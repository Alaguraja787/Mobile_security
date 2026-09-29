// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/app_telemetry.dart';
import '../../models/privacy_event.dart';
import '../../models/sensor_access_event.dart';
import '../../services/device_connection_manager.dart';
import '../../services/permission_intelligence_analyzer.dart';
import '../../services/privacy_alert_manager.dart';
import '../../services/sensor_access_service.dart';
import '../../telemetry/app_telemetry_builder.dart';
import '../../telemetry/telemetry_service.dart';
import '../../telemetry/collectors/android_collector.dart';
import '../../widgets/app_icon_widget.dart';
import '../settings/settings_screen.dart';
import 'sensor_session_screen.dart';
import 'widgets/dashboard_charts.dart';

class DashboardScreen extends StatefulWidget {
  final TelemetryService telemetryService;
  final SensorAccessService? sensorAccessService;
  final VoidCallback? onNavigateToApps;
  final VoidCallback? onNavigateToAlerts;
  final VoidCallback? onNavigateToGuardian;

  const DashboardScreen({
    super.key,
    required this.telemetryService,
    this.sensorAccessService,
    this.onNavigateToApps,
    this.onNavigateToAlerts,
    this.onNavigateToGuardian,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final AppTelemetryBuilder _builder = AppTelemetryBuilder();
  final PermissionIntelligenceAnalyzer _analyzer = PermissionIntelligenceAnalyzer();

  List<AppTelemetry> _apps = [];
  List<PermissionRiskResult> _evaluations = [];
  DevicePrivacyScoreBreakdown? _cachedBreakdown;
  int _cachedTotalPermissions = 0;
  bool _cachedHasUsageAccess = false;
  bool _isLoading = true;
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    (widget.sensorAccessService ?? SensorAccessService.shared).reconcileWithPlatform();

    if (widget.telemetryService.latestEvent != null) {
      final builtApps = _builder.build(widget.telemetryService.latestEvent!);
      _updateTelemetryData(builtApps);
    }
    _listenTelemetry();

    // Smoothly refresh active sensor durations and relative timestamps every second
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      (widget.sensorAccessService ?? SensorAccessService.shared).reconcileWithPlatform();
    }
  }

  void _updateTelemetryData(List<AppTelemetry> builtApps, [PrivacyEvent? event]) {
    final evals = builtApps.map((a) => _analyzer.analyzeApp(a)).toList();
    _apps = builtApps;
    _evaluations = evals;
    _cachedBreakdown = _analyzer.calculateDevicePrivacyScoreBreakdown(evals);
    _cachedTotalPermissions = builtApps.fold(0, (sum, a) => sum + a.requestedPermissions.length);
    _cachedHasUsageAccess = (event?.usageSummary.usageAccessGranted ?? false) ||
        builtApps.any((a) =>
            a.usageDataState != 'USAGE_DATA_UNAVAILABLE' &&
            a.usageAvailability != 'USAGE_DATA_UNAVAILABLE');
    _isLoading = false;
  }

