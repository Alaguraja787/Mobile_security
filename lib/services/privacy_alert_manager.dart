import 'package:flutter/foundation.dart';
import '../guardian/agent/models/agent_necessity_evaluation.dart';
import '../models/app_telemetry.dart';
import '../models/sensor_access_event.dart';
import 'permission_intelligence_analyzer.dart';

enum AlertSeverity {
  critical,
  review,
  info,
}

class PrivacyAlert {
  final String id;
  final String appName;
  final String packageName;
  final String permission;
  final String previousState; // e.g. "DENIED", "UNGRANTED"
  final String currentState;  // e.g. "GRANTED", "ACCESSED"
  final AlertSeverity severity;
  final DateTime timestamp;
  final String reason;
  final String guardianExplanation;
  final String recommendation;
  final AgentRecommendation? agentRecommendation;
  final double? necessityScore;
  final bool? isForeground;
  final SensorType? sensorType;
  String actionStatus; // 'PENDING', 'ALLOWED', 'BLOCKED'

  PrivacyAlert({
    required this.id,
    required this.appName,
    required this.packageName,
    required this.permission,
    required this.previousState,
    required this.currentState,
    required this.severity,
    required this.timestamp,
    required this.reason,
    required this.guardianExplanation,
    required this.recommendation,
    this.agentRecommendation,
    this.necessityScore,
    this.isForeground,
    this.sensorType,
    this.actionStatus = 'PENDING',
  });

  String get severityLabel {
    switch (severity) {
      case AlertSeverity.critical:
        return 'CRITICAL';
      case AlertSeverity.review:
        return 'REVIEW';
      case AlertSeverity.info:
        return 'INFO';
    }
  }

  bool get isBlockRecommended => agentRecommendation == AgentRecommendation.block;
  bool get isAllowRecommended => agentRecommendation == AgentRecommendation.allow;
  bool get isReviewRecommended => agentRecommendation == AgentRecommendation.askUser;
}

/// Real-time Privacy Alert Manager that diffs telemetry snapshots
/// and records autonomous Agent evaluations whenever sensor access occurs.
class PrivacyAlertManager extends ChangeNotifier {
  final List<PrivacyAlert> _alerts = [];
  final Map<String, Set<String>> _previousGrantedPermissions = {};
  final PermissionIntelligenceAnalyzer _analyzer = PermissionIntelligenceAnalyzer();

  List<PrivacyAlert> get alerts => List.unmodifiable(_alerts);

  List<PrivacyAlert> get criticalAlerts =>
      _alerts.where((a) => a.severity == AlertSeverity.critical).toList();

  List<PrivacyAlert> get reviewAlerts =>
      _alerts.where((a) => a.severity == AlertSeverity.review).toList();

  List<PrivacyAlert> get infoAlerts =>
      _alerts.where((a) => a.severity == AlertSeverity.info).toList();

  /// Process autonomous Agent necessity evaluation
  void processAgentEvaluation(AgentNecessityEvaluation evaluation) {
    final AlertSeverity severity;
    switch (evaluation.recommendation) {
      case AgentRecommendation.block:
        severity = AlertSeverity.critical;
        break;
      case AgentRecommendation.askUser:
        severity = AlertSeverity.review;
        break;
      case AgentRecommendation.allow:
        severity = AlertSeverity.info;
        break;
    }

    final alert = PrivacyAlert(
      id: evaluation.evaluationId,
      appName: evaluation.appName,
      packageName: evaluation.packageName,
      permission: '${evaluation.sensorType.label.toUpperCase()}_ACCESS',
      previousState: 'INACTIVE',
      currentState: 'ACCESSED',
      severity: severity,
      timestamp: evaluation.timestamp,
      reason: evaluation.primaryReason,
      guardianExplanation: evaluation.detailedExplanation,
      recommendation: 'AI Recommendation: ${evaluation.recommendation.humanLabel}',
      agentRecommendation: evaluation.recommendation,
      necessityScore: evaluation.necessityScore,
      isForeground: evaluation.isForeground,
      sensorType: evaluation.sensorType,
      actionStatus: 'PENDING',
    );

    // Remove older duplicate pending alert for same package and sensor to keep list clean
    _alerts.removeWhere((a) =>
        a.packageName == alert.packageName &&
        a.permission == alert.permission &&
        a.actionStatus == 'PENDING' &&
        alert.timestamp.difference(a.timestamp).inSeconds.abs() < 10);

    _alerts.insert(0, alert);
    if (_alerts.length > 100) {
      _alerts.removeRange(100, _alerts.length);
    }
    notifyListeners();
  }

  /// Updates user decision state ('ALLOWED', 'BLOCKED')
  void updateAlertActionStatus(String alertId, String newStatus) {
    final idx = _alerts.indexWhere((a) => a.id == alertId);
    if (idx != -1) {
      _alerts[idx].actionStatus = newStatus;
      notifyListeners();
    }
  }

