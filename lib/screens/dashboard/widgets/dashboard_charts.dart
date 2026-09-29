import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/app_telemetry.dart';
import '../../../models/sensor_access_event.dart';
import '../../../services/permission_intelligence_analyzer.dart';
import '../../../services/sensor_access_service.dart';
import '../sensor_session_screen.dart';

// ---------------------------------------------------------------------------
// 1. RISK DISTRIBUTION DONUT CHART
// ---------------------------------------------------------------------------

class RiskDistributionDonutChart extends StatelessWidget {
  final DevicePrivacyScoreBreakdown? breakdown;
  final VoidCallback? onAskGuardian;

  const RiskDistributionDonutChart({
    super.key,
    required this.breakdown,
    this.onAskGuardian,
  });

  @override
  Widget build(BuildContext context) {
    final total = breakdown?.totalApps ?? 0;
    final slices = total > 0
        ? [
            _RiskSlice(
              label: 'Expected',
              count: breakdown!.expectedCount,
              color: AppColors.statusNormal,
            ),
            _RiskSlice(
              label: 'Low',
              count: breakdown!.lowCount,
              color: AppColors.accentCyan,
            ),
            _RiskSlice(
              label: 'Review',
              count: breakdown!.reviewCount,
              color: AppColors.statusReview,
            ),
            _RiskSlice(
              label: 'High',
              count: breakdown!.highCount,
              color: AppColors.statusAttention,
            ),
            _RiskSlice(
              label: 'Critical',
              count: breakdown!.criticalCount,
              color: Colors.redAccent,
            ),
          ]
        : <_RiskSlice>[];

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_outline, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Risk Distribution',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$total Analysed',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (total == 0)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: const Text(
                'No risk analysis data available',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 450;
              final donutSize = isWide ? 130.0 : 110.0;

              final donutWidget = SizedBox(
                width: donutSize,
                height: donutSize,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    slices: slices,
                    total: total,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Text(
                          'Total Apps',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );

              final legendWidget = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: slices.map((s) {
                  final pct = total > 0 ? (s.count / total * 100).toStringAsFixed(1) : '0';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: s.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.label,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${s.count}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '($pct%)',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );

              if (isWide) {
                return Row(
                  children: [
                    donutWidget,
                    const SizedBox(width: 28),
                    Expanded(child: legendWidget),
                  ],
                );
              } else {
                return Column(
                  children: [
                    donutWidget,
                    const SizedBox(height: 16),
                    legendWidget,
                  ],
                );
              }
            },
          ),
          ],
        ],
      ),
    );
  }
}

class _RiskSlice {
  final String label;
  final int count;
  final Color color;

  _RiskSlice({
    required this.label,
    required this.count,
    required this.color,
  });
}

class _DonutChartPainter extends CustomPainter {
  final List<_RiskSlice> slices;
  final int total;

  _DonutChartPainter({
    required this.slices,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 14.0;

    // Draw background track ring
    final bgPaint = Paint()
      ..color = AppColors.surfaceElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);

    if (total == 0) return;

    double startAngle = -math.pi / 2;
    const gapAngle = 0.03; // Small visual gap between slices

    for (final slice in slices) {
      if (slice.count <= 0) continue;
      final sweepAngle = (slice.count / total) * 2 * math.pi;

      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // Adjust for gap if more than one slice
      final effectiveSweep = sweepAngle > gapAngle ? sweepAngle - gapAngle : sweepAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle + gapAngle / 2,
        effectiveSweep,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.total != total || oldDelegate.slices != slices;
  }
}

// ---------------------------------------------------------------------------
// 2. TOP USED APPS TODAY BAR CHART
// ---------------------------------------------------------------------------

class AppUsageBarChart extends StatelessWidget {
  final List<AppTelemetry> apps;
  final bool hasUsageAccess;
  final VoidCallback? onOpenUsageSettings;

  const AppUsageBarChart({
    super.key,
    required this.apps,
    required this.hasUsageAccess,
    this.onOpenUsageSettings,
  });

