import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/app_telemetry.dart';
import '../../services/permission_intelligence_analyzer.dart';
import '../../widgets/app_icon_widget.dart';

class AppDetailsScreen extends StatelessWidget {
  final AppTelemetry app;
  final PermissionRiskResult evaluation;

  const AppDetailsScreen({
    super.key,
    required this.app,
    required this.evaluation,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor = AppColors.statusNormal;
    if (evaluation.level == PermissionRiskLevel.critical) {
      statusColor = AppColors.statusAttention;
    } else if (evaluation.level == PermissionRiskLevel.high ||
        evaluation.level == PermissionRiskLevel.attention) {
      statusColor = Colors.orangeAccent;
    } else if (evaluation.level == PermissionRiskLevel.review) {
      statusColor = AppColors.statusReview;
    }

    final Map<String, List<PermissionStateDetail>> groupedPermissions = _groupPermissions(app);

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Permission Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Metadata Card with Real Native App Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                AppIconWidget(
                  packageName: app.packageName,
                  appName: app.appName,
                  size: 56,
                  borderRadius: 12,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.appName.isNotEmpty ? app.appName : app.packageName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Text(
                        app.packageName,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Category: ${app.category.name.toUpperCase()} • ${app.isSystemApp ? "System App" : "User App"}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    '${evaluation.levelEmoji} ${evaluation.levelLabel}',
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Metadata Chips Grid
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMetaChip('Version', app.versionName.isNotEmpty ? app.versionName : 'N/A'),
                _buildMetaChip('Target SDK', '${app.targetSdkVersion}'),
                _buildMetaChip('Min SDK', '${app.minSdkVersion}'),
                _buildMetaChip('UID', '${app.uid}'),
                if (app.installerPackage.isNotEmpty)
                  _buildMetaChip('Installer', app.installerPackage.split('.').last),
                _buildMetaChip('Status', app.isEnabled ? 'Enabled' : 'Disabled'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Today's Usage & Activity Card (Requirement 13)
          Container(
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
                        Icon(Icons.hourglass_top, color: AppColors.primary, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Today's App Activity",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: app.isUsageStatsAvailable
                            ? AppColors.statusNormal.withValues(alpha: 0.15)
                            : AppColors.statusAttention.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        app.usageDataState != 'UNKNOWN' ? app.usageDataState : app.usageAvailability,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: app.isUsageStatsAvailable ? AppColors.statusNormal : AppColors.statusAttention,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildUsageMetricTile('Today\'s Usage', app.usageTodayFormatted, Icons.timer_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildUsageMetricTile('Last Used', app.lastUsedFormatted, Icons.history),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildUsageMetricTile(
                        'Foreground Time',
                        app.foregroundDurationMs != null
                            ? '${(app.foregroundDurationMs! / 1000).round()}s (${app.foregroundMinutes?.toStringAsFixed(1) ?? "0"}m)'
                            : 'Unavailable',
                        Icons.visibility_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildUsageMetricTile(
                        'Usage Data Status',
                        app.usageDataState != 'UNKNOWN' ? app.usageDataState : app.usageAvailability,
                        Icons.check_circle_outline,
                      ),
                    ),
                  ],
                ),
                if (app.visibleTimeMs != null || app.foregroundServiceTimeMs != null) ...[
                  const SizedBox(height: 8),
                  if (app.visibleTimeMs != null)
                    Text('Visible Time: ${AppTelemetry.formatDuration(app.visibleTimeMs!)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  if (app.foregroundServiceTimeMs != null)
                    Text('Foreground Service: ${AppTelemetry.formatDuration(app.foregroundServiceTimeMs!)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Guardian Reasoning Explanation Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield, color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Guardian Privacy Assessment',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  evaluation.summaryReason,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
                if (evaluation.contextualInferences.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Observed Context Signals:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  ...evaluation.contextualInferences.map((inf) => Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: AppColors.primary)),
                            Expanded(
                              child: Text(inf, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick Stat Counter
          Row(
            children: [
              _buildStatCounter(
                'Total Requested',
                '${app.requestedPermissions.length}',
                AppColors.textPrimary,
              ),
              const SizedBox(width: 12),
              _buildStatCounter(
                'Granted',
                '${app.grantedPermissions.length}',
                AppColors.statusNormal,
              ),
              const SizedBox(width: 12),
              _buildStatCounter(
                'Denied',
                '${app.deniedPermissions.length}',
                AppColors.statusAttention,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Grouped Permissions Section
          const Text(
            'Declared & Requested Permissions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),

          if (groupedPermissions.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No declared permissions detected for this package.',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            ),

          ...groupedPermissions.entries.map((entry) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.surfaceBorder),
              ),
              child: ExpansionTile(
                initiallyExpanded: true,
                title: Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                ),
                subtitle: Text(
                  '${entry.value.length} permission(s)',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                children: entry.value.map((detail) {
                  return ListTile(
                    dense: true,
                    title: Text(
                      detail.permissionName,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      detail.protectionLevel,
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                    trailing: _buildStateTag(detail.state),
                  );
                }).toList(),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMetaChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.textMuted)),
            TextSpan(text: value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCounter(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildStateTag(String state) {
    Color tagColor;
    switch (state) {
      case 'Granted':
        tagColor = AppColors.statusNormal;
        break;
      case 'Denied':
        tagColor = AppColors.statusAttention;
        break;
      case 'Restricted':
        tagColor = AppColors.statusReview;
        break;
      case 'Unavailable':
      case 'Unknown':
      default:
        tagColor = AppColors.textMuted;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tagColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tagColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(state, style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Map<String, List<PermissionStateDetail>> _groupPermissions(AppTelemetry app) {
    final Map<String, List<PermissionStateDetail>> groups = {};

    for (final raw in app.requestedPermissions) {
      final String simple = raw.contains('.') ? raw.split('.').last : raw;
      final bool isGranted = app.grantedPermissions.contains(raw);
      final bool isDangerous = app.dangerousGrantedPermissions.contains(raw) ||
          app.dangerousRequestedPermissions.contains(raw);
      final String state = isGranted ? 'Granted' : 'Denied';

      String category = 'OTHER PERMISSIONS';
      if (simple.contains('CAMERA')) {
        category = 'CAMERA ACCESS';
      } else if (simple.contains('AUDIO') || simple.contains('MICROPHONE')) {
        category = 'MICROPHONE ACCESS';
      } else if (simple.contains('LOCATION')) {
        category = 'LOCATION ACCESS';
      } else if (simple.contains('CONTACTS')) {
        category = 'CONTACTS & ACCOUNTS';
      } else if (simple.contains('STORAGE') || simple.contains('MEDIA')) {
        category = 'PHOTOS & STORAGE';
      } else if (simple.contains('PHONE') || simple.contains('CALL') || simple.contains('SMS')) {
        category = 'PHONE & SMS';
      } else if (simple.contains('OVERLAY') || simple.contains('ALERT')) {
        category = 'SYSTEM OVERLAY';
      }

      groups.putIfAbsent(category, () => []);
      groups[category]!.add(PermissionStateDetail(
        permissionName: simple,
        state: state,
        protectionLevel: isDangerous ? 'PROTECTION_DANGEROUS' : 'PROTECTION_NORMAL',
      ));
    }

    if (app.hasOverlayOp) {
      groups.putIfAbsent('SPECIAL ACCESS', () => []);
      groups['SPECIAL ACCESS']!.add(PermissionStateDetail(
        permissionName: 'SYSTEM_ALERT_WINDOW (AppOp)',
        state: 'Granted',
        protectionLevel: 'SPECIAL_APPOP',
      ));
    }

    if (app.hasUsageAccessOp) {
      groups.putIfAbsent('SPECIAL ACCESS', () => []);
      groups['SPECIAL ACCESS']!.add(PermissionStateDetail(
        permissionName: 'PACKAGE_USAGE_STATS (AppOp)',
        state: 'Granted',
        protectionLevel: 'SPECIAL_APPOP',
      ));
    }

    return groups;
  }

  Widget _buildUsageMetricTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class PermissionStateDetail {
  final String permissionName;
  final String state;
  final String protectionLevel;

  PermissionStateDetail({
    required this.permissionName,
    required this.state,
    this.protectionLevel = 'PROTECTION_NORMAL',
  });
}
