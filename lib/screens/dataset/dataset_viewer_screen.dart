import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../phase2/dataset/collection_session.dart';
import '../../phase2/dataset/dataset_collector.dart';
import '../../phase2/dataset/dataset_record.dart';
import '../../services/storage_service.dart';
import 'models/dataset_filter_options.dart';
import 'record_detail_screen.dart';
import 'session_summary_card.dart';

/// Human-readable dataset viewer for inspecting real persisted telemetry records
/// directly through [StorageService] with memory-bounded pagination, search & filter,
/// aggregated session statistics, and export/delete operations.
class DatasetViewerScreen extends StatefulWidget {
  final StorageService storage;
  final DatasetCollector collector;
  final String? initialSessionId;
  final bool enableLiveTicker;

  const DatasetViewerScreen({
    super.key,
    required this.storage,
    required this.collector,
    this.initialSessionId,
    this.enableLiveTicker = true,
  });

  @override
  State<DatasetViewerScreen> createState() => _DatasetViewerScreenState();
}

class _DatasetViewerScreenState extends State<DatasetViewerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Pagination state
  int _currentPage = 0;
  final int _pageSize = 25;
  int _totalMatchingRecords = 0;
  List<DatasetRecord> _pagedRecords = [];
  bool _isLoadingRecords = false;

  // Filter state
  late DatasetFilterOptions _filterOptions;
  final TextEditingController _searchController = TextEditingController();

  // Sessions state
  List<Map<String, dynamic>> _historicalSessions = [];
  Map<String, dynamic> _sessionSummary = {};
  bool _isLoadingSummary = false;

  // Live collection state
  late CollectionSession _liveSession;
  StreamSubscription<CollectionSession>? _sessionSubscription;
  Timer? _liveTickerTimer;
  int _liveStorageBytes = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _filterOptions = DatasetFilterOptions(sessionId: widget.initialSessionId);

    _liveSession = widget.collector.getCollectionStatus();
    _sessionSubscription = widget.collector.sessionStream.listen((session) {
      if (mounted) {
        setState(() {
          _liveSession = session;
        });
      }
    });

    // Refresh live storage size periodically if live ticker enabled
    if (widget.enableLiveTicker) {
      _liveTickerTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) _refreshLiveMetrics();
      });
    }

    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _sessionSubscription?.cancel();
    _liveTickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLiveMetrics() async {
    final size = await widget.storage.getStorageSizeBytes();
    if (mounted) {
      setState(() {
        _liveStorageBytes = size;
        _liveSession = widget.collector.getCollectionStatus();
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadHistoricalSessions(),
      _loadRecords(resetPage: true),
      _loadSummary(),
      _refreshLiveMetrics(),
    ]);
  }

  Future<void> _loadHistoricalSessions() async {
    final summaries = await widget.storage.getSessionSummaries();
    if (mounted) {
      setState(() {
        _historicalSessions = summaries;
      });
    }
  }

  Future<void> _loadRecords({bool resetPage = false}) async {
    if (resetPage) _currentPage = 0;

    setState(() => _isLoadingRecords = true);

    try {
      final total = await widget.storage.countRecords(
        sessionId: _filterOptions.sessionId,
        startTime: _filterOptions.startTime,
        endTime: _filterOptions.endTime,
        packageNameQuery: _filterOptions.searchQuery,
        availabilityFilter: _filterOptions.availabilityFilter,
        hasMicActivity: _filterOptions.micActiveOnly ? true : null,
        hasCameraActivity: _filterOptions.cameraActiveOnly ? true : null,
        hasForegroundActivity: _filterOptions.foregroundOnly ? true : null,
        hasNetworkActivity: _filterOptions.networkOnly ? true : null,
      );

      final offset = _currentPage * _pageSize;
      final records = await widget.storage.getRecords(
        limit: _pageSize,
        offset: offset,
        sessionId: _filterOptions.sessionId,
        startTime: _filterOptions.startTime,
        endTime: _filterOptions.endTime,
        packageNameQuery: _filterOptions.searchQuery,
        availabilityFilter: _filterOptions.availabilityFilter,
        hasMicActivity: _filterOptions.micActiveOnly ? true : null,
        hasCameraActivity: _filterOptions.cameraActiveOnly ? true : null,
        hasForegroundActivity: _filterOptions.foregroundOnly ? true : null,
        hasNetworkActivity: _filterOptions.networkOnly ? true : null,
      );

      if (mounted) {
        setState(() {
          _totalMatchingRecords = total;
          _pagedRecords = records;
          _isLoadingRecords = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRecords = false);
      }
    }
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoadingSummary = true);
    try {
      final details = await widget.storage.getSessionSummaryDetails(
        sessionId: _filterOptions.sessionId,
      );
      if (mounted) {
        setState(() {
          _sessionSummary = details;
          _isLoadingSummary = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSummary = false);
    }
  }

  void _onSessionSelected(String? sessionId) {
    setState(() {
      _filterOptions = _filterOptions.copyWith(
        sessionId: sessionId,
        clearSessionId: sessionId == null,
      );
    });
    _loadRecords(resetPage: true);
    _loadSummary();
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter Persisted Records',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _filterOptions = _filterOptions.reset();
                              _searchController.clear();
                            });
                          },
                          child: const Text('Reset All'),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Session Selector
                    const Text(
                      'Collection Session',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      initialValue: _filterOptions.sessionId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Sessions (Entire Dataset)'),
                        ),
                        ..._historicalSessions.map((s) {
                          final sId = s['sessionId']?.toString() ?? '';
                          final count = s['recordCount'] ?? 0;
                          return DropdownMenuItem(
                            value: sId,
                            child: Text('$sId ($count records)'),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          _filterOptions = _filterOptions.copyWith(
                            sessionId: val,
                            clearSessionId: val == null,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 14),

                    // Availability Status Filter
                    const Text(
                      'Feature Availability Status',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      initialValue: _filterOptions.availabilityFilter,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All Availability States')),
                        DropdownMenuItem(value: 'VALID', child: Text('VALID (Normal)')),
                        DropdownMenuItem(value: 'ZERO_REPORTED', child: Text('ZERO_REPORTED (True Zero)')),
                        DropdownMenuItem(value: 'RESTRICTED', child: Text('RESTRICTED (Missing/Denied AppOp)')),
                        DropdownMenuItem(value: 'DENIED', child: Text('DENIED (Revoked/Refused)')),
                        DropdownMenuItem(value: 'UNAVAILABLE', child: Text('UNAVAILABLE (No Sensor/Hardware)')),
                        DropdownMenuItem(value: 'ERROR', child: Text('ERROR (Query Failed)')),
                        DropdownMenuItem(value: 'UNKNOWN', child: Text('UNKNOWN (Unreported)')),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          _filterOptions = _filterOptions.copyWith(
                            availabilityFilter: val,
                            clearAvailabilityFilter: val == null,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 14),

                    // Activity Flags
                    const Text(
                      'Telemetry Activity Filters',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Microphone Active Only'),
                      subtitle: const Text('Records with active hardware audio capture'),
                      value: _filterOptions.micActiveOnly,
                      onChanged: (v) => setModalState(
                          () => _filterOptions = _filterOptions.copyWith(micActiveOnly: v)),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Camera Active Only'),
                      subtitle: const Text('Records with active camera hardware use'),
                      value: _filterOptions.cameraActiveOnly,
                      onChanged: (v) => setModalState(
                          () => _filterOptions = _filterOptions.copyWith(cameraActiveOnly: v)),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Foreground Apps Only'),
                      subtitle: const Text('Records where app was actively in foreground'),
                      value: _filterOptions.foregroundOnly,
                      onChanged: (v) => setModalState(
                          () => _filterOptions = _filterOptions.copyWith(foregroundOnly: v)),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Network Activity Only'),
                      subtitle: const Text('Records with non-zero upload/download bytes'),
                      value: _filterOptions.networkOnly,
                      onChanged: (v) => setModalState(
                          () => _filterOptions = _filterOptions.copyWith(networkOnly: v)),
                    ),
                    const SizedBox(height: 20),

                    // Apply Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {});
                          _loadRecords(resetPage: true);
                          _loadSummary();
                        },
                        child: const Text('APPLY FILTERS', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportData({String? sessionId}) async {
    final targetSession = sessionId ?? _filterOptions.sessionId;
    final now = DateTime.now();
    final suffix = targetSession != null ? '_$targetSession' : '_all';
    final fileName = 'dataset_export${suffix}_${now.millisecondsSinceEpoch}.json';
    Directory baseDir;
    try {
      baseDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = Directory.current;
    }
    final exportFile = File(p.join(baseDir.path, fileName));

    try {
      bool success;
      if (targetSession != null) {
        success = await widget.collector.exportSessionToFile(targetSession, exportFile);
      } else {
        success = await widget.storage.exportToFile(exportFile);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? Colors.green.shade800 : Colors.red.shade800,
            content: Text(
              success
                  ? 'Dataset exported to:\n${exportFile.absolute.path}'
                  : 'Export failed. Check storage permissions.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('Export error: $e'),
          ),
        );
      }
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Collection Session?'),
        content: Text('Delete all persisted telemetry records for session:\n"$sessionId"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Session'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.storage.deleteSession(sessionId);
      if (_filterOptions.sessionId == sessionId) {
        _filterOptions = _filterOptions.copyWith(clearSessionId: true);
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted records for session: $sessionId')),
        );
      }
    }
  }

  Future<void> _deleteAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Collected Data?'),
        content: const Text(
          'This will permanently delete all persisted telemetry records in local storage. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.collector.clear(clearStorage: true);
      _filterOptions = _filterOptions.reset();
      _searchController.clear();
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All local telemetry records cleared.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dataset Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter Records',
            onPressed: _showFilterModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh All',
            onPressed: _refreshAll,
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'export_current') {
                _exportData();
              } else if (val == 'export_all') {
                _exportData(sessionId: null);
              } else if (val == 'clear_all') {
                _deleteAllData();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'export_current',
                child: Row(
                  children: [
                    const Icon(Icons.file_download, size: 18),
                    const SizedBox(width: 8),
                    Text(_filterOptions.sessionId != null
                        ? 'Export Selected Session'
                        : 'Export Active View'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_all',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 18),
                    SizedBox(width: 8),
                    Text('Export All Records'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Clear All Data', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          tabs: [
            Tab(
              icon: const Icon(Icons.list_alt),
              text: 'Records ($_totalMatchingRecords)',
            ),
            const Tab(
              icon: Icon(Icons.bar_chart),
              text: 'Summary',
            ),
            Tab(
              icon: const Icon(Icons.folder_outlined),
              text: 'Sessions (${_historicalSessions.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Live status & session picker header
          _buildLiveStatusHeader(),
          _buildActiveFiltersBar(),

          // Main Tab View
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRecordsTab(),
                _buildSummaryTab(),
                _buildSessionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TOP LIVE STATUS & SESSION SELECTOR
  // ==========================================================
  Widget _buildLiveStatusHeader() {
    final isCollecting = widget.collector.isCollecting;
    final sizeKb = (_liveStorageBytes / 1024).toStringAsFixed(1);
    final sizeMb = (_liveStorageBytes / (1024 * 1024)).toStringAsFixed(2);
    final sizeStr = _liveStorageBytes > 1024 * 1024 ? '$sizeMb MB' : '$sizeKb KB';

    int elapsedSec = 0;
    if (isCollecting && _liveSession.startTime.isNotEmpty) {
      final start = DateTime.tryParse(_liveSession.startTime);
      if (start != null) {
        elapsedSec = DateTime.now().difference(start).inSeconds.clamp(0, 9999999);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: isCollecting
          ? Colors.green.shade900.withValues(alpha: 0.25)
          : const Color(0xFF141420),
      child: Row(
        children: [
          // Live indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isCollecting ? Colors.greenAccent : Colors.white38,
              shape: BoxShape.circle,
              boxShadow: isCollecting
                  ? [
                      BoxShadow(
                        color: Colors.greenAccent.withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isCollecting ? 'COLLECTING' : 'STORAGE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isCollecting ? Colors.greenAccent : Colors.white70,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 10),
          if (isCollecting) ...[
            Text(
              'Elapsed: ${_formatDuration(elapsedSec)}',
              style: const TextStyle(fontSize: 11, color: Colors.greenAccent),
            ),
            const SizedBox(width: 8),
            Text(
              '• Live: ${_liveSession.recordCount} recs',
              style: const TextStyle(fontSize: 11, color: Colors.greenAccent),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            'Size: $sizeStr',
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(width: 8),
          Text(
            '• Total: ${widget.storage.cachedRecordCount} records',
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const Spacer(),
          // Quick session dropdown
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _filterOptions.sessionId,
              isDense: true,
              style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
              dropdownColor: const Color(0xFF1E1E2C),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Sessions', style: TextStyle(fontSize: 11)),
                ),
                ..._historicalSessions.map((s) {
                  final id = s['sessionId']?.toString() ?? '';
                  final count = s['recordCount'] ?? 0;
                  final label = id.length > 15 ? '${id.substring(0, 15)}...' : id;
                  return DropdownMenuItem(
                    value: id,
                    child: Text('$label ($count)', style: const TextStyle(fontSize: 11)),
                  );
                }),
              ],
              onChanged: _onSessionSelected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersBar() {
    if (!_filterOptions.hasActiveFilters && _searchController.text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      color: Colors.deepPurple.shade900.withValues(alpha: 0.2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text('Filters:', style: TextStyle(fontSize: 11, color: Colors.white60)),
            const SizedBox(width: 6),
            if (_filterOptions.sessionId != null)
              _buildFilterChip('Session: ${_filterOptions.sessionId}', () {
                setState(() => _filterOptions = _filterOptions.copyWith(clearSessionId: true));
                _loadRecords(resetPage: true);
                _loadSummary();
              }),
            if (_filterOptions.searchQuery != null && _filterOptions.searchQuery!.isNotEmpty)
              _buildFilterChip('Search: "${_filterOptions.searchQuery}"', () {
                _searchController.clear();
                setState(() => _filterOptions = _filterOptions.copyWith(clearSearchQuery: true));
                _loadRecords(resetPage: true);
              }),
            if (_filterOptions.availabilityFilter != null)
              _buildFilterChip('Status: ${_filterOptions.availabilityFilter}', () {
                setState(() => _filterOptions = _filterOptions.copyWith(clearAvailabilityFilter: true));
                _loadRecords(resetPage: true);
              }),
            if (_filterOptions.micActiveOnly)
              _buildFilterChip('Mic Active', () {
                setState(() => _filterOptions = _filterOptions.copyWith(micActiveOnly: false));
                _loadRecords(resetPage: true);
              }),
            if (_filterOptions.cameraActiveOnly)
              _buildFilterChip('Cam Active', () {
                setState(() => _filterOptions = _filterOptions.copyWith(cameraActiveOnly: false));
                _loadRecords(resetPage: true);
              }),
            if (_filterOptions.foregroundOnly)
              _buildFilterChip('Foreground', () {
                setState(() => _filterOptions = _filterOptions.copyWith(foregroundOnly: false));
                _loadRecords(resetPage: true);
              }),
            if (_filterOptions.networkOnly)
              _buildFilterChip('Network', () {
                setState(() => _filterOptions = _filterOptions.copyWith(networkOnly: false));
                _loadRecords(resetPage: true);
              }),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                _searchController.clear();
                setState(() => _filterOptions = _filterOptions.reset());
                _loadRecords(resetPage: true);
                _loadSummary();
              },
              child: const Text('Clear All', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onDeleted) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 10)),
        deleteIcon: const Icon(Icons.close, size: 12),
        onDeleted: onDeleted,
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.deepPurple.shade700.withValues(alpha: 0.5),
        padding: EdgeInsets.zero,
      ),
    );
  }

  // ==========================================================
  // TAB 1: RECORDS TAB (PAGINATED)
  // ==========================================================
  Widget _buildRecordsTab() {
    return Column(
      children: [
        // Search & Quick Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search package or app name...',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _filterOptions =
                                  _filterOptions.copyWith(clearSearchQuery: true));
                              _loadRecords(resetPage: true);
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (val) {
                    setState(() {
                      _filterOptions = _filterOptions.copyWith(
                        searchQuery: val.trim(),
                        clearSearchQuery: val.trim().isEmpty,
                      );
                    });
                    _loadRecords(resetPage: true);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: Badge(
                  isLabelVisible: _filterOptions.hasActiveFilters,
                  label: Text('${_filterOptions.activeFilterCount}'),
                  child: const Icon(Icons.tune, size: 20),
                ),
                tooltip: 'Advanced Filters',
                onPressed: _showFilterModal,
              ),
            ],
          ),
        ),

        // Records List
        Expanded(
          child: _isLoadingRecords
              ? const Center(child: CircularProgressIndicator())
              : _pagedRecords.isEmpty
                  ? _buildEmptyRecordsView()
                  : RefreshIndicator(
                      onRefresh: () => _loadRecords(resetPage: false),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        itemCount: _pagedRecords.length,
                        itemBuilder: (context, index) {
                          final record = _pagedRecords[index];
                          return _buildRecordCard(record);
                        },
                      ),
                    ),
        ),

        // Pagination Bar
        _buildPaginationBar(),
      ],
    );
  }

  Widget _buildRecordCard(DatasetRecord record) {
    final raw = record.rawTelemetry;
    final app = Map<String, dynamic>.from(raw['app'] ?? {});
    final sensor = Map<String, dynamic>.from(raw['sensorTelemetry'] ?? {});

    final isForeground = app['isCurrentlyForeground'] == true;
    final isMicActive = sensor['microphoneHardwareInUse'] == true ||
        (sensor['activeAudioRecordingsCount'] as num? ?? 0) > 0;
    final isCamActive = sensor['cameraHardwareInUse'] == true;
    final isCamUnavailable = sensor['cameraUnavailable'] == true;
    final appTx = (app['uploadBytes'] as num? ?? 0);
    final appRx = (app['downloadBytes'] as num? ?? 0);
    final hasTraffic = appTx > 0 || appRx > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isForeground
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.white10,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => RecordDetailScreen(record: record),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: App identifier & timestamp
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app['appName']?.toString().isNotEmpty == true
                              ? '${app['appName']} (${record.packageName})'
                              : record.packageName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTimestamp(record.timestamp),
                          style: const TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildHealthBadge(record.collectorHealthStatus),
                ],
              ),
              const SizedBox(height: 8),

              // Row 2: Telemetry Chips
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  // Foreground badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isForeground
                          ? Colors.green.shade900.withValues(alpha: 0.4)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isForeground ? Colors.greenAccent : Colors.transparent,
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      isForeground ? 'FOREGROUND' : 'BACKGROUND',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isForeground ? Colors.greenAccent : Colors.white60,
                      ),
                    ),
                  ),

                  // Mic indicator
                  if (isMicActive)
                    _buildIndicatorTag('MIC ACTIVE', Icons.mic, Colors.amberAccent),

                  // Camera indicator
                  if (isCamActive)
                    _buildIndicatorTag('CAMERA ACTIVE', Icons.camera_alt, Colors.redAccent),

                  // Camera availability state indicator
                  if (isCamUnavailable)
                    _buildIndicatorTag('CAM UNAVAILABLE', Icons.camera_alt_outlined, Colors.orangeAccent),

                  // Network indicator
                  if (hasTraffic)
                    _buildIndicatorTag(
                      '${_formatBytes(appTx)} tx / ${_formatBytes(appRx)} rx',
                      Icons.network_check,
                      Colors.cyanAccent,
                    ),

                  // Device snippet
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${record.androidVersion} (SDK ${record.sdkInt})',
                      style: const TextStyle(fontSize: 9, color: Colors.white54),
                    ),
                  ),

                  // Schema badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade900.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'v${record.featureVector.schemaVersion}',
                      style: const TextStyle(fontSize: 9, color: Colors.purpleAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndicatorTag(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyRecordsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 48, color: Colors.white30),
            const SizedBox(height: 12),
            const Text(
              'No Persisted Records Found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'No records match the current filters or no telemetry collection has occurred yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 16),
            if (_filterOptions.hasActiveFilters)
              OutlinedButton.icon(
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Clear Active Filters'),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _filterOptions = _filterOptions.reset());
                  _loadRecords(resetPage: true);
                  _loadSummary();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationBar() {
    final totalPages = (_totalMatchingRecords / _pageSize).ceil();
    final startIdx = _totalMatchingRecords == 0 ? 0 : (_currentPage * _pageSize) + 1;
    final endIdx = ((_currentPage + 1) * _pageSize).clamp(0, _totalMatchingRecords);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF141420),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          // Range info
          Text(
            'Showing $startIdx-$endIdx of $_totalMatchingRecords',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const Spacer(),

          // First page
          IconButton(
            icon: const Icon(Icons.first_page, size: 18),
            tooltip: 'First Page',
            onPressed: _currentPage > 0
                ? () {
                    setState(() => _currentPage = 0);
                    _loadRecords();
                  }
                : null,
          ),

          // Prev page
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            tooltip: 'Previous Page',
            onPressed: _currentPage > 0
                ? () {
                    setState(() => _currentPage--);
                    _loadRecords();
                  }
                : null,
          ),

          // Current Page indicator
          Text(
            '${totalPages == 0 ? 0 : _currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),

          // Next page
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            tooltip: 'Next Page',
            onPressed: (_currentPage + 1) < totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadRecords();
                  }
                : null,
          ),

          // Last page
          IconButton(
            icon: const Icon(Icons.last_page, size: 18),
            tooltip: 'Last Page',
            onPressed: (_currentPage + 1) < totalPages
                ? () {
                    setState(() => _currentPage = totalPages - 1);
                    _loadRecords();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TAB 2: SUMMARY TAB
  // ==========================================================
  Widget _buildSummaryTab() {
    if (_isLoadingSummary) {
      return const Center(child: CircularProgressIndicator());
    }

    return SessionSummaryCard(
      summary: _sessionSummary,
      onRefresh: _loadSummary,
      onExport: () => _exportData(sessionId: _filterOptions.sessionId),
      onDelete: _filterOptions.sessionId != null
          ? () => _deleteSession(_filterOptions.sessionId!)
          : null,
    );
  }

  // ==========================================================
  // TAB 3: HISTORICAL SESSIONS TAB
  // ==========================================================
  Widget _buildSessionsTab() {
    if (_historicalSessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.history, size: 48, color: Colors.white30),
              SizedBox(height: 12),
              Text(
                'No Collection Sessions Recorded',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'Start a collection session from the dashboard or settings to accumulate real device telemetry.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14.0),
      itemCount: _historicalSessions.length,
      itemBuilder: (context, index) {
        final s = _historicalSessions[index];
        final sId = s['sessionId']?.toString() ?? 'unknown';
        final count = s['recordCount'] ?? 0;
        final approxSize = s['approxSizeBytes'] ?? 0;
        final durationSec = s['durationSeconds'] ?? 0;
        final firstTs = s['firstTimestamp']?.toString() ?? '';
        final lastTs = s['lastTimestamp']?.toString() ?? '';
        final isSelected = _filterOptions.sessionId == sId;

        final isActive = widget.collector.isCollecting && widget.collector.currentSessionId == sId;
        final status = isActive ? 'ACTIVE' : (s['status']?.toString() ?? 'COMPLETED');
        final statusColor = isActive ? Colors.greenAccent : Colors.tealAccent;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? Colors.cyanAccent : Colors.white10,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check_circle : Icons.folder_outlined,
                      color: isSelected ? Colors.cyanAccent : Colors.purpleAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sId,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.cyanAccent : Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: statusColor, width: 0.7),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, size: 18),
                      tooltip: 'Export Session',
                      onPressed: () => _exportData(sessionId: sId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      tooltip: 'Delete Session',
                      onPressed: () => _deleteSession(sId),
                    ),
                  ],
                ),
                const Divider(height: 16),
                _buildSessionMetaRow('Records', '$count records'),
                _buildSessionMetaRow('Storage Size', _formatBytes(approxSize)),
                _buildSessionMetaRow('Duration', _formatDuration(durationSec)),
                _buildSessionMetaRow(
                  'Time Span',
                  firstTs.isEmpty ? '-' : '${_formatTimestamp(firstTs)} → ${_formatTimestamp(lastTs)}',
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(
                      isSelected ? Icons.visibility : Icons.filter_alt,
                      size: 16,
                    ),
                    label: Text(isSelected ? 'Currently Viewing' : 'View Session Records'),
                    onPressed: () {
                      _onSessionSelected(sId);
                      _tabController.animateTo(0); // Switch to records tab
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    final h = m ~/ 60;
    final remM = m % 60;
    if (h == 0) return '${m}m ${s}s';
    return '${h}h ${remM}m ${s}s';
  }

  String _formatBytes(dynamic v) {
    if (v == null) return '0 B';
    final num b = v is num ? v : (num.tryParse(v.toString()) ?? 0);
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatTimestamp(String ts) {
    if (ts.isEmpty) return '';
    return ts.length > 19 ? ts.substring(0, 19).replaceAll('T', ' ') : ts;
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'VALID':
        return Colors.greenAccent;
      case 'ZERO_REPORTED':
        return Colors.blueAccent;
      case 'DENIED':
        return Colors.orangeAccent;
      case 'RESTRICTED':
        return Colors.amberAccent;
      case 'UNAVAILABLE':
        return Colors.grey;
      case 'ERROR':
        return Colors.redAccent;
      case 'UNKNOWN':
      default:
        return Colors.blueGrey;
    }
  }
}
