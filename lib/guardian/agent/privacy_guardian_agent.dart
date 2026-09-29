import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import '../../models/sensor_access_event.dart';
import '../../services/guardian_service.dart';
import '../../services/privacy_alert_manager.dart';
import '../../services/privacy_notification_service.dart';
import '../../services/sensor_access_service.dart';
import '../../telemetry/telemetry_service.dart';
import 'context_necessity_evaluator.dart';
import 'models/agent_necessity_evaluation.dart';

class AgentPolicyConfig {
  final bool autoBlockBackgroundCamera;
  final bool autoBlockBackgroundMic;
  final bool autoBlockScreenLockedAccess;
  final Set<String> trustedCameraPackages;

  const AgentPolicyConfig({
    this.autoBlockBackgroundCamera = false, // Human-in-the-loop by default!
    this.autoBlockBackgroundMic = false,    // Human-in-the-loop by default!
    this.autoBlockScreenLockedAccess = false,
    this.trustedCameraPackages = const {},
  });

  AgentPolicyConfig copyWith({
    bool? autoBlockBackgroundCamera,
    bool? autoBlockBackgroundMic,
    bool? autoBlockScreenLockedAccess,
    Set<String>? trustedCameraPackages,
  }) {
    return AgentPolicyConfig(
      autoBlockBackgroundCamera: autoBlockBackgroundCamera ?? this.autoBlockBackgroundCamera,
      autoBlockBackgroundMic: autoBlockBackgroundMic ?? this.autoBlockBackgroundMic,
      autoBlockScreenLockedAccess: autoBlockScreenLockedAccess ?? this.autoBlockScreenLockedAccess,
      trustedCameraPackages: trustedCameraPackages ?? this.trustedCameraPackages,
    );
  }
}

/// Autonomous AI Privacy Guardian Agent.
///
/// Implements the proactive agentic cycle:
/// DETECT -> ATTRIBUTE -> ANALYZE CONTEXT -> EVALUATE NECESSITY -> RECOMMEND -> HUMAN APPROVAL.
///
/// Transforms the passive chatbot into an active real-time privacy sentinel.
class PrivacyGuardianAgent extends ChangeNotifier {
  final SensorAccessService sensorAccessService;
  final TelemetryService telemetryService;
  final PrivacyAlertManager alertManager;
  final PrivacyNotificationService notificationService;
  final GuardianService guardianService;
  final ContextNecessityEvaluator evaluator;

  StreamSubscription<SensorAccessEvent>? _sensorSubscription;
  final List<AgentNecessityEvaluation> _recentEvaluations = [];
  final Map<String, AgentRecommendation> _userDecisions = {};
  AgentPolicyConfig _policyConfig = const AgentPolicyConfig();

  List<AgentNecessityEvaluation> get recentEvaluations => List.unmodifiable(_recentEvaluations);
  Map<String, AgentRecommendation> get userDecisions => Map.unmodifiable(_userDecisions);
  AgentPolicyConfig get policyConfig => _policyConfig;

  PrivacyGuardianAgent({
    required this.sensorAccessService,
    required this.telemetryService,
    required this.alertManager,
    required this.notificationService,
    required this.guardianService,
    this.evaluator = const ContextNecessityEvaluator(),
    AgentPolicyConfig? initialPolicyConfig,
  }) : _policyConfig = initialPolicyConfig ?? const AgentPolicyConfig();

  void updatePolicyConfig(AgentPolicyConfig newConfig) {
    _policyConfig = newConfig;
    notifyListeners();
  }

  /// Starts autonomous monitoring of sensor access events
  void start() {
    if (_sensorSubscription != null) return;

    developer.log('PRIVACY_GUARDIAN_AGENT_STARTED', name: 'PrivacyGuardianAgent');
    _sensorSubscription = sensorAccessService.eventStream.listen(_onSensorEventReceived);
  }

  /// Stops autonomous monitoring
  void stop() {
    _sensorSubscription?.cancel();
    _sensorSubscription = null;
    developer.log('PRIVACY_GUARDIAN_AGENT_STOPPED', name: 'PrivacyGuardianAgent');
  }