  void _listenTelemetry() {
    widget.telemetryService.stream.listen((PrivacyEvent event) {
      final builtApps = _builder.build(event);
      if (!mounted) return;
      setState(() {
        _updateTelemetryData(builtApps, event);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final deviceManager = Provider.of<DeviceConnectionManager>(context);
    final alertManager = Provider.of<PrivacyAlertManager>(context);
    final sensorAccessService = Provider.of<SensorAccessService?>(context);

    final int totalApps = _apps.length;
    final int totalPermissions = _cachedTotalPermissions;
    final breakdown = _cachedBreakdown ?? _analyzer.calculateDevicePrivacyScoreBreakdown(_evaluations);
    final int needReviewCount = breakdown.reviewCount + breakdown.highCount + breakdown.criticalCount;
    final int activeAlertsCount = alertManager.alerts.length;
    final int privacyHealthScore = breakdown.overallScore;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Telemetry',
            onPressed: () => widget.telemetryService.refreshOnce(forceRefresh: true),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings & Precise Attribution',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  collector: widget.telemetryService.collector,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Discovering connected device telemetry...',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => widget.telemetryService.refreshOnce(forceRefresh: true),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // 1. Connected Device
                  _buildHeaderCard(deviceManager),
                  const SizedBox(height: 16),

                  // Locked Screen Activity Banner (Prominent warning when background activity occurs while phone is locked)
                  if (sensorAccessService != null)
                    _buildLockedScreenAlertsBanner(sensorAccessService),

                  // 2. LIVE PRIVACY ACTIVITY & 3. RECENT SENSOR ACTIVITY
                  _buildSensorMonitoringBlock(context, sensorAccessService),
                  const SizedBox(height: 16),

                  // 4. Risk Distribution Donut Chart
                  RiskDistributionDonutChart(
                    breakdown: breakdown,
                    onAskGuardian: widget.onNavigateToGuardian,
                  ),
                  const SizedBox(height: 16),

                  // 5. Today's App Usage Bar Chart
                  AppUsageBarChart(
                    apps: _apps,
                    hasUsageAccess: _cachedHasUsageAccess,
                    onOpenUsageSettings: () =>
                        widget.telemetryService.collector.openUsageAccessSettings(),
                  ),
                  const SizedBox(height: 16),

                  // 6. Permission Distribution Chart
                  PermissionDistributionChart(apps: _apps),
                  const SizedBox(height: 16),

                  // 7. Existing Privacy Alerts
                  _buildRecentAlertsSection(alertManager),
                  const SizedBox(height: 16),

                  // 8. Privacy Health Score & Overview Metrics
                  _buildPrivacyHealthCard(privacyHealthScore, needReviewCount, breakdown),
                  const SizedBox(height: 16),
                  _buildOverviewMetrics(
                    totalApps: totalApps,
                    totalPermissions: totalPermissions,
                    needReview: needReviewCount,
                    activeAlerts: activeAlertsCount,
                  ),
                  const SizedBox(height: 16),

                  // 9. Device & System Context
                  _buildConnectedDeviceDetailsCard(deviceManager),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard(DeviceConnectionManager deviceManager) {
    final info = deviceManager.deviceInfo;
    final bool isConnected = deviceManager.status == DeviceConnectionStatus.connected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.surface,
            AppColors.primary.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardGlassBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isConnected ? AppColors.statusNormal.withValues(alpha: 0.2) : AppColors.statusAttention.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.phone_android,
              color: isConnected ? AppColors.statusNormal : AppColors.statusAttention,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CONNECTED DEVICE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  info?.deviceName ?? 'Searching device...',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  info != null ? 'Android ${info.androidVersion} • ${info.connectionMethod}' : 'Initializing bridge...',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isConnected ? AppColors.statusNormal.withValues(alpha: 0.15) : AppColors.statusAttention.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected ? AppColors.statusNormal : AppColors.statusAttention,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected ? AppColors.statusNormal : AppColors.statusAttention,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isConnected ? AppColors.statusNormal : AppColors.statusAttention,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedScreenAlertsBanner(SensorAccessService sensorService) {
    final locked = sensorService.lockedScreenEvents;
    if (locked.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.shade900.withValues(alpha: 0.35),
            AppColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_clock, color: Colors.redAccent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LOCKED SCREEN ACTIVITY DETECTED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Colors.redAccent,
                      ),
                    ),
                    Text(
                      '${locked.length} background access event(s) occurred while your phone was locked.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...locked.take(3).map((e) {
            final appName = e.appName ?? e.packageName ?? 'An application';
            final desc = e.fileName != null
                ? '$appName accessed "${e.fileName}"'
                : '$appName accessed ${e.sensorType.label.toLowerCase()}';
            final time = SensorAccessService.formatRelativeTime(e.timestamp);
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SensorSessionScreen(
                      initialSensorType: e.sensorType,
                      sensorService: sensorService,
                      telemetryService: widget.telemetryService,
                    ),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(e.sensorType.iconEmoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        desc,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 14, color: AppColors.textMuted),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOverviewMetrics({
    required int totalApps,
    required int totalPermissions,
    required int needReview,
    required int activeAlerts,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = (constraints.maxWidth - 24) / (constraints.maxWidth > 600 ? 4 : 2);

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildMetricTile(
              width: cardWidth,
              title: 'Apps',
              value: '$totalApps',
              icon: Icons.apps,
              iconColor: AppColors.primary,
              onTap: widget.onNavigateToApps,
            ),
            _buildMetricTile(
              width: cardWidth,
              title: 'Permissions',
              value: '$totalPermissions',
              icon: Icons.security,
              iconColor: AppColors.accentCyan,
              onTap: widget.onNavigateToApps,
            ),
            _buildMetricTile(
              width: cardWidth,
              title: 'Need Review',
              value: '$needReview',
              icon: Icons.warning_amber_rounded,
              iconColor: AppColors.statusReview,
              onTap: widget.onNavigateToApps,
            ),
            _buildMetricTile(
              width: cardWidth,
              title: 'Active Alerts',
              value: '$activeAlerts',
              icon: Icons.notifications_active,
              iconColor: AppColors.statusAttention,
              onTap: widget.onNavigateToAlerts,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricTile({
    required double width,
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(icon, color: iconColor, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyHealthCard(int score, int needReviewCount, [DevicePrivacyScoreBreakdown? breakdown]) {
    Color scoreColor = AppColors.statusNormal;
    if (score < 60) {
      scoreColor = AppColors.statusAttention;
    } else if (score < 85) {
      scoreColor = AppColors.statusReview;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: CircularProgressIndicator(
                      value: score / 100.0,
                      strokeWidth: 8,
                      backgroundColor: AppColors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                    ),
                  ),
                  Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Privacy Health Score',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      needReviewCount > 0
                          ? '$needReviewCount app(s) warrant privacy review based on granted capability groups.'
                          : 'Excellent! All granted application permissions match typical operational bounds.',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: widget.onNavigateToGuardian,
                      icon: const Icon(Icons.record_voice_over, size: 16),
                      label: const Text('Ask Guardian AI'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (breakdown != null) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.surfaceBorder, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBreakdownChip('Expected', breakdown.expectedCount, AppColors.statusNormal),
                _buildBreakdownChip('Low', breakdown.lowCount, AppColors.statusNormal),
                _buildBreakdownChip('Review', breakdown.reviewCount, AppColors.statusReview),
                _buildBreakdownChip('High', breakdown.highCount, AppColors.statusAttention),
                _buildBreakdownChip('Critical', breakdown.criticalCount, Colors.redAccent),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownChip(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildRecentAlertsSection(PrivacyAlertManager alertManager) {
    final recent = alertManager.alerts.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Privacy Alerts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            TextButton(
              onPressed: widget.onNavigateToAlerts,
              child: const Text('View All', style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppColors.statusNormal, size: 20),
                SizedBox(width: 12),
                Text('No recent permission alert events detected.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          )
        else
          Column(
            children: recent.map((alert) {
              Color severityColor = AppColors.statusNormal;
              if (alert.severity == AlertSeverity.critical) {
                severityColor = AppColors.statusAttention;
              } else if (alert.severity == AlertSeverity.review) {
                severityColor = AppColors.statusReview;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      alert.severity == AlertSeverity.critical ? Icons.warning : Icons.info_outline,
                      color: severityColor,
                      size: 20,
                    ),
                  ),
                  title: Text(alert.appName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${alert.permission} • ${alert.currentState}', style: const TextStyle(fontSize: 12)),
                  trailing: Text(
                    alert.severityLabel,
                    style: TextStyle(color: severityColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildConnectedDeviceDetailsCard(DeviceConnectionManager deviceManager) {
    final info = deviceManager.deviceInfo;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Device & System Context', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const Divider(height: 20, color: AppColors.surfaceBorder),
          _buildDetailRow('Device Model', info?.deviceName ?? 'Unknown'),
          _buildDetailRow('Android OS Version', info?.androidVersion ?? 'Unknown'),
          _buildDetailRow('API Level / SDK', info != null ? '${info.sdkVersion}' : 'Unknown'),
          _buildDetailRow('Connection Method', info?.connectionMethod ?? 'Unknown'),
          _buildDetailRow('Last Telemetry Sync', info != null ? '${info.lastSync.hour}:${info.lastSync.minute}:${info.lastSync.second}' : 'Never'),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildSensorMonitoringBlock(BuildContext context, SensorAccessService? propService) {
    final service = propService ??
        Provider.of<SensorAccessService?>(context) ??
        SensorAccessService.shared;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        print('DASHBOARD_RECEIVED: activeCount=${service.activeSessions.length} recentCount=${service.recentEvents.length}');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLivePrivacyActivitySection(service),
            const SizedBox(height: 16),
            _buildRecentSensorActivitySection(service),
          ],
        );
      },
    );
  }

  Widget _buildLivePrivacyActivitySection(SensorAccessService sensorService) {
    final activeSessions = sensorService.activeSessions;
    final bool hasActiveSessions = activeSessions.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasActiveSessions
            ? AppColors.statusAttention.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasActiveSessions
              ? AppColors.statusAttention.withValues(alpha: 0.6)
              : AppColors.surfaceBorder,
          width: hasActiveSessions ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      hasActiveSessions ? Icons.sensors : Icons.sensors_off,
                      color: hasActiveSessions ? AppColors.statusAttention : AppColors.statusNormal,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'LIVE PRIVACY ACTIVITY',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasActiveSessions)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.statusAttention.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.statusAttention),
                  ),
                  child: const Text(
                    '● LIVE',
                    style: TextStyle(
                      color: AppColors.statusAttention,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.statusNormal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.statusNormal.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'IDLE',
                    style: TextStyle(
                      color: AppColors.statusNormal,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LiveSensorMiniVisualizer(
            sensorService: sensorService,
            onSensorTap: (sensorType) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SensorSessionScreen(
                    initialSensorType: sensorType,
                    sensorService: sensorService,
                    telemetryService: widget.telemetryService,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          if (hasActiveSessions)
            Column(
              children: activeSessions.map((event) {
                final bool isAppVerified = event.isAppAttributed &&
                    event.appName != null &&
                    event.appName!.trim().isNotEmpty;

                final String appDisplay = isAppVerified
                    ? event.appName!
                    : (event.isAppAttributed && event.packageName != null && event.packageName!.trim().isNotEmpty)
                        ? event.packageName!
                        : 'App identity unavailable';

                final String activeDuration = SensorAccessService.formatActiveDuration(event.timestamp);

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SensorSessionScreen(
                          initialSensorType: event.sensorType,
                          sensorService: sensorService,
                          telemetryService: widget.telemetryService,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.surfaceBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (isAppVerified && event.packageName != null)
                          AppIconWidget(
                            packageName: event.packageName!,
                            appName: appDisplay,
                            size: 46,
                            borderRadius: 12,
                          )
                        else
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.surfaceBorder),
                            ),
                            child: Center(
                              child: Text(
                                event.sensorType.iconEmoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      appDisplay,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isAppVerified ? AppColors.textPrimary : AppColors.textMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isAppVerified
                                          ? AppColors.statusNormal.withValues(alpha: 0.15)
                                          : AppColors.statusReview.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: isAppVerified
                                        ? const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'APP LEVEL • ',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.statusNormal,
                                                ),
                                              ),
                                              Text(
                                                'VERIFIED',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.statusNormal,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Text(
                                            'DEVICE LEVEL',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.statusReview,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Builder(
                                builder: (context) {
                                  final String statusDesc = (event.fileName != null && event.fileName!.isNotEmpty)
                                      ? (event.sensorType == SensorType.photos
                                          ? 'Accessed photo "${event.fileName}" • $activeDuration'
                                          : 'Accessed file "${event.fileName}" • $activeDuration')
                                      : 'Using ${event.sensorType.label.toLowerCase()} now • $activeDuration';
                                  return Text(
                                    statusDesc,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.statusAttention,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                              if (isAppVerified && event.packageName != null && event.packageName!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                if (sensorService.isAppBlocked(event.packageName!, event.sensorType))
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.statusAttention.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.statusAttention.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${event.sensorType.label.toUpperCase()} = DENIED',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.statusAttention,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () => _handleRestoreSensor(
                                            context,
                                            sensorService,
                                            event.packageName!,
                                            event.sensorType,
                                            appDisplay,
                                          ),
                                          child: const Text(
                                            'ALLOW AGAIN',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.block, size: 13, color: AppColors.statusAttention),
                                    label: Text(
                                      'BLOCK ${event.sensorType.label.toUpperCase()}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.statusAttention,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppColors.statusAttention),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _handleBlockSensor(
                                      context,
                                      sensorService,
                                      event,
                                      appDisplay,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '● LIVE',
                              style: TextStyle(
                                color: AppColors.statusAttention,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            )
          else
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.statusNormal, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No active camera, microphone, or location access',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          if (sensorService.blockedApps.isNotEmpty) ...[
            const Divider(height: 20),
            const Row(
              children: [
                Icon(Icons.security, size: 14, color: AppColors.statusAttention),
                SizedBox(width: 6),
                Text(
                  'BLOCKED SENSOR ACCESS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...sensorService.blockedApps.entries.expand((entry) {
              final pkg = entry.key;
              final matchingApp = _apps.where((a) => a.packageName == pkg).firstOrNull;
              final recentMatch = sensorService.recentEvents.where((e) => e.packageName == pkg && e.appName != null).firstOrNull;
              final appName = matchingApp?.appName ?? recentMatch?.appName ?? pkg;

              return entry.value.map((sensor) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.statusReview.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.statusReview.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            AppIconWidget(
                              packageName: pkg,
                              appName: appName,
                              size: 40,
                              borderRadius: 10,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${sensor.iconEmoji} ${sensor.label} access blocked',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.statusAttention,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.statusAttention.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${sensor.label.toUpperCase()} = DENIED',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: AppColors.statusAttention,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _handleRestoreSensor(context, sensorService, pkg, sensor, appName),
                        child: const Text('ALLOW AGAIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              });
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentSensorActivitySection(SensorAccessService sensorService) {
    final recentEvents = sensorService.recentEvents;
    final bool hasRecentEvents = recentEvents.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'RECENT SENSOR ACTIVITY',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (hasRecentEvents)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${recentEvents.length} events',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasRecentEvents)
            Column(
              children: recentEvents.take(10).map((event) {
                final bool isAppVerified = event.isAppAttributed &&
                    event.appName != null &&
                    event.appName!.trim().isNotEmpty;

                final String title = isAppVerified
                    ? event.appName!
                    : (event.isAppAttributed && event.packageName != null)
                        ? event.packageName!
                        : event.sensorType.label;

                final String relativeTime =
                    SensorAccessService.formatRelativeTime(event.timestamp);

                final bool isBlocked = event.blockedState ||
                    sensorService.isAppBlocked(event.packageName ?? '', event.sensorType);

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SensorSessionScreen(
                          initialSensorType: event.sensorType,
                          sensorService: sensorService,
                          telemetryService: widget.telemetryService,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isBlocked
                            ? AppColors.statusAttention.withValues(alpha: 0.4)
                            : AppColors.surfaceBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isAppVerified && event.packageName != null)
                              AppIconWidget(
                                packageName: event.packageName!,
                                appName: title,
                                size: 42,
                                borderRadius: 10,
                              )
                            else
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.surfaceBorder),
                                ),
                                child: Center(
                                  child: Text(
                                    event.sensorType.iconEmoji,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${event.sensorType.iconEmoji} ${event.sensorType.label} • Used $relativeTime',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (event.fileName != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '${event.sensorType == SensorType.photos ? "🖼️ Photo" : "📁 File"}: ${event.fileName}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.accentCyan,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (event.isScreenLocked) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.lock, size: 10, color: Colors.redAccent),
                                          SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'LOCKED SCREEN ACCESS',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.redAccent,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (isBlocked) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '${event.sensorType.label.toUpperCase()} = DENIED (BLOCKED)',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.statusAttention,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isAppVerified
                                    ? AppColors.statusNormal.withValues(alpha: 0.15)
                                    : AppColors.statusReview.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: isAppVerified
                                  ? const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'APP LEVEL • ',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.statusNormal,
                                          ),
                                        ),
                                        Text(
                                          'VERIFIED',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.statusNormal,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'DEVICE LEVEL',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.statusReview,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        if (isAppVerified && event.packageName != null && event.packageName!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          if (isBlocked)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.statusAttention.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.statusAttention.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${event.sensorType.label.toUpperCase()} = DENIED',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.statusAttention,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _handleRestoreSensor(
                                      context,
                                      sensorService,
                                      event.packageName!,
                                      event.sensorType,
                                      title,
                                    ),
                                    child: const Text(
                                      'ALLOW AGAIN',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.block, size: 13, color: AppColors.statusAttention),
                                  label: Text(
                                    'BLOCK ${event.sensorType.label.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.statusAttention,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.statusAttention),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _handleBlockSensor(
                                    context,
                                    sensorService,
                                    event,
                                    title,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            )
          else
            const Row(
              children: [
                Icon(Icons.access_time, color: AppColors.textMuted, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No recent sensor activity recorded',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _handleBlockSensor(
    BuildContext context,
    SensorAccessService sensorService,
    SensorAccessEvent event,
    String appDisplay,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final targetPerm = event.sensorType == SensorType.microphone
        ? 'android.permission.RECORD_AUDIO'
        : event.sensorType == SensorType.location
            ? 'android.permission.ACCESS_FINE_LOCATION'
            : 'android.permission.CAMERA';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block ${event.sensorType.label.toLowerCase()} access for $appDisplay?'),
        content: Text(
          'Block ${event.sensorType.label.toLowerCase()} access for $appDisplay?\n\n'
          'Target: ${event.packageName}\n'
          'Permission: $targetPerm\n\n'
          'This will revoke system sensor permission via Shizuku. When you open $appDisplay again, ${event.sensorType.label.toLowerCase()} access will be disabled and $appDisplay will ask for permission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusAttention),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('BLOCK ${event.sensorType.label.toUpperCase()}'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await sensorService.blockSensorAccess(
      packageName: event.packageName!,
      sensor: event.sensorType,
      appName: appDisplay,
    );

    final verified = result['verified'] == true;
    if (verified) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${event.sensorType.label} access blocked for $appDisplay (verified). When opened, $appDisplay will ask for permission.'),
          backgroundColor: AppColors.statusNormal,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not verify ${event.sensorType.label.toLowerCase()} access was blocked: ${result['error'] ?? 'Permission remains granted'}'),
          backgroundColor: AppColors.statusAttention,
          action: SnackBarAction(
            label: 'SETTINGS',
            textColor: Colors.white,
            onPressed: () => AndroidCollector().openAppSettings(event.packageName!),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _handleRestoreSensor(
    BuildContext context,
    SensorAccessService sensorService,
    String packageName,
    SensorType sensor,
    String appDisplay,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final targetPerm = sensor == SensorType.microphone
        ? 'android.permission.RECORD_AUDIO'
        : sensor == SensorType.location
            ? 'android.permission.ACCESS_FINE_LOCATION'
            : 'android.permission.CAMERA';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Allow ${sensor.label.toLowerCase()} access for $appDisplay again?'),
        content: Text(
          'Allow ${sensor.label.toLowerCase()} access for $appDisplay again?\n\n'
          'Target: $packageName\n'
          'Permission: $targetPerm\n\n'
          'This will attempt to restore system sensor permission via Shizuku UserService.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ALLOW'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await sensorService.restoreSensorAccess(
      packageName: packageName,
      sensor: sensor,
      appName: appDisplay,
    );

    final verified = result['verified'] == true;
    if (verified) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${sensor.label} access restored for $appDisplay (verified).'),
          backgroundColor: AppColors.statusNormal,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Direct restore unavailable. You can allow access in Android Settings.'),
          backgroundColor: AppColors.statusAttention,
          action: SnackBarAction(
            label: 'SETTINGS',
            textColor: Colors.white,
            onPressed: () => AndroidCollector().openAppSettings(packageName),
          ),
        ),
      );
    }
  }
}