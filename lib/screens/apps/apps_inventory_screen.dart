import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/app_telemetry.dart';
import '../../models/privacy_event.dart';
import '../../services/permission_intelligence_analyzer.dart';
import '../../telemetry/app_telemetry_builder.dart';
import '../../telemetry/telemetry_service.dart';
import 'app_details_screen.dart';
import '../../widgets/app_icon_widget.dart';

class AppsInventoryScreen extends StatefulWidget {
  final TelemetryService telemetryService;

  const AppsInventoryScreen({
    super.key,
    required this.telemetryService,
  });

  @override
  State<AppsInventoryScreen> createState() => _AppsInventoryScreenState();
}

class _AppsInventoryScreenState extends State<AppsInventoryScreen> {
  final AppTelemetryBuilder _builder = AppTelemetryBuilder();
  final PermissionIntelligenceAnalyzer _analyzer = PermissionIntelligenceAnalyzer();

  List<AppTelemetry> _allApps = [];
  List<AppTelemetry> _filteredApps = [];
  bool _isLoading = true;

  String _searchQuery = '';
  String _filterRisk = 'ALL'; // ALL, ATTENTION, REVIEW, NORMAL, SYSTEM, USER
  String _sortBy = 'RISK';    // RISK, NAME, PERMISSIONS

  @override
  void initState() {
    super.initState();
    final cached = widget.telemetryService.latestEvent;
    if (cached != null) {
      _allApps = _builder.build(cached);
      _isLoading = false;
      _applyFilters();
    } else {
      widget.telemetryService.refreshOnce();
    }
    _listenTelemetry();
  }

  void _listenTelemetry() {
    widget.telemetryService.stream.listen((PrivacyEvent event) {
      final apps = _builder.build(event);
      if (!mounted) return;
      setState(() {
        _allApps = apps;
        _isLoading = false;
        _applyFilters();
      });
    });
  }

  void _applyFilters() {
    List<AppTelemetry> list = List.from(_allApps);

    // Search Filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((a) =>
          a.appName.toLowerCase().contains(q) ||
          a.packageName.toLowerCase().contains(q)).toList();
    }

    // Category / Risk Filter
    if (_filterRisk != 'ALL') {
      list = list.where((a) {
        final res = _analyzer.analyzeApp(a);
        if (_filterRisk == 'ATTENTION') {
          return res.level == PermissionRiskLevel.attention ||
              res.level == PermissionRiskLevel.high ||
              res.level == PermissionRiskLevel.critical;
        }
        if (_filterRisk == 'REVIEW') return res.level == PermissionRiskLevel.review;
        if (_filterRisk == 'NORMAL') {
          return res.level == PermissionRiskLevel.normal ||
              res.level == PermissionRiskLevel.low ||
              res.level == PermissionRiskLevel.expected;
        }
        if (_filterRisk == 'SYSTEM') return a.isSystemApp;
        if (_filterRisk == 'USER') return !a.isSystemApp;
        return true;
      }).toList();
    }

    // Sort
    list.sort((a, b) {
      if (_sortBy == 'RISK') {
        final scoreA = _analyzer.analyzeApp(a).riskScore;
        final scoreB = _analyzer.analyzeApp(b).riskScore;
        return scoreB.compareTo(scoreA); // Highest risk first
      } else if (_sortBy == 'PERMISSIONS') {
        return b.grantedPermissions.length.compareTo(a.grantedPermissions.length);
      } else {
        return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      }
    });

    setState(() {
      _filteredApps = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Discovered Applications (${_filteredApps.length})'),
      ),
      body: Column(
        children: [
          // Search & Filter Controls Bar
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.surface,
            child: Column(
              children: [
                TextField(
                  onChanged: (val) {
                    _searchQuery = val;
                    _applyFilters();
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search app name or package...',
                    prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All Apps', 'ALL'),
                            const SizedBox(width: 6),
                            _buildFilterChip('🔴 Attention', 'ATTENTION'),
                            const SizedBox(width: 6),
                            _buildFilterChip('🟡 Review', 'REVIEW'),
                            const SizedBox(width: 6),
                            _buildFilterChip('🟢 Normal', 'NORMAL'),
                            const SizedBox(width: 6),
                            _buildFilterChip('User Apps', 'USER'),
                            const SizedBox(width: 6),
                            _buildFilterChip('System Apps', 'SYSTEM'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _sortBy,
                      dropdownColor: AppColors.surfaceElevated,
                      style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'RISK', child: Text('Sort: Risk')),
                        DropdownMenuItem(value: 'PERMISSIONS', child: Text('Sort: Perms')),
                        DropdownMenuItem(value: 'NAME', child: Text('Sort: Name')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _sortBy = val;
                            _applyFilters();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // App Inventory List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredApps.isEmpty
                    ? const Center(
                        child: Text(
                          'No applications match the active filter criteria.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          final eval = _analyzer.analyzeApp(app);

                          Color statusColor = AppColors.statusNormal;
                          if (eval.level == PermissionRiskLevel.critical) {
                            statusColor = Colors.redAccent;
                          } else if (eval.level == PermissionRiskLevel.high || eval.level == PermissionRiskLevel.attention) {
                            statusColor = AppColors.statusAttention;
                          } else if (eval.level == PermissionRiskLevel.review) {
                            statusColor = AppColors.statusReview;
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AppDetailsScreen(
                                      app: app,
                                      evaluation: eval,
                                    ),
                                  ),
                                );
                              },
                              leading: AppIconWidget(
                                packageName: app.packageName,
                                appName: app.appName,
                                size: 44,
                              ),
                              title: Text(
                                app.appName.isNotEmpty ? app.appName : app.packageName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    app.packageName,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${app.requestedPermissions.length} permissions • ${app.grantedPermissions.length} granted',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: statusColor),
                                    ),
                                    child: Text(
                                      '${eval.levelEmoji} ${eval.levelLabel}',
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final bool isSelected = _filterRisk == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : AppColors.textSecondary)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _filterRisk = value;
            _applyFilters();
          });
        }
      },
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceElevated,
    );
  }
}