  @override
  Widget build(BuildContext context) {
    final usedApps = apps
        .where((a) => (a.usageTodayMs ?? a.foregroundDurationMs ?? 0) > 0)
        .toList()
      ..sort((a, b) => (b.usageTodayMs ?? b.foregroundDurationMs ?? 0)
          .compareTo(a.usageTodayMs ?? a.foregroundDurationMs ?? 0));

    final top5 = usedApps.take(5).toList();

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Today's App Usage",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasUsageAccess
                      ? AppColors.statusNormal.withValues(alpha: 0.15)
                      : AppColors.statusAttention.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  hasUsageAccess ? 'Top ${top5.length} Apps' : 'Permission Required',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hasUsageAccess ? AppColors.statusNormal : AppColors.statusAttention,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasUsageAccess)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.statusAttention.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No usage data available: Android Usage Access permission is required to measure foreground screen time.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (onOpenUsageSettings != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: onOpenUsageSettings,
                      icon: const Icon(Icons.settings, size: 14),
                      label: const Text('Open Usage Settings', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (top5.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: const Text(
                'No usage data available for today yet.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else ...[
            Builder(
              builder: (context) {
                final int totalForegroundTimeMs = usedApps.fold(
                    0, (sum, a) => sum + (a.usageTodayMs ?? a.foregroundDurationMs ?? 0));
                final String totalForegroundFormatted =
                    AppTelemetry.formatDuration(totalForegroundTimeMs);

                final maxMs = (top5.first.usageTodayMs ?? top5.first.foregroundDurationMs ?? 1).toDouble();
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Apps Used Today',
                                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                const SizedBox(height: 4),
                                Text(
                                  '${usedApps.length}',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary),
                                ),
                                Text(
                                  '${apps.length - usedApps.length} unused',
                                  style: const TextStyle(
                                      fontSize: 10, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Foreground',
                                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                const SizedBox(height: 4),
                                Text(
                                  totalForegroundFormatted,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary),
                                ),
                                const Text(
                                  'Active foreground time',
                                  style: TextStyle(
                                      fontSize: 10, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...top5.map((app) {
                    final appMs = (app.usageTodayMs ?? app.foregroundDurationMs ?? 0).toDouble();
                    final ratio = maxMs > 0 ? (appMs / maxMs).clamp(0.05, 1.0) : 0.05;
                    final displayName = app.appName.trim().isNotEmpty ? app.appName : app.packageName;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                app.usageTodayFormatted,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accentCyan,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              children: [
                                Container(
                                  height: 8,
                                  width: double.infinity,
                                  color: AppColors.surfaceElevated,
                                ),
                                FractionallySizedBox(
                                  widthFactor: ratio,
                                  child: Container(
                                    height: 8,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [AppColors.primary, AppColors.accentCyan],
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
          ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. PERMISSION DISTRIBUTION CHART
// ---------------------------------------------------------------------------

class PermissionDistributionChart extends StatelessWidget {
  final List<AppTelemetry> apps;

  const PermissionDistributionChart({
    super.key,
    required this.apps,
  });

  @override
  Widget build(BuildContext context) {
    int dangerousGranted = 0;
    int standardGranted = 0;
    int denied = 0;

    for (final app in apps) {
      final totalGranted = app.grantedPermissions.length;
      final dangGranted = app.dangerousGrantedPermissions.length;
      dangerousGranted += dangGranted;
      standardGranted += (totalGranted >= dangGranted) ? (totalGranted - dangGranted) : 0;
      denied += app.deniedPermissions.length;
    }

    final total = dangerousGranted + standardGranted + denied;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.security, color: AppColors.accentCyan, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Permission Distribution',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$total Total',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accentCyan,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (apps.isEmpty || total == 0)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: const Text(
                'No permission inventory available',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else ...[
            // Horizontal stacked progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    if (dangerousGranted > 0)
                      Expanded(
                        flex: dangerousGranted,
                        child: Container(color: AppColors.statusReview),
                      ),
                    if (standardGranted > 0)
                      Expanded(
                        flex: standardGranted,
                        child: Container(color: AppColors.statusNormal),
                      ),
                    if (denied > 0)
                      Expanded(
                        flex: denied,
                        child: Container(color: AppColors.surfaceBorder),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem(
                  'Sensitive Granted',
                  dangerousGranted,
                  total > 0 ? (dangerousGranted / total * 100).toStringAsFixed(1) : '0',
                  AppColors.statusReview,
                ),
                _buildLegendItem(
                  'Standard Granted',
                  standardGranted,
                  total > 0 ? (standardGranted / total * 100).toStringAsFixed(1) : '0',
                  AppColors.statusNormal,
                ),
                _buildLegendItem(
                  'Denied / Revoked',
                  denied,
                  total > 0 ? (denied / total * 100).toStringAsFixed(1) : '0',
                  AppColors.textMuted,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, int count, String pct, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
        Text(
          '($pct%)',
          style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. LIVE SENSOR MINI VISUALIZER
// ---------------------------------------------------------------------------

class LiveSensorMiniVisualizer extends StatelessWidget {
  final SensorAccessService sensorService;
  final void Function(SensorType type)? onSensorTap;

  const LiveSensorMiniVisualizer({
    super.key,
    required this.sensorService,
    this.onSensorTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeSessions = sensorService.activeSessions;
    final bool isCamLive = activeSessions.any((s) => s.sensorType == SensorType.camera);
    final bool isMicLive = activeSessions.any((s) => s.sensorType == SensorType.microphone);
    final bool isLocLive = activeSessions.any((s) => s.sensorType == SensorType.location);

    final camSession = isCamLive
        ? activeSessions.firstWhere((s) => s.sensorType == SensorType.camera)
        : null;
    final micSession = isMicLive
        ? activeSessions.firstWhere((s) => s.sensorType == SensorType.microphone)
        : null;
    final locSession = isLocLive
        ? activeSessions.firstWhere((s) => s.sensorType == SensorType.location)
        : null;

    return Row(
      children: [
        Expanded(
          child: _buildSensorStatusTile(
            context: context,
            sensorType: SensorType.camera,
            title: 'CAMERA',
            icon: Icons.camera_alt_outlined,
            isLive: isCamLive,
            activeSession: camSession,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSensorStatusTile(
            context: context,
            sensorType: SensorType.microphone,
            title: 'MICROPHONE',
            icon: Icons.mic_none_outlined,
            isLive: isMicLive,
            activeSession: micSession,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSensorStatusTile(
            context: context,
            sensorType: SensorType.location,
            title: 'LOCATION',
            icon: Icons.location_on_outlined,
            isLive: isLocLive,
            activeSession: locSession,
          ),
        ),
      ],
    );
  }

  Widget _buildSensorStatusTile({
    required BuildContext context,
    required SensorType sensorType,
    required String title,
    required IconData icon,
    required bool isLive,
    required SensorAccessEvent? activeSession,
  }) {
    final Color accentColor = isLive ? AppColors.statusAttention : AppColors.textMuted;
    final String statusText = isLive ? 'LIVE' : 'INACTIVE';
    final String detailText = isLive
        ? (activeSession?.isAppAttributed == true && activeSession?.appName != null && activeSession!.appName!.isNotEmpty)
            ? activeSession.appName!
            : (activeSession?.isAppAttributed == true && activeSession?.packageName != null && activeSession!.packageName!.isNotEmpty)
                ? activeSession.packageName!
                : 'App identity unavailable'
        : 'No access';

    void handleTap() {
      if (onSensorTap != null) {
        onSensorTap!(sensorType);
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SensorSessionScreen(
              initialSensorType: sensorType,
              sensorService: sensorService,
            ),
          ),
        );
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: handleTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isLive
                ? AppColors.statusAttention.withValues(alpha: 0.12)
                : AppColors.surfaceElevated.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isLive ? AppColors.statusAttention : AppColors.surfaceBorder,
              width: isLive ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 16, color: accentColor),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isLive
                              ? AppColors.statusAttention.withValues(alpha: 0.2)
                              : AppColors.surfaceBorder.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 12,
                        color: isLive ? AppColors.statusAttention : AppColors.textMuted,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  color: isLive ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detailText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isLive ? FontWeight.w600 : FontWeight.normal,
                  color: isLive ? AppColors.statusAttention : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
