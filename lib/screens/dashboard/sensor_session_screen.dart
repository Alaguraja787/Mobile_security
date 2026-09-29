import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/sensor_access_event.dart';
import '../../services/sensor_access_service.dart';
import '../../telemetry/collectors/android_collector.dart';
import '../../telemetry/telemetry_service.dart';
import '../../widgets/app_icon_widget.dart';

/// Dedicated full-screen session view for a specific hardware sensor (Camera, Microphone, Location, etc.).
///
/// Provides live session streaming details, active applications, real-time duration counters,
/// granular permission controls (Block/Restore via Shizuku), and isolated event history.
class SensorSessionScreen extends StatefulWidget {
  final SensorType initialSensorType;
  final SensorAccessService? sensorService;
  final TelemetryService? telemetryService;

  const SensorSessionScreen({
    super.key,
    this.initialSensorType = SensorType.camera,
    this.sensorService,
    this.telemetryService,
  });

  @override
  State<SensorSessionScreen> createState() => _SensorSessionScreenState();
}

class _SensorSessionScreenState extends State<SensorSessionScreen> {
  late SensorType _selectedSensor;
  Timer? _ticker;

  final List<SensorType> _availableSensors = [
    SensorType.camera,
    SensorType.microphone,
    SensorType.location,
    SensorType.photos,
  ];

