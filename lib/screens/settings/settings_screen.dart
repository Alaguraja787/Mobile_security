import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../telemetry/collectors/android_collector.dart';

/// Screen providing user-facing settings, Shizuku Precise App Attribution controls,
/// and Android privacy monitoring configuration.
class SettingsScreen extends StatefulWidget {
  final AndroidCollector? collector;

  const SettingsScreen({
    super.key,
    this.collector,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late final AndroidCollector _collector;

  bool _isLoading = true;
  bool _isNotificationsEnabled = true;
  bool _isVoiceAlertsEnabled = true;
  bool _isPreciseModeEnabled = false;
  bool _isShizukuInstalled = false;
  bool _isShizukuAvailable = false;
  bool _hasPermission = false;
  bool _isServiceBound = false;
  String _state = 'OFF';
  String _lifecycleState = 'SHIZUKU_UNAVAILABLE';
  String _status = 'Standard Monitoring';
  String _summary = 'Uses standard Android privacy monitoring.';

  // Standard monitoring permissions
  bool _usageAccessGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _overlayPermissionGranted = false;
  String _notificationPermission = 'UNAVAILABLE';

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _collector = widget.collector ?? AndroidCollector();
    _loadStatus();

    // Periodic status refresh while on settings screen
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _loadStatus(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadStatus(silent: true);
    }
  }

  Future<void> _loadStatus({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final shizukuStatus = await _collector.getShizukuStatus();
      final usageGranted = await _collector.isUsageAccessGranted();
      final batteryIgnored = await _collector.isBatteryOptimizationIgnored();
      final overlayGranted = await _collector.isOverlayPermissionGranted();
      final notifPerm = await _collector.checkNotificationPermission();
      final voiceAlerts = await _collector.isVoiceAlertsEnabled();
      final notifsEnabled = await _collector.isNotificationsEnabled();

      if (!mounted) return;

      setState(() {
        _isNotificationsEnabled = notifsEnabled;
        _isVoiceAlertsEnabled = voiceAlerts;
        _isPreciseModeEnabled = shizukuStatus['isPreciseModeEnabled'] == true;
        _isShizukuInstalled = shizukuStatus['isShizukuInstalled'] == true;
        _isShizukuAvailable = shizukuStatus['isShizukuAvailable'] == true;
        _hasPermission = shizukuStatus['hasPermission'] == true;
        _isServiceBound = shizukuStatus['isServiceBound'] == true;
        _state = shizukuStatus['state']?.toString() ?? 'OFF';
        _lifecycleState = shizukuStatus['lifecycleState']?.toString() ?? 'SHIZUKU_UNAVAILABLE';
        _status = shizukuStatus['status']?.toString() ?? 'Standard Monitoring';
        _summary = shizukuStatus['summary']?.toString() ?? 'Uses standard Android privacy monitoring.';

        _usageAccessGranted = usageGranted;
        _batteryOptimizationIgnored = batteryIgnored;
        _overlayPermissionGranted = overlayGranted;
        _notificationPermission = notifPerm;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _isNotificationsEnabled = value);
    await _collector.setNotificationsEnabled(value);
  }

  Future<void> _toggleVoiceAlerts(bool value) async {
    setState(() => _isVoiceAlertsEnabled = value);
    await _collector.setVoiceAlertsEnabled(value);
  }

  Future<void> _togglePreciseMode(bool value) async {
    setState(() => _isPreciseModeEnabled = value);
    await _collector.setPreciseModeEnabled(value);
    await _loadStatus();
  }

  Future<void> _requestPermission() async {
    await _collector.requestShizukuPermission();
    await _loadStatus();
  }

  Future<void> _openShizukuApp() async {
    await _collector.openShizukuApp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Privacy Controls'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: () => _loadStatus(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildAlertPreferencesCard(),
                const SizedBox(height: 16),
                _buildPreciseAttributionCard(),
                const SizedBox(height: 16),
                _buildDiagnosticsCard(),
                const SizedBox(height: 16),
                _buildStandardMonitoringPermissionsCard(),
                const SizedBox(height: 16),
                _buildArchitectureNoticeCard(),
              ],
            ),
    );
  }

