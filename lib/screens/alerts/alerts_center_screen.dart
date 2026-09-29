import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../guardian/agent/models/agent_necessity_evaluation.dart';
import '../../guardian/agent/privacy_guardian_agent.dart';
import '../../models/app_telemetry.dart';
import '../../models/sensor_access_event.dart';
import '../../services/guardian_service.dart';
import '../../services/permission_intelligence_analyzer.dart';
import '../../services/privacy_alert_manager.dart';
import '../../telemetry/app_telemetry_builder.dart';
import '../../telemetry/telemetry_service.dart';
import '../apps/app_details_screen.dart';

class AlertsCenterScreen extends StatefulWidget {
  final VoidCallback? onNavigateToGuardian;

  const AlertsCenterScreen({
    super.key,
    this.onNavigateToGuardian,
  });

  @override
  State<AlertsCenterScreen> createState() => _AlertsCenterScreenState();
}

class _AlertsCenterScreenState extends State<AlertsCenterScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showPolicyDialog(BuildContext context, PrivacyGuardianAgent agent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final policy = agent.policyConfig;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.smart_toy_outlined, color: AppColors.primary, size: 24),
                          SizedBox(width: 10),
                          Text(
                            'Autonomous Guardian Policies',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.textMuted),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Configure whether the agent asks for your confirmation or automatically enforces blocks.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Divider(height: 24, color: AppColors.surfaceBorder),
                  SwitchListTile(
                    title: const Text('Always Block Background Camera', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Silently blocks camera hardware triggers if app is not actively open in foreground.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: policy.autoBlockBackgroundCamera,
                    activeTrackColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      agent.updatePolicyConfig(policy.copyWith(autoBlockBackgroundCamera: val));
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Always Block Background Microphone', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Prevents background microphone recording outside active calls.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: policy.autoBlockBackgroundMic,
                    activeTrackColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      agent.updatePolicyConfig(policy.copyWith(autoBlockBackgroundMic: val));
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Always Block When Screen Locked', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Automatically revokes camera & microphone triggers when device is locked.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: policy.autoBlockScreenLockedAccess,
                    activeTrackColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      agent.updatePolicyConfig(policy.copyWith(autoBlockScreenLockedAccess: val));
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final alertManager = Provider.of<PrivacyAlertManager>(context);
    final agent = Provider.of<PrivacyGuardianAgent?>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Alert Center'),
        actions: [
          if (agent != null)
            IconButton(
              icon: const Icon(Icons.tune_outlined, color: AppColors.primary),
              tooltip: 'Agent Policies',
              onPressed: () => _showPolicyDialog(context, agent),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: [
            Tab(text: 'All (${alertManager.alerts.length})'),
            Tab(text: '🔴 Critical (${alertManager.criticalAlerts.length})'),
            Tab(text: '🟡 Review (${alertManager.reviewAlerts.length})'),
            Tab(text: 'ℹ Info (${alertManager.infoAlerts.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (agent != null) _buildAgentStatusBar(agent),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAlertList(alertManager.alerts, agent),
                _buildAlertList(alertManager.criticalAlerts, agent),
                _buildAlertList(alertManager.reviewAlerts, agent),
                _buildAlertList(alertManager.infoAlerts, agent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentStatusBar(PrivacyGuardianAgent agent) {
    final policy = agent.policyConfig;
    final bool anyAutoPolicy = policy.autoBlockBackgroundCamera ||
        policy.autoBlockBackgroundMic ||
        policy.autoBlockScreenLockedAccess;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(
          bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_outlined, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Autonomous Privacy Guardian Agent',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  anyAutoPolicy
                      ? 'Policy: Autonomous Enforcing active'
                      : 'Mode: Human-in-the-Loop (Approval Required)',
                  style: TextStyle(
                    fontSize: 11,
                    color: anyAutoPolicy ? AppColors.statusNormal : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _showPolicyDialog(context, agent),
            icon: const Icon(Icons.settings_outlined, size: 14),
            label: const Text('Policies', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertList(List<PrivacyAlert> alerts, PrivacyGuardianAgent? agent) {
    if (alerts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 48, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'No active privacy alerts in this category.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index];

        Color severityColor = AppColors.statusNormal;
        if (alert.severity == AlertSeverity.critical) {
          severityColor = AppColors.statusAttention;
        } else if (alert.severity == AlertSeverity.review) {
          severityColor = AppColors.statusReview;
        }

        final bool hasAgentRec = alert.agentRecommendation != null;
        final AgentRecommendation? rec = alert.agentRecommendation;

        Color recBadgeColor = AppColors.textSecondary;
        String recBadgeText = 'REVIEW';
        IconData recBadgeIcon = Icons.help_outline;

        if (rec == AgentRecommendation.block) {
          recBadgeColor = AppColors.statusAttention;
          recBadgeText = 'AGENT: BLOCK RECOMMENDED';
          recBadgeIcon = Icons.block;
        } else if (rec == AgentRecommendation.allow) {
          recBadgeColor = AppColors.statusNormal;
          recBadgeText = 'AGENT: ALLOW RECOMMENDED';
          recBadgeIcon = Icons.check_circle_outline;
        } else if (rec == AgentRecommendation.askUser) {
          recBadgeColor = AppColors.statusReview;
          recBadgeText = 'AGENT: REVIEW WITH USER';
          recBadgeIcon = Icons.warning_amber_rounded;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasAgentRec
                  ? recBadgeColor.withValues(alpha: 0.5)
                  : severityColor.withValues(alpha: 0.35),
              width: hasAgentRec ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Agent Recommendation or Severity Badge + Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (hasAgentRec)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: recBadgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: recBadgeColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(recBadgeIcon, color: recBadgeColor, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            recBadgeText,
                            style: TextStyle(
                              color: recBadgeColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.4,
                            ),
                          ),
                          if (alert.necessityScore != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: recBadgeColor.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${(alert.necessityScore! * 100).toInt()}% Necessity',
                                style: TextStyle(
                                  color: recBadgeColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: severityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: severityColor),
                      ),
                      child: Text(
                        alert.severityLabel,
                        style: TextStyle(
                          color: severityColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  Text(
                    '${alert.timestamp.hour}:${alert.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // App Name and Context Tags
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      alert.appName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (alert.sensorType != null)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            alert.sensorType == SensorType.camera
                                ? Icons.videocam_outlined
                                : (alert.sensorType == SensorType.microphone
                                    ? Icons.mic_none_outlined
                                    : Icons.location_on_outlined),
                            size: 11,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            alert.sensorType!.label,
                            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  if (alert.isForeground != null)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: alert.isForeground == true
                            ? AppColors.statusNormal.withValues(alpha: 0.1)
                            : AppColors.statusAttention.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        alert.isForeground == true ? '📱 Foreground' : '💤 Background',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: alert.isForeground == true
                              ? AppColors.statusNormal
                              : AppColors.statusAttention,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              // Reason
              Text(
                alert.reason,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),

              // Guardian Agent Analysis Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.surfaceBorder.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.smart_toy_outlined, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Autonomous Agent Analysis:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            alert.guardianExplanation,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Action Buttons & Governance
              _buildActionRow(context, alert, agent),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionRow(BuildContext context, PrivacyAlert alert, PrivacyGuardianAgent? agent) {
    if (alert.actionStatus == 'BLOCKED' || alert.actionStatus == 'BLOCKED_BY_POLICY') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.statusAttention.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.statusAttention.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.shield, color: AppColors.statusAttention, size: 16),
                const SizedBox(width: 8),
                Text(
                  alert.actionStatus == 'BLOCKED_BY_POLICY'
                      ? 'Auto-Blocked by Policy (Shizuku)'
                      : 'Blocked via Shizuku Privileged Control',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.statusAttention,
                  ),
                ),
              ],
            ),
            if (agent != null && alert.sensorType != null)
              TextButton(
                onPressed: () async {
                  final res = await agent.restoreUserDecision(
                    evaluationId: alert.id,
                    packageName: alert.packageName,
                    sensorType: alert.sensorType!,
                    appName: alert.appName,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res['success'] == true
                            ? 'Restored ${alert.sensorType!.label} access for ${alert.appName}'
                            : 'Restore failed: ${res['error']}'),
                      ),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                child: const Text('Undo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      );
    }

    if (alert.actionStatus == 'ALLOWED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.statusNormal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.statusNormal.withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.statusNormal, size: 16),
            SizedBox(width: 8),
            Text(
              'Allowed by User Governance',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.statusNormal,
              ),
            ),
          ],
        ),
      );
    }

    // Default: PENDING - Render Action Buttons
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        // App Details / Review button
        OutlinedButton.icon(
          onPressed: () {
            final telemetry = Provider.of<TelemetryService>(context, listen: false);
            final apps = telemetry.latestEvent != null
                ? AppTelemetryBuilder().build(telemetry.latestEvent!)
                : <AppTelemetry>[];
            AppTelemetry? foundApp;
            for (final a in apps) {
              if (a.packageName == alert.packageName || a.appName == alert.appName) {
                foundApp = a;
                break;
              }
            }
            if (foundApp != null) {
              final analyzer = PermissionIntelligenceAnalyzer();
              final eval = analyzer.analyzeApp(foundApp);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppDetailsScreen(app: foundApp!, evaluation: eval),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('App ${alert.appName} details not found in current inventory.')),
              );
            }
          },
          icon: const Icon(Icons.info_outline, size: 13),
          label: const Text('Details', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.surfaceBorder),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),

        // Ask Guardian button
        OutlinedButton.icon(
          onPressed: () {
            final guardian = Provider.of<GuardianService>(context, listen: false);
            guardian.askGuardian(
              'Explain autonomous privacy alert for ${alert.appName}: ${alert.permission} is ${alert.currentState}. '
              'Agent recommendation was ${alert.agentRecommendation?.label ?? "NONE"}. '
              'Reason: ${alert.reason}. Context: ${alert.guardianExplanation}',
            );
            widget.onNavigateToGuardian?.call();
          },
          icon: const Icon(Icons.chat_bubble_outline, size: 13),
          label: const Text('Ask Agent', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),

        // Allow Button
        if (alert.agentRecommendation != null && agent != null)
          OutlinedButton.icon(
            onPressed: () async {
              await agent.handleUserDecision(
                evaluationId: alert.id,
                decision: AgentRecommendation.allow,
                packageName: alert.packageName,
                sensorType: alert.sensorType,
                appName: alert.appName,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Allowed ${alert.sensorType?.label ?? "sensor"} access for ${alert.appName}')),
                );
              }
            },
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Allow', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.statusNormal,
              side: const BorderSide(color: AppColors.statusNormal),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),

        // Block Button (Executes privileged Shizuku AppOps block)
        if (alert.sensorType != null && agent != null)
          ElevatedButton.icon(
            onPressed: () async {
              final result = await agent.handleUserDecision(
                evaluationId: alert.id,
                decision: AgentRecommendation.block,
                packageName: alert.packageName,
                sensorType: alert.sensorType,
                appName: alert.appName,
              );
              if (context.mounted) {
                final success = result['success'] == true;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: success ? AppColors.surfaceElevated : AppColors.statusAttention,
                    content: Text(
                      success
                          ? '🚫 Blocked ${alert.sensorType!.label} for ${alert.appName} via Shizuku'
                          : 'Block failed: ${result['error'] ?? "Unknown error"}',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.block, size: 13),
            label: const Text('Block', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusAttention,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
      ],
    );
  }
}