  /// Process new batch of AppTelemetry and detect state transitions
  void processTelemetryBatch(List<AppTelemetry> apps) {
    bool hasNewAlerts = false;

    for (final app in apps) {
      final Set<String> currentGranted = Set.from(app.grantedPermissions);
      final Set<String>? prevGranted = _previousGrantedPermissions[app.packageName];

      if (prevGranted != null) {
        // Detect permissions newly granted
        final newlyGranted = currentGranted.difference(prevGranted);
        for (final perm in newlyGranted) {
          final alert = _generatePermissionChangeAlert(
            app: app,
            permission: perm,
            previousState: 'DENIED',
            currentState: 'GRANTED',
          );
          _alerts.insert(0, alert);
          hasNewAlerts = true;
        }

        // Detect permissions revoked
        final newlyRevoked = prevGranted.difference(currentGranted);
        for (final perm in newlyRevoked) {
          final alert = _generatePermissionChangeAlert(
            app: app,
            permission: perm,
            previousState: 'GRANTED',
            currentState: 'DENIED',
          );
          _alerts.insert(0, alert);
          hasNewAlerts = true;
        }
      } else {
        // First snapshot initialization for this package — alert only for genuine high-risk anomalies on non-system apps
        final riskRes = _analyzer.analyzeApp(app);
        if (riskRes.level == PermissionRiskLevel.critical) {
          final topFlagged = riskRes.flaggedPermissions.isNotEmpty ? riskRes.flaggedPermissions.first : null;
          final alert = PrivacyAlert(
            id: 'init_${app.packageName}',
            appName: app.appName,
            packageName: app.packageName,
            permission: topFlagged?.permission ?? 'HIGH_RISK_PERMISSIONS',
            previousState: 'UNKNOWN',
            currentState: 'GRANTED',
            severity: riskRes.level == PermissionRiskLevel.critical ? AlertSeverity.critical : AlertSeverity.review,
            timestamp: DateTime.now(),
            reason: riskRes.summaryReason,
            guardianExplanation: topFlagged?.sensitivityReason ?? riskRes.summaryReason,
            recommendation: 'Review application permissions in system settings.',
            actionStatus: 'PENDING',
          );
          _alerts.add(alert);
          hasNewAlerts = true;
        }
      }

      _previousGrantedPermissions[app.packageName] = currentGranted;
    }

    if (hasNewAlerts) {
      notifyListeners();
    }
  }

  PrivacyAlert _generatePermissionChangeAlert({
    required AppTelemetry app,
    required String permission,
    required String previousState,
    required String currentState,
  }) {
    final String simpleName = permission.contains('.') ? permission.split('.').last : permission;
    final bool isSensitive = simpleName.contains('MICROPHONE') ||
        simpleName.contains('CAMERA') ||
        simpleName.contains('LOCATION') ||
        simpleName.contains('CONTACTS') ||
        simpleName.contains('RECORD_AUDIO') ||
        simpleName.contains('SMS');

    final AlertSeverity severity;
    if (currentState == 'DENIED') {
      severity = AlertSeverity.info;
    } else if (app.hasOverlayOp && isSensitive) {
      severity = AlertSeverity.critical;
    } else if (isSensitive) {
      severity = AlertSeverity.review;
    } else {
      severity = AlertSeverity.info;
    }

    String guardianExplanation = 'Permission "$simpleName" state changed from $previousState to $currentState.';
    if (isSensitive && currentState == 'GRANTED') {
      guardianExplanation =
          'Permission "$simpleName" was enabled. This gives the app access to sensor/system capabilities when activated. Review if this change was intentional.';
    }

    return PrivacyAlert(
      id: 'alert_${DateTime.now().millisecondsSinceEpoch}_${app.packageName}_$simpleName',
      appName: app.appName,
      packageName: app.packageName,
      permission: simpleName,
      previousState: previousState,
      currentState: currentState,
      severity: severity,
      timestamp: DateTime.now(),
      reason: 'Permission state transition detected.',
      guardianExplanation: guardianExplanation,
      recommendation: 'Verify application settings if this permission change was unexpected.',
      actionStatus: 'PENDING',
    );
  }

  void processSensorAccessEvent(SensorAccessEvent event) {
    if (event.state != SensorAccessState.started && event.state != SensorAccessState.active) {
      return;
    }

    final appName = event.appName ?? event.packageName ?? 'An application';
    final pkg = event.packageName ?? 'system';
    final isMedia = event.sensorType == SensorType.photos ||
        event.sensorType == SensorType.files ||
        event.sensorType == SensorType.videos ||
        event.sensorType == SensorType.audioFiles;

    final AlertSeverity severity = event.isScreenLocked
        ? AlertSeverity.critical
        : (isMedia ? AlertSeverity.review : AlertSeverity.info);

    final String reason = event.isScreenLocked
        ? 'Background resource accessed while screen was locked'
        : '${event.sensorType.label} access detected';

    final String fileInfo = event.fileName != null ? ' ("${event.fileName}")' : '';
    final String explanation = event.isScreenLocked
        ? '⚠️ Suspicious Background Access: $appName accessed ${event.sensorType.label}$fileInfo while your device screen was locked!'
        : '$appName accessed ${event.sensorType.label}$fileInfo.';

    final alert = PrivacyAlert(
      id: event.eventId ?? 'sensor_${DateTime.now().millisecondsSinceEpoch}_$pkg',
      appName: appName,
      packageName: pkg,
      permission: '${event.sensorType.label.toUpperCase()}_ACCESS',
      previousState: 'INACTIVE',
      currentState: 'ACCESSED',
      severity: severity,
      timestamp: event.timestamp,
      reason: reason,
      guardianExplanation: explanation,
      recommendation: event.isScreenLocked
          ? 'Investigate why this application was accessing resources in the background while the phone was locked.'
          : 'Verify if you intended to grant $appName access to ${event.sensorType.label.toLowerCase()}.',
      sensorType: event.sensorType,
      actionStatus: 'PENDING',
    );

    _alerts.insert(0, alert);
    if (_alerts.length > 100) {
      _alerts.removeRange(100, _alerts.length);
    }
    notifyListeners();
  }

  void clearAlerts() {
    _alerts.clear();
    notifyListeners();
  }
}