  Widget _buildAlertPreferencesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (_isNotificationsEnabled || _isVoiceAlertsEnabled)
              ? AppColors.statusNormal
              : AppColors.surfaceBorder,
          width: (_isNotificationsEnabled || _isVoiceAlertsEnabled) ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alert & Privacy Notification Controls',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Configure visual notifications and spoken voice alerts',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Option 1: Heads-Up Notifications
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isNotificationsEnabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    color: _isNotificationsEnabled ? AppColors.statusNormal : AppColors.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Alert Notifications',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _isNotificationsEnabled,
                onChanged: _toggleNotifications,
                activeThumbColor: AppColors.statusNormal,
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (_isNotificationsEnabled ? AppColors.statusNormal : AppColors.statusReview)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _isNotificationsEnabled ? 'NOTIFICATIONS ACTIVE' : 'NOTIFICATIONS OFF (MUTED)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isNotificationsEnabled ? AppColors.statusNormal : AppColors.statusReview,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isNotificationsEnabled
                ? 'Posts high-priority alert banners on your screen whenever another app accesses camera, mic, photos, or location.'
                : 'Alert notifications are turned OFF. No banners will pop up on your screen.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(height: 1, color: AppColors.surfaceBorder),
          ),

          // Option 2: Spoken Voice Alerts
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isVoiceAlertsEnabled
                        ? Icons.record_voice_over
                        : Icons.voice_over_off,
                    color: _isVoiceAlertsEnabled ? AppColors.statusNormal : AppColors.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Spoken Voice Alerts',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _isVoiceAlertsEnabled,
                onChanged: _toggleVoiceAlerts,
                activeThumbColor: AppColors.statusNormal,
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (_isVoiceAlertsEnabled ? AppColors.statusNormal : AppColors.statusReview)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _isVoiceAlertsEnabled ? 'VOICE ANNOUNCEMENTS ON' : 'VOICE MUTED (OFF)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isVoiceAlertsEnabled ? AppColors.statusNormal : AppColors.statusReview,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isVoiceAlertsEnabled
                ? 'Speaks alerts aloud via Text-to-Speech whenever sensor access is detected.'
                : 'Spoken voice announcements are turned OFF.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(
                  (_isNotificationsEnabled && _isVoiceAlertsEnabled)
                      ? Icons.check_circle_outline
                      : (!_isNotificationsEnabled && !_isVoiceAlertsEnabled)
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                  size: 16,
                  color: (_isNotificationsEnabled && _isVoiceAlertsEnabled)
                      ? AppColors.statusNormal
                      : (!_isNotificationsEnabled && !_isVoiceAlertsEnabled)
                          ? AppColors.statusReview
                          : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (_isNotificationsEnabled && _isVoiceAlertsEnabled)
                        ? 'Active Mode: Both visual notifications and spoken voice alerts are enabled.'
                        : (_isNotificationsEnabled && !_isVoiceAlertsEnabled)
                            ? 'Silent Notification Mode: Notifications will pop up silently without voice speech.'
                            : (!_isNotificationsEnabled && _isVoiceAlertsEnabled)
                                ? 'Voice Only Mode: Alerts will speak aloud without visual notification banners.'
                                : 'Completely Silent: All alerts are silenced. Events will still be recorded live in your Dashboard.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: (_isNotificationsEnabled && _isVoiceAlertsEnabled)
                          ? AppColors.statusNormal
                          : (!_isNotificationsEnabled && !_isVoiceAlertsEnabled)
                              ? AppColors.statusReview
                              : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreciseAttributionCard() {
    final bool isActive = _state == 'ACTIVE';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppColors.statusNormal : AppColors.surfaceBorder,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isActive ? AppColors.statusNormal : AppColors.primary)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isActive ? Icons.verified_user : Icons.privacy_tip_outlined,
                      color: isActive ? AppColors.statusNormal : AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Precise App Attribution',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _isPreciseModeEnabled,
                onChanged: _togglePreciseMode,
                activeThumbColor: AppColors.statusNormal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isActive ? AppColors.statusNormal : AppColors.primary)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _status.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isActive ? AppColors.statusNormal : AppColors.primary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Enable this mode to identify which app is using the camera or microphone when Android exposes the information through the elevated monitoring service. Requires the Shizuku app and user authorization.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _buildStateActionWidget(),
        ],
      ),
    );
  }

  Widget _buildStateActionWidget() {
    switch (_state) {
      case 'OFF':
        return _buildStatusBanner(
          icon: Icons.shield_outlined,
          color: AppColors.textSecondary,
          title: 'Uses standard Android privacy monitoring.',
          description:
              'Standard monitoring detects camera and microphone activity at device level. Turn switch on to configure precise attribution.',
        );

      case 'NEEDS_SHIZUKU':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(
              icon: Icons.warning_amber_rounded,
              color: AppColors.statusAttention,
              title: 'Install and start Shizuku to enable precise app attribution.',
              description:
                  'Shizuku is required to host the isolated elevated attribution service via wireless debugging or ADB.',
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _openShizukuApp,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open or Install Shizuku'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );

      case 'NEEDS_PERMISSION':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(
              icon: Icons.lock_person_outlined,
              color: AppColors.statusReview,
              title: 'Grant Privacy Sentinel access in Shizuku.',
              description:
                  'Shizuku is running, but user permission has not been granted to Privacy Sentinel yet.',
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Grant Shizuku Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.statusReview,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );

      case 'ACTIVE':
        return _buildStatusBanner(
          icon: Icons.check_circle,
          color: AppColors.statusNormal,
          title: 'Precise app attribution is active.',
          description:
              'Real cross-app camera and microphone usage is identified using elevated system AppOps callbacks and genuine package identity.',
        );

      case 'AVAILABLE':
        return _buildStatusBanner(
          icon: _isServiceBound ? Icons.cloud_done_outlined : Icons.check_circle_outline,
          color: AppColors.statusNormal,
          title: _isServiceBound ? 'UserService connected.' : 'Shizuku permission granted.',
          description: _isServiceBound
              ? 'Elevated background UserService is connected and verified. Ready for AppOps sensor monitoring.'
              : 'Shizuku integration is authorized and connected. Ready for elevated sensor monitoring.',
        );

      case 'TEMPORARILY_UNAVAILABLE':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(
              icon: Icons.sync_problem,
              color: AppColors.statusAttention,
              title: 'Elevated service temporarily unavailable. Falling back to device monitoring.',
              description:
                  'The Shizuku binder connection was lost. Privacy Sentinel will automatically rebind once Shizuku is resumed.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _loadStatus(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Check Connection'),
            ),
          ],
        );

      case 'ERROR':
      default:
        return _buildStatusBanner(
          icon: Icons.error_outline,
          color: AppColors.statusAttention,
          title: 'Elevated service error. Falling back to standard monitoring.',
          description: _summary,
        );
    }
  }

  Widget _buildStatusBanner({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard() {
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
          const Row(
            children: [
              Icon(Icons.tune, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Attribution Diagnostics',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDiagRow('Shizuku Installed?', _isShizukuInstalled ? 'YES' : 'NO', _isShizukuInstalled),
          _buildDiagRow('Shizuku Running?', _isShizukuAvailable ? 'YES' : 'NO', _isShizukuAvailable),
          _buildDiagRow('Permission Granted?', _hasPermission ? 'GRANTED' : 'DENIED / MISSING', _hasPermission),
          _buildDiagRow('UserService Connected?', _isServiceBound ? 'CONNECTED' : 'DISCONNECTED', _isServiceBound),
          _buildDiagRow('Precise Attribution Active?', _state == 'ACTIVE' ? 'ACTIVE' : 'INACTIVE', _state == 'ACTIVE'),
          _buildDiagRow('Internal Lifecycle', _lifecycleState, _lifecycleState == 'SHIZUKU_PERMISSION_GRANTED'),
        ],
      ),
    );
  }

  Widget _buildDiagRow(String label, String value, bool isOk) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (isOk ? AppColors.statusNormal : AppColors.statusReview).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isOk ? AppColors.statusNormal : AppColors.statusReview,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardMonitoringPermissionsCard() {
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
          const Row(
            children: [
              Icon(Icons.security, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Standard Privacy Permissions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPermissionTile(
            title: 'Usage Access (PACKAGE_USAGE_STATS)',
            subtitle: 'Detects background app foregrounding and screen time.',
            isGranted: _usageAccessGranted,
            onTap: () async {
              await _collector.openUsageAccessSettings();
              await _loadStatus();
            },
          ),
          const Divider(height: 16),
          _buildPermissionTile(
            title: 'Notifications (POST_NOTIFICATIONS)',
            subtitle: 'Delivers real-time camera and microphone alerts.',
            isGranted: _notificationPermission == 'GRANTED',
            onTap: () async {
              await _collector.requestNotificationPermission();
              await _loadStatus();
            },
          ),
          const Divider(height: 16),
          _buildPermissionTile(
            title: 'Ignore Battery Optimizations',
            subtitle: 'Allows background sensor monitoring service continuity.',
            isGranted: _batteryOptimizationIgnored,
            onTap: () async {
              await _collector.openBatteryOptimizationSettings();
              await _loadStatus();
            },
          ),
          const Divider(height: 16),
          _buildPermissionTile(
            title: 'Display Over Other Apps (Overlay)',
            subtitle: 'Enables foreground privacy alert indicators.',
            isGranted: _overlayPermissionGranted,
            onTap: () async {
              await _collector.openOverlaySettings();
              await _loadStatus();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isGranted ? AppColors.statusNormal : AppColors.statusReview).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isGranted ? 'GRANTED' : 'CONFIGURE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isGranted ? AppColors.statusNormal : AppColors.statusReview,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchitectureNoticeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Architecture & Security Guarantees',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            'Privacy Sentinel does not use root, OEM dependencies, or system log scraping. The normal app process remains completely unprivileged. When Precise Mode is active, an isolated Shizuku UserService observes system AppOps active state callbacks and returns verified client package identities.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