  /// Autonomous Evaluation Pipeline when a sensor hardware event is detected
  Future<void> _onSensorEventReceived(SensorAccessEvent event) async {
    // Only evaluate active or started states with known package attribution
    if (event.state != SensorAccessState.started && event.state != SensorAccessState.active) {
      return;
    }
    if (event.packageName == null || event.packageName!.isEmpty) {
      return;
    }

    try {
      final pkg = event.packageName!;
      developer.log('AGENT_SENSOR_TRIGGER: sensor=${event.sensorType.label} app=$pkg', name: 'PrivacyGuardianAgent');

      // 1. Gather live on-device context
      final latestTelemetry = telemetryService.latestEvent;
      final String? activeForegroundPkg = guardianService.inventoryContext.currentSnapshot?.getLastUsedApp()?.packageName;

      // 2. Fetch application profile for app metadata
      final snapshot = guardianService.inventoryContext.currentSnapshot;
      final appProfile = snapshot?.applications.where((a) => a.packageName == pkg).firstOrNull;

      // 3. Context & Functional Necessity Evaluation
      final evaluation = evaluator.evaluate(
        event: event,
        activeForegroundPackage: activeForegroundPkg,
        appNameOverride: appProfile?.appName,
        isScreenLocked: event.isScreenLocked || (latestTelemetry?.deviceContext.screenLocked ?? false),
      );

      _recentEvaluations.insert(0, evaluation);
      if (_recentEvaluations.length > 50) {
        _recentEvaluations.removeRange(50, _recentEvaluations.length);
      }

      developer.log(
        'AGENT_DECISION_EMITTED: [${evaluation.recommendation.label}] ${evaluation.appName}: "${evaluation.primaryReason}"',
        name: 'PrivacyGuardianAgent',
      );

      // Check if user has autonomous policy configured to auto-block
      bool shouldAutoBlock = false;
      if (evaluation.recommendation == AgentRecommendation.block) {
        if (_policyConfig.autoBlockScreenLockedAccess && evaluation.isScreenLocked) {
          shouldAutoBlock = true;
        } else if (_policyConfig.autoBlockBackgroundCamera &&
            !evaluation.isForeground &&
            evaluation.sensorType == SensorType.camera) {
          shouldAutoBlock = true;
        } else if (_policyConfig.autoBlockBackgroundMic &&
            !evaluation.isForeground &&
            evaluation.sensorType == SensorType.microphone) {
          shouldAutoBlock = true;
        }
      }

      if (shouldAutoBlock) {
        developer.log('AUTONOMOUS_POLICY_BLOCK: ${evaluation.packageName} on ${evaluation.sensorType.label}', name: 'PrivacyGuardianAgent');
        await sensorAccessService.blockSensorAccess(
          packageName: evaluation.packageName,
          sensor: evaluation.sensorType,
          appName: evaluation.appName,
        );
        _userDecisions[evaluation.evaluationId] = AgentRecommendation.block;
        alertManager.processAgentEvaluation(evaluation);
        alertManager.updateAlertActionStatus(evaluation.evaluationId, 'BLOCKED_BY_POLICY');
      } else {
        // Human-Approved Governance (Default):
        // 4. Update Alert Center with Agent Recommendation and Contextual Justification
        alertManager.processAgentEvaluation(evaluation);

        // 5. Dispatch Actionable Notification with Human-in-the-Loop choices
        await notificationService.handleAgentEvaluation(evaluation);
      }

      notifyListeners();
    } catch (e, stack) {
      developer.log('AGENT_EVALUATION_ERROR: $e\n$stack', name: 'PrivacyGuardianAgent');
    }
  }

  /// Human-Approved Governance: Executes user confirmation
  Future<Map<String, dynamic>> handleUserDecision({
    required String evaluationId,
    required AgentRecommendation decision,
    String? packageName,
    SensorType? sensorType,
    String? appName,
  }) async {
    final evaluation = _recentEvaluations.where((e) => e.evaluationId == evaluationId).firstOrNull;
    final targetPkg = evaluation?.packageName ?? packageName;
    final targetSensor = evaluation?.sensorType ?? sensorType;
    final targetAppName = evaluation?.appName ?? appName ?? targetPkg ?? 'Unknown App';

    _userDecisions[evaluationId] = decision;
    developer.log(
      'USER_GOVERNANCE_DECISION: evaluationId=$evaluationId decision=${decision.label} for $targetPkg',
      name: 'PrivacyGuardianAgent',
    );

    if (decision == AgentRecommendation.block) {
      if (targetPkg != null && targetSensor != null) {
        // Execute privileged block remediation via Shizuku / native layer
        final result = await sensorAccessService.blockSensorAccess(
          packageName: targetPkg,
          sensor: targetSensor,
          appName: targetAppName,
        );

        alertManager.updateAlertActionStatus(evaluationId, 'BLOCKED');
        notifyListeners();
        return result;
      }
      return {'success': false, 'error': 'PACKAGE_OR_SENSOR_MISSING'};
    } else if (decision == AgentRecommendation.allow) {
      alertManager.updateAlertActionStatus(evaluationId, 'ALLOWED');
      notifyListeners();
      return {'success': true, 'action': 'ALLOWED'};
    } else {
      alertManager.updateAlertActionStatus(evaluationId, 'REVIEW_REQUESTED');
      notifyListeners();
      return {'success': true, 'action': 'REVIEW_REQUESTED'};
    }
  }

  /// Restores access for an app previously blocked
  Future<Map<String, dynamic>> restoreUserDecision({
    required String evaluationId,
    required String packageName,
    required SensorType sensorType,
    required String appName,
  }) async {
    final result = await sensorAccessService.restoreSensorAccess(
      packageName: packageName,
      sensor: sensorType,
      appName: appName,
    );
    if (result['success'] == true) {
      _userDecisions.remove(evaluationId);
      alertManager.updateAlertActionStatus(evaluationId, 'PENDING');
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