  @override
  void initState() {
    super.initState();
    _selectedSensor = widget.initialSensorType;
    // Periodic ticker to ensure live elapsed duration counters increment smoothly every second
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  SensorAccessService _resolveService(BuildContext context) {
    if (widget.sensorService != null) return widget.sensorService!;
    try {
      return Provider.of<SensorAccessService>(context, listen: false);
    } catch (_) {
      return SensorAccessService.shared;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sensorService = _resolveService(context);

    return ListenableBuilder(
      listenable: sensorService,
      builder: (context, _) {
        final activeSessions = sensorService.activeSessions
            .where((s) => s.sensorType == _selectedSensor)
            .toList();
        final bool isLive = activeSessions.isNotEmpty;

        final recentEvents = sensorService.recentEvents
            .where((e) => e.sensorType == _selectedSensor)
            .toList();

        final blockedForSensor = sensorService.blockedApps.entries
            .where((entry) => entry.value.contains(_selectedSensor))
            .map((entry) => entry.key)
            .toList();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(context, isLive),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            children: [
              // 1. Segmented Sensor Selector Tabs
              _buildSensorSelectorBar(sensorService),
              const SizedBox(height: 16),

              // 2. Hero Session Status Card
              _buildHeroSessionCard(isLive, activeSessions.length),
              const SizedBox(height: 20),

              // 3. Active App Sessions (Live Now)
              _buildActiveSessionsSection(context, sensorService, activeSessions),
              const SizedBox(height: 20),

              // 4. Blocked Applications for this Sensor
              if (blockedForSensor.isNotEmpty) ...[
                _buildBlockedAppsSection(context, sensorService, blockedForSensor),
                const SizedBox(height: 20),
              ],

              // 5. Sensor Timeline & History
              _buildHistorySection(context, sensorService, recentEvents),
              const SizedBox(height: 20),

              // 6. Native Hardware & System Security Info
              _buildSystemControlsCard(context),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isLive) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Text(
            _selectedSensor.iconEmoji,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_selectedSensor.label} Session',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isLive
                ? AppColors.statusAttention.withValues(alpha: 0.2)
                : AppColors.statusNormal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLive ? AppColors.statusAttention : AppColors.statusNormal,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLive ? AppColors.statusAttention : AppColors.statusNormal,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isLive ? 'LIVE' : 'IDLE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isLive ? AppColors.statusAttention : AppColors.statusNormal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSensorSelectorBar(SensorAccessService sensorService) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _availableSensors.map((type) {
          final isSelected = type == _selectedSensor;
          final isSensorLive = sensorService.isSensorActive(type);

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _selectedSensor = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isSensorLive
                          ? AppColors.statusAttention.withValues(alpha: 0.2)
                          : AppColors.primary.withValues(alpha: 0.25))
                      : AppColors.surfaceElevated.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? (isSensorLive ? AppColors.statusAttention : AppColors.primary)
                        : AppColors.surfaceBorder,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(type.iconEmoji, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 6),
                    Text(
                      type.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (isSensorLive) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.statusAttention,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeroSessionCard(bool isLive, int activeCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLive
              ? [
                  AppColors.statusAttention.withValues(alpha: 0.22),
                  AppColors.surface,
                ]
              : [
                  AppColors.surface,
                  AppColors.primary.withValues(alpha: 0.12),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive
              ? AppColors.statusAttention.withValues(alpha: 0.7)
              : AppColors.cardGlassBorder,
          width: isLive ? 1.8 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLive
                      ? AppColors.statusAttention.withValues(alpha: 0.25)
                      : AppColors.statusNormal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLive
                        ? AppColors.statusAttention.withValues(alpha: 0.5)
                        : AppColors.statusNormal.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  _selectedSensor.iconEmoji,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLive
                          ? 'HARDWARE SENSOR STREAMING'
                          : 'HARDWARE SENSOR SECURE & IDLE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: isLive ? AppColors.statusAttention : AppColors.statusNormal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLive
                          ? '$activeCount ${activeCount == 1 ? 'application is' : 'applications are'} actively accessing your ${_selectedSensor.label.toLowerCase()} right now.'
                          : 'No background or foreground applications have an active ${_selectedSensor.label.toLowerCase()} stream.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.surfaceBorder),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricChip(
                label: 'MONITORING CHANNEL',
                value: 'Native Binder IPC',
                icon: Icons.hub_outlined,
              ),
              _buildMetricChip(
                label: 'PRIVACY ENGINE',
                value: isLive ? 'Real-Time Intercept' : 'Protected',
                icon: Icons.shield_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.accentCyan),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: AppColors.textMuted,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveSessionsSection(
    BuildContext context,
    SensorAccessService sensorService,
    List<SensorAccessEvent> activeSessions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors, size: 18, color: AppColors.statusAttention),
                const SizedBox(width: 8),
                Text(
                  'ACTIVE ${_selectedSensor.label.toUpperCase()} SESSIONS',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: activeSessions.isNotEmpty
                    ? AppColors.statusAttention.withValues(alpha: 0.2)
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${activeSessions.length} LIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: activeSessions.isNotEmpty
                      ? AppColors.statusAttention
                      : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (activeSessions.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.statusNormal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.statusNormal,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No Active ${_selectedSensor.label} Access',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your device hardware is protected. No applications are currently using the ${_selectedSensor.label.toLowerCase()}.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: activeSessions.map((event) {
              return _buildActiveAppCard(context, sensorService, event);
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildActiveAppCard(
    BuildContext context,
    SensorAccessService sensorService,
    SensorAccessEvent event,
  ) {
    final bool isAppVerified = event.isAppAttributed &&
        event.appName != null &&
        event.appName!.trim().isNotEmpty;

    final String appDisplay = isAppVerified
        ? event.appName!
        : (event.isAppAttributed &&
                event.packageName != null &&
                event.packageName!.trim().isNotEmpty)
            ? event.packageName!
            : 'App identity unavailable';

    final String activeDuration =
        SensorAccessService.formatActiveDuration(event.timestamp);
    final bool isBlocked = sensorService.isAppBlocked(
        event.packageName ?? '', event.sensorType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.statusAttention.withValues(alpha: 0.6),
          width: 1.5,
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
                  appName: appDisplay,
                  size: 48,
                  borderRadius: 12,
                )
              else
                Container(
                  width: 48,
                  height: 48,
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
                              color: isAppVerified
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAppVerified
                                ? AppColors.statusNormal.withValues(alpha: 0.15)
                                : AppColors.statusReview.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isAppVerified ? 'VERIFIED APP' : 'DEVICE LEVEL',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isAppVerified
                                  ? AppColors.statusNormal
                                  : AppColors.statusReview,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (event.packageName != null &&
                        event.packageName!.isNotEmpty)
                      Text(
                        event.packageName!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Text(
                          '● LIVE',
                          style: TextStyle(
                            color: AppColors.statusAttention,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          activeDuration,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (event.isScreenLocked) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.redAccent),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'LOCKED SCREEN ACCESS: Accessed sensor while phone was locked!',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isAppVerified &&
              event.packageName != null &&
              event.packageName!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isBlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.statusAttention.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.statusAttention.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${event.sensorType.label.toUpperCase()} = DENIED',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.statusAttention,
                          ),
                        ),
                        const SizedBox(width: 10),
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
                              fontSize: 11,
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
                    icon: const Icon(Icons.block,
                        size: 14, color: AppColors.statusAttention),
                    label: Text(
                      'BLOCK ${event.sensorType.label.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.statusAttention,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.statusAttention),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _handleBlockSensor(
                      context,
                      sensorService,
                      event,
                      appDisplay,
                    ),
                  ),
                IconButton(
                  tooltip: 'App Details in Settings',
                  icon: const Icon(Icons.settings_outlined,
                      size: 20, color: AppColors.textSecondary),
                  onPressed: () =>
                      AndroidCollector().openAppSettings(event.packageName!),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBlockedAppsSection(
    BuildContext context,
    SensorAccessService sensorService,
    List<String> blockedPackages,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.statusAttention.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security, size: 16, color: AppColors.statusAttention),
              const SizedBox(width: 8),
              Text(
                'BLOCKED FOR ${_selectedSensor.label.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...blockedPackages.map((pkg) {
            final recentMatch = sensorService.recentEvents
                .where((e) => e.packageName == pkg && e.appName != null)
                .firstOrNull;
            final appName = recentMatch?.appName ?? pkg;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.surfaceBorder),
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
                          size: 38,
                          borderRadius: 8,
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
                                '${_selectedSensor.label.toUpperCase()} = DENIED',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.statusAttention,
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
                    onPressed: () => _handleRestoreSensor(
                      context,
                      sensorService,
                      pkg,
                      _selectedSensor,
                      appName,
                    ),
                    child: const Text('ALLOW AGAIN',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHistorySection(
    BuildContext context,
    SensorAccessService sensorService,
    List<SensorAccessEvent> events,
  ) {
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
              Row(
                children: [
                  const Icon(Icons.history, size: 18, color: AppColors.accentCyan),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedSensor.label.toUpperCase()} ACTIVITY TIMELINE',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                '${events.length} Events',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No recent ${_selectedSensor.label.toLowerCase()} activity recorded',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length > 25 ? 25 : events.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 16, color: AppColors.surfaceBorder),
              itemBuilder: (context, index) {
                final event = events[index];
                final isAppVerified = event.isAppAttributed &&
                    event.appName != null &&
                    event.appName!.trim().isNotEmpty;
                final title = isAppVerified
                    ? event.appName!
                    : (event.isAppAttributed &&
                            event.packageName != null &&
                            event.packageName!.trim().isNotEmpty)
                        ? event.packageName!
                        : 'Hardware ${_selectedSensor.label}';

                final relativeTime =
                    SensorAccessService.formatRelativeTime(event.timestamp);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isAppVerified && event.packageName != null)
                      AppIconWidget(
                        packageName: event.packageName!,
                        appName: title,
                        size: 36,
                        borderRadius: 8,
                      )
                    else
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.surfaceBorder),
                        ),
                        child: Center(
                          child: Text(
                            event.sensorType.iconEmoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                relativeTime,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: event.isStarted
                                      ? AppColors.statusAttention.withValues(alpha: 0.15)
                                      : AppColors.statusNormal.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  event.state.toJson(),
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    color: event.isStarted
                                        ? AppColors.statusAttention
                                        : AppColors.statusNormal,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (event.isScreenLocked) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'SCREEN LOCKED',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  event.packageName ?? '',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSystemControlsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.accentCyan),
              SizedBox(width: 8),
              Text(
                'SYSTEM PRIVACY ARCHITECTURE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'On Android 12+, you can instantly cut hardware access for ${_selectedSensor.label} system-wide using the Quick Settings tile.\n\n'
            'Privacy Sentinel directly hooks into the native Android IPC AppOpsManager and CameraManager to intercept hardware access in real time.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
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
