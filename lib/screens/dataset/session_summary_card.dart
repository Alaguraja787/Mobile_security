import 'package:flutter/material.dart';

/// Interactive summary metrics card displaying actual aggregated statistics
/// computed from real persisted records in [StorageService].
class SessionSummaryCard extends StatelessWidget {
  final Map<String, dynamic> summary;
  final VoidCallback? onRefresh;
  final VoidCallback? onExport;
  final VoidCallback? onDelete;

  const SessionSummaryCard({
    super.key,
    required this.summary,
    this.onRefresh,
    this.onExport,
    this.onDelete,
  });

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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionId = summary['sessionId']?.toString() ?? 'all';
    final recordCount = (summary['recordCount'] as num?)?.toInt() ?? 0;
    final firstTs = summary['firstTimestamp']?.toString() ?? '';
    final lastTs = summary['lastTimestamp']?.toString() ?? '';
    final durationSec = (summary['durationSeconds'] as num?)?.toInt() ?? 0;
    final sizeBytes = (summary['storageSizeBytes'] as num?)?.toInt() ?? 0;

    final uniquePkgs = (summary['uniquePackages'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final packageCounts = Map<String, int>.from(summary['packageCounts'] ?? {});
    final micCount = (summary['micActiveRecords'] as num?)?.toInt() ?? 0;
    final camCount = (summary['cameraActiveRecords'] as num?)?.toInt() ?? 0;
    final netCount = (summary['networkActiveRecords'] as num?)?.toInt() ?? 0;
    final fgCount = (summary['foregroundRecords'] as num?)?.toInt() ?? 0;

    final availMap = Map<String, int>.from(summary['availabilityBreakdown'] ?? {});

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session Header Card
          Card(
            color: Colors.deepPurple.shade900.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.deepPurple.shade400.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics, color: Colors.cyanAccent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sessionId == 'all' ? 'Entire Dataset Analytics' : 'Session: $sessionId',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onRefresh != null)
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Refresh Summary',
                          onPressed: onRefresh,
                        ),
                    ],
                  ),
                  const Divider(height: 20),
                  _buildMetaRow(
                    'Time Range',
                    firstTs.isEmpty
                        ? 'No records'
                        : '${_formatTs(firstTs)} → ${_formatTs(lastTs)}',
                  ),
                  _buildMetaRow('Duration Observed', _formatDuration(durationSec)),
                  _buildMetaRow('Storage Footprint', _formatBytes(sizeBytes)),
                  _buildMetaRow('Total Persisted Records', '$recordCount records'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Primary KPI Grid
          Text(
            'Telemetry Activity Summary',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              _buildMetricCard(
                icon: Icons.mic,
                label: 'Microphone Active',
                value: '$micCount',
                subtext: recordCount > 0
                    ? '${((micCount / recordCount) * 100).toStringAsFixed(1)}% of records'
                    : '0%',
                color: micCount > 0 ? Colors.amberAccent : Colors.white60,
              ),
              _buildMetricCard(
                icon: Icons.camera_alt,
                label: 'Camera Active',
                value: '$camCount',
                subtext: recordCount > 0
                    ? '${((camCount / recordCount) * 100).toStringAsFixed(1)}% of records'
                    : '0%',
                color: camCount > 0 ? Colors.redAccent : Colors.white60,
              ),
              _buildMetricCard(
                icon: Icons.open_in_browser,
                label: 'Foreground Apps',
                value: '$fgCount',
                subtext: recordCount > 0
                    ? '${((fgCount / recordCount) * 100).toStringAsFixed(1)}% of records'
                    : '0%',
                color: Colors.greenAccent,
              ),
              _buildMetricCard(
                icon: Icons.network_check,
                label: 'Network Traffic',
                value: '$netCount',
                subtext: recordCount > 0
                    ? '${((netCount / recordCount) * 100).toStringAsFixed(1)}% of records'
                    : '0%',
                color: Colors.cyanAccent,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Observed Apps Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.apps, color: Colors.purpleAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Observed Applications (${uniquePkgs.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  if (uniquePkgs.isEmpty)
                    const Text(
                      'No applications recorded.',
                      style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: uniquePkgs.map((pkg) {
                        final count = packageCounts[pkg] ?? 0;
                        return Chip(
                          avatar: CircleAvatar(
                            backgroundColor: Colors.purple.shade700,
                            child: Text(
                              count.toString(),
                              style: const TextStyle(fontSize: 10, color: Colors.white),
                            ),
                          ),
                          label: Text(
                            pkg,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.black26,
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Availability Breakdown Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.tealAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Feature Availability & Missingness Breakdown',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  ...availMap.entries.map((entry) {
                    final status = entry.key;
                    final count = entry.value;
                    final color = _getStatusColor(status);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              status,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                          Text(
                            '$count features',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // Actions
          if (onExport != null || onDelete != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                if (onExport != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Export Session'),
                      onPressed: onExport,
                    ),
                  ),
                if (onExport != null && onDelete != null) const SizedBox(width: 12),
                if (onDelete != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Session'),
                      onPressed: onDelete,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String subtext,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            subtext,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTs(String ts) {
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
