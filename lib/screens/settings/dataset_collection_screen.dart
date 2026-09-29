import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../phase2/dataset/collection_session.dart';
import '../../phase2/dataset/dataset_collector.dart';
import '../../services/storage_service.dart';
import '../dataset/dataset_viewer_screen.dart';

/// Screen for controlling real Android telemetry collection sessions,
/// monitoring live recording counters, inspecting storage size, and exporting datasets.
class DatasetCollectionScreen extends StatefulWidget {
  final DatasetCollector collector;
  final StorageService storage;

  const DatasetCollectionScreen({
    super.key,
    required this.collector,
    required this.storage,
  });

  @override
  State<DatasetCollectionScreen> createState() =>
      _DatasetCollectionScreenState();
}

class _DatasetCollectionScreenState extends State<DatasetCollectionScreen> {
  late CollectionSession _currentSession;
  List<Map<String, dynamic>> _historicalSessions = [];
  int _totalStorageBytes = 0;
  int _totalStorageRecords = 0;
  bool _isLoading = false;
  String? _exportSuccessMessage;
  Timer? _uiRefreshTimer;
  StreamSubscription<CollectionSession>? _sessionSub;

  @override
  void initState() {
    super.initState();
    _currentSession = widget.collector.getCollectionStatus();

    _sessionSub = widget.collector.sessionStream.listen((session) {
      if (mounted) {
        setState(() {
          _currentSession = session;
        });
      }
    });

    _refreshMetrics();
    // Periodic refresh while on this screen to update storage counters
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _refreshMetrics();
    });
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshMetrics() async {
    final size = await widget.storage.getStorageSizeBytes();
    final summaries = await widget.storage.getSessionSummaries();
    final count = widget.storage.cachedRecordCount;

    if (mounted) {
      setState(() {
        _totalStorageBytes = size;
        _totalStorageRecords = count;
        _historicalSessions = summaries;
        _currentSession = widget.collector.getCollectionStatus();
      });
    }
  }

  Future<void> _toggleCollection() async {
    setState(() => _isLoading = true);

    if (widget.collector.isCollecting) {
      await widget.collector.stopCollection();
    } else {
      widget.collector.startCollection();
    }

    await _refreshMetrics();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportDataset({String? sessionId}) async {
    setState(() {
      _isLoading = true;
      _exportSuccessMessage = null;
    });

    try {
      final now = DateTime.now();
      final suffix = sessionId != null ? '_$sessionId' : '_all';
      final fileName = 'dataset_export${suffix}_${now.millisecondsSinceEpoch}.json';
      Directory baseDir;
      try {
        baseDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        baseDir = Directory.current;
      }
      final exportFile = File(p.join(baseDir.path, fileName));

      bool success;
      if (sessionId != null) {
        success = await widget.collector.exportSessionToFile(sessionId, exportFile);
      } else {
        success = await widget.storage.exportToFile(exportFile);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _exportSuccessMessage = success
              ? 'Dataset exported successfully to:\n${exportFile.absolute.path}'
              : 'Export failed. Check storage permissions.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _exportSuccessMessage = 'Export error: $e';
        });
      }
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Collected Data?'),
        content: const Text(
          'This will permanently delete all persisted real-world telemetry records from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Storage'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await widget.collector.clear(clearStorage: true);
      await _refreshMetrics();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _exportSuccessMessage = 'Local telemetry storage cleared.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCollecting = widget.collector.isCollecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dataset Collection & Storage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'View Collected Dataset',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DatasetViewerScreen(
                    storage: widget.storage,
                    collector: widget.collector,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Metrics',
            onPressed: _refreshMetrics,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSessionStatusCard(isCollecting),
          const SizedBox(height: 16),
          _buildStorageMetricsCard(),
          const SizedBox(height: 16),
          _buildActionControls(isCollecting),
          const SizedBox(height: 16),
          if (_exportSuccessMessage != null) _buildExportFeedbackCard(),
          const SizedBox(height: 16),
          _buildHistoricalSessionsCard(),
        ],
      ),
    );
  }

  Widget _buildSessionStatusCard(bool isCollecting) {
    final statusColor = isCollecting
        ? Colors.greenAccent
        : (_currentSession.state == CollectionState.stopped
            ? Colors.blueAccent
            : Colors.orangeAccent);

    return Card(
      color: Colors.deepPurple.shade900.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: isCollecting
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Collection Status: ${_currentSession.state.toFormattedString()}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildDataRow('Active Session ID', _currentSession.sessionId),
            _buildDataRow('Start Time', _currentSession.startTime),
            if (_currentSession.stopTime != null)
              _buildDataRow('Stop Time', _currentSession.stopTime!),
            _buildDataRow(
              'Session Records Captured',
              '${_currentSession.recordCount} records',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageMetricsCard() {
    final sizeKb = (_totalStorageBytes / 1024).toStringAsFixed(1);
    final sizeMb = (_totalStorageBytes / 1024 / 1024).toStringAsFixed(2);
    final sizeStr = _totalStorageBytes > 1024 * 1024 ? '$sizeMb MB' : '$sizeKb KB';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text(
                  'Persistent Local Storage',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildDataRow('Storage Format', 'Append-Safe JSON Lines (.jsonl)'),
            _buildDataRow('Total Persisted Records', '$_totalStorageRecords records'),
            _buildDataRow('Total Storage File Size', sizeStr),
            _buildDataRow('Max Configured Retention', '${widget.storage.maxRecords} records (FIFO)'),
            _buildDataRow('Memory Buffer Status', '${widget.collector.recordCount} records in RAM'),
          ],
        ),
      ),
    );
  }

  Widget _buildActionControls(bool isCollecting) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isCollecting ? Colors.redAccent : Colors.green.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(isCollecting ? Icons.stop : Icons.play_arrow),
            label: Text(
              isCollecting ? 'STOP COLLECTION SESSION' : 'START COLLECTION SESSION',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onPressed: _isLoading ? null : _toggleCollection,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text(
              'VIEW COLLECTED DATASET',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DatasetViewerScreen(
                    storage: widget.storage,
                    collector: widget.collector,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.file_download),
                label: const Text('Export All'),
                onPressed: _isLoading ? null : () => _exportDataset(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear Storage'),
                onPressed: _isLoading ? null : _clearAll,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExportFeedbackCard() {
    final isSuccess = !_exportSuccessMessage!.toLowerCase().contains('failed') &&
        !_exportSuccessMessage!.toLowerCase().contains('error');
    final color = isSuccess ? Colors.greenAccent : Colors.redAccent;

    return Card(
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _exportSuccessMessage!,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoricalSessionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historical Sessions (${_historicalSessions.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            if (_historicalSessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'No historical sessions recorded yet.',
                  style: TextStyle(color: Colors.white60, fontStyle: FontStyle.italic),
                ),
              )
            else
              ..._historicalSessions.map((session) {
                final sId = session['sessionId']?.toString() ?? 'unknown';
                final count = session['recordCount'] ?? 0;
                final lastTs = session['lastTimestamp']?.toString() ?? '';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history, color: Colors.purpleAccent),
                  title: Text(
                    sId,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$count records • Last: ${lastTs.length > 19 ? lastTs.substring(0, 19) : lastTs}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DatasetViewerScreen(
                          storage: widget.storage,
                          collector: widget.collector,
                          initialSessionId: sId,
                        ),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 20),
                        tooltip: 'View in Dataset Viewer',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DatasetViewerScreen(
                                storage: widget.storage,
                                collector: widget.collector,
                                initialSessionId: sId,
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.download, size: 20),
                        tooltip: 'Export Session',
                        onPressed: () => _exportDataset(sessionId: sId),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                        tooltip: 'Delete Session',
                        onPressed: () async {
                          await widget.storage.deleteSession(sId);
                          await _refreshMetrics();
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
