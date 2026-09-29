import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../phase2/dataset/dataset_record.dart';

/// Structured, human-readable inspection screen for a single persisted [DatasetRecord].
/// Displays exact stored telemetry values categorized logically with availability status indicators.
class RecordDetailScreen extends StatefulWidget {
  final DatasetRecord record;

  const RecordDetailScreen({
    super.key,
    required this.record,
  });

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _copyRawJson() {
    final prettyJson =
        const JsonEncoder.withIndent('  ').convert(widget.record.toJson());
    Clipboard.setData(ClipboardData(text: prettyJson));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Raw record JSON copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.packageName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _formatTimestamp(r.timestamp),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_copied ? Icons.check : Icons.copy),
            tooltip: 'Copy Raw JSON',
            onPressed: _copyRawJson,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Telemetry'),
            Tab(icon: Icon(Icons.memory_outlined), text: '32 Features'),
            Tab(icon: Icon(Icons.code), text: 'Raw JSON'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStructuredTelemetryTab(),
          _buildFeaturesTab(),
          _buildRawJsonTab(),
        ],
      ),
    );
  }

  // ==========================================================
  // TAB 1: STRUCTURED TELEMETRY
  // ==========================================================
  Widget _buildStructuredTelemetryTab() {
    final r = widget.record;
    final raw = r.rawTelemetry;
    final app = Map<String, dynamic>.from(raw['app'] ?? {});
    final dev = Map<String, dynamic>.from(raw['deviceContext'] ?? {});
    final sec = Map<String, dynamic>.from(raw['securityContext'] ?? {});
    final net = Map<String, dynamic>.from(raw['network'] ?? {});
    final sensor = Map<String, dynamic>.from(raw['sensorTelemetry'] ?? {});
    final usage = Map<String, dynamic>.from(raw['usageSummary'] ?? {});

    return ListView(
      padding: const EdgeInsets.all(14.0),
      children: [
        // Top Header Banner
        _buildRecordHeaderCard(),
        const SizedBox(height: 12),

        // 1. Device Context
        _buildSectionCard(
          title: 'Device Context',
          icon: Icons.phone_android,
          color: Colors.blueAccent,
          items: [
            _item('Manufacturer', dev['manufacturer']),
            _item('Model', dev['model']),
            _item('Brand / Device', '${dev['brand']} (${dev['device']})'),
            _item('Board / Hardware', '${dev['board']} / ${dev['hardware']}'),
            _item('Android Version', '${dev['androidVersion']} (SDK ${dev['sdkInt']})'),
            _item('Screen Locked', _formatBool(dev['screenLocked'])),
            _item('Screen Interactive', _formatBool(dev['screenOn'])),
            _item('Device Secure (PIN/Pattern)', _formatBool(dev['isDeviceSecure'])),
            _item(
              'Battery Level',
              dev['batteryPercent'] != null ? '${dev['batteryPercent']}%' : 'null',
            ),
            _item('Battery Charging', _formatBool(dev['isCharging'])),
            _item('Battery Status', dev['batteryStatus']),
            _item('Battery Health', dev['batteryHealth']),
            _item(
              'Battery Temp',
              dev['batteryTemperatureCelsius'] != null
                  ? '${(dev['batteryTemperatureCelsius'] as num).toStringAsFixed(1)} °C'
                  : 'null',
            ),
            _item(
              'Battery Voltage',
              dev['batteryVoltageMv'] != null
                  ? '${dev['batteryVoltageMv']} mV'
                  : 'null',
            ),
            _item('Power Save Mode', _formatBool(dev['powerSaveMode'])),
            _item('Device Idle (Doze) Mode', _formatBool(dev['deviceIdleMode'])),
            _item('System Uptime', _formatUptime(dev['uptimeMs'])),
            _item('Timezone', dev['timezone']),
            _item('Locale', dev['locale']),
          ],
        ),
        const SizedBox(height: 12),

        // 2. Application Data
        _buildSectionCard(
          title: 'Application Identity & Metadata',
          icon: Icons.apps,
          color: Colors.purpleAccent,
          items: [
            _item('Application Name', app['appName']),
            _item('Package Name', app['packageName']),
            _item('Linux UID', app['uid']),
            _item('Target SDK Version', app['targetSdkVersion']),
            _item('Min SDK Version', app['minSdkVersion']),
            _item('Version Name', app['versionName']),
            _item('Version Code', app['versionCode']),
            _item('First Install Time', _formatEpoch(app['firstInstallTime'])),
            _item('Last Update Time', _formatEpoch(app['lastUpdateTime'])),
            _item('Installer Package', app['installerPackage']),
            _item('System Partition App', _formatBool(app['isSystemApp'])),
            _item('Package Enabled', _formatBool(app['isEnabled'])),
          ],
        ),
        const SizedBox(height: 12),

        // 3. Sensor & Privacy State
        _buildSectionCard(
          title: 'Sensor & Privacy State',
          icon: Icons.privacy_tip,
          color: Colors.amberAccent,
          items: [
            _item(
              'Camera Hardware In Use',
              _formatBool(sensor['cameraHardwareInUse']),
              statusBadge: sensor['cameraHardwareInUse'] == true
                  ? 'IN_USE'
                  : 'IDLE',
              badgeColor: sensor['cameraHardwareInUse'] == true
                  ? Colors.redAccent
                  : Colors.greenAccent,
            ),
            _item('Camera Unavailable', _formatBool(sensor['cameraUnavailable'])),
            _item('Unavailable Cameras Count', sensor['unavailableCamerasCount']),
            _item(
              'Microphone Hardware In Use',
              _formatBool(sensor['microphoneHardwareInUse']),
              statusBadge: sensor['microphoneHardwareInUse'] == true
                  ? 'RECORDING'
                  : 'IDLE',
              badgeColor: sensor['microphoneHardwareInUse'] == true
                  ? Colors.amberAccent
                  : Colors.greenAccent,
            ),
            _item('Active Audio Recordings Count', sensor['activeAudioRecordingsCount']),
            _item('Microphone Muted', _formatBool(sensor['isMicrophoneMuted'])),
            _item('Audio Mode', sensor['audioMode']),
            _item('Attribution Scope', sensor['attributionScope']),
            _item(
              'Sensor Availability',
              sensor['sensorAvailability'],
              statusBadge: sensor['sensorAvailability'],
              badgeColor: _getStatusColor(sensor['sensorAvailability']?.toString() ?? ''),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 4. Permissions & Capabilities
        _buildSectionCard(
          title: 'Permissions & Capabilities',
          icon: Icons.security,
          color: Colors.tealAccent,
          items: [
            _item(
              'Requested Permissions Count',
              (app['requestedPermissions'] as List?)?.length ?? 0,
            ),
            _item(
              'Granted Permissions Count',
              (app['grantedPermissions'] as List?)?.length ?? 0,
            ),
            _item(
              'Denied Permissions Count',
              (app['deniedPermissions'] as List?)?.length ?? 0,
            ),
            _item(
              'Dangerous Granted Count',
              (app['dangerousGrantedPermissions'] as List?)?.length ?? 0,
            ),
            _item(
              'Dangerous Requested Count',
              (app['dangerousRequestedPermissions'] as List?)?.length ?? 0,
            ),
            _item('SYSTEM_ALERT_WINDOW (Overlay)', _formatBool(app['hasOverlayOp'])),
            _item('PACKAGE_USAGE_STATS Access', _formatBool(app['hasUsageAccessOp'])),
          ],
          customFooter: _buildPermissionsList(app),
        ),
        const SizedBox(height: 12),

        // 5. Usage & Foreground Dynamics
        _buildSectionCard(
          title: 'Usage & Foreground Dynamics',
          icon: Icons.history_toggle_off,
          color: Colors.orangeAccent,
          items: [
            _item(
              'Usage Access Granted',
              _formatBool(usage['usageAccessGranted']),
            ),
            _item(
              'Usage Availability',
              usage['availability'] ?? app['usageAvailability'],
              statusBadge: (usage['availability'] ?? app['usageAvailability'])?.toString(),
              badgeColor: _getStatusColor(
                  (usage['availability'] ?? app['usageAvailability'])?.toString() ?? ''),
            ),
            _item(
              'Foreground Duration (24h)',
              app['foregroundDurationMs'] != null
                  ? '${app['foregroundDurationMs']} ms (${((app['foregroundDurationMs'] as num) / 60000.0).toStringAsFixed(1)} min)'
                  : 'null',
            ),
            _item(
              'Foreground Transitions (24h)',
              app['foregroundTransitionCount'],
            ),
            _item(
              'Currently In Foreground',
              _formatBool(app['isCurrentlyForeground']),
              statusBadge: app['isCurrentlyForeground'] == true
                  ? 'FOREGROUND'
                  : 'BACKGROUND',
              badgeColor: app['isCurrentlyForeground'] == true
                  ? Colors.greenAccent
                  : Colors.grey,
            ),
            _item('Recently Used Heuristic (<5m)', _formatBool(app['isRecentlyUsedDerived'])),
            _item('Current Foreground Package', usage['currentForegroundApp']),
          ],
        ),
        const SizedBox(height: 12),

        // 6. Network Telemetry
        _buildSectionCard(
          title: 'Network Telemetry',
          icon: Icons.network_check,
          color: Colors.cyanAccent,
          items: [
            _item('Network Connected', _formatBool(net['isConnected'])),
            _item('Transport Type', net['transport']),
            _item('Metered Connection', _formatBool(net['isMetered'])),
            _item('VPN Active', _formatBool(net['vpnActive'])),
            _item('Downstream Bandwidth', '${net['downstreamBandwidthKbps']} Kbps'),
            _item('Upstream Bandwidth', '${net['upstreamBandwidthKbps']} Kbps'),
            _item(
              'TrafficStats Availability',
              net['trafficStatsAvailability'],
              statusBadge: net['trafficStatsAvailability']?.toString(),
              badgeColor: _getStatusColor(net['trafficStatsAvailability']?.toString() ?? ''),
            ),
            _item(
              'App Tx Bytes (24h)',
              app['uploadBytes'] != null ? _formatBytes(app['uploadBytes']) : 'null',
            ),
            _item(
              'App Rx Bytes (24h)',
              app['downloadBytes'] != null ? _formatBytes(app['downloadBytes']) : 'null',
            ),
            _item(
              'App Network Usage Status',
              app['networkUsageAvailability'],
              statusBadge: app['networkUsageAvailability']?.toString(),
              badgeColor: _getStatusColor(app['networkUsageAvailability']?.toString() ?? ''),
            ),
            _item('Device Total Tx', _formatBytes(net['deviceTotalTxBytes'])),
            _item('Device Total Rx', _formatBytes(net['deviceTotalRxBytes'])),
            _item('Device Mobile Tx', _formatBytes(net['deviceMobileTxBytes'])),
            _item('Device Mobile Rx', _formatBytes(net['deviceMobileRxBytes'])),
          ],
        ),
        const SizedBox(height: 12),

        // 7. Security Context
        _buildSectionCard(
          title: 'Security Context & Integrity',
          icon: Icons.verified_user_outlined,
          color: Colors.lightGreenAccent,
          items: [
            _item('Developer Options Enabled', _formatBool(sec['developerOptionsEnabled'])),
            _item('ADB Enabled', _formatBool(sec['adbEnabled'])),
            _item('Accessibility Services Enabled', _formatBool(sec['accessibilityEnabled'])),
            _item('Can Draw Overlays', _formatBool(sec['selfCanDrawOverlays'])),
            _item('Ignoring Battery Optimization', _formatBool(sec['selfIsIgnoringBatteryOptimizations'])),
            _item('Root Detection Method', sec['rootDetection']?['rootDetectionMethod'] ?? sec['rootDetectionMethod']),
            _item('Root Heuristic Detected', _formatBool(sec['rootDetection']?['isRootedHeuristic'] ?? sec['isRootedHeuristic'])),
            _item('Root Confidence', sec['rootDetection']?['confidence'] ?? sec['rootConfidence']),
          ],
        ),
        const SizedBox(height: 12),

        // 8. Missingness & Availability Diagnostics
        _buildMissingnessAvailabilityCard(r, raw),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==========================================================
  // TAB 2: 32 DETERMINISTIC FEATURES TABLE
  // ==========================================================
  Widget _buildFeaturesTab() {
    final r = widget.record;
    final values = r.featureVector.values;

    return ListView.builder(
      padding: const EdgeInsets.all(14.0),
      itemCount: values.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Card(
            color: Colors.deepPurple.shade900.withValues(alpha: 0.3),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.cyanAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Feature Vector Schema ${r.featureVector.schemaVersion} (${values.length} features)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final f = values[index - 1];
        final statusColor = _getStatusColor(f.status.toFormattedString());

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${f.featureIndex}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.featureName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        border: Border.all(color: statusColor, width: 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        f.status.toFormattedString(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Type: ${f.dataType.name.toUpperCase()}',
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                    Text(
                      'Numeric: ${f.numericValue != null ? f.numericValue.toString() : "null"}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: f.numericValue != null ? Colors.cyanAccent : Colors.white38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Raw Value: ${f.rawValue != null ? f.rawValue.toString() : "null (Missing)"}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // TAB 3: RAW JSON VIEW
  // ==========================================================
  Widget _buildRawJsonTab() {
    final prettyJson =
        const JsonEncoder.withIndent('  ').convert(widget.record.toJson());

    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF101018),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Persisted JSON Representation',
                style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                label: Text(_copied ? 'Copied' : 'Copy JSON'),
                onPressed: _copyRawJson,
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                prettyJson,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF80CBC4),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // HELPER WIDGETS
  // ==========================================================
  Widget _buildRecordHeaderCard() {
    final r = widget.record;
    final healthColor = _getStatusColor(r.collectorHealthStatus);

    return Card(
      color: Colors.deepPurple.shade900.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.packageName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Record ID: ${r.recordId}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white60,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: healthColor.withValues(alpha: 0.2),
                    border: Border.all(color: healthColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    r.collectorHealthStatus,
                    style: TextStyle(
                      color: healthColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildMetaLine('Session ID', r.sessionId ?? 'unassigned'),
            _buildMetaLine('Device Hash', r.deviceIdHash),
            _buildMetaLine('Timestamp', r.timestamp),
            if (r.label != null) _buildMetaLine('Ground Truth Label', r.label!),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingnessAvailabilityCard(DatasetRecord r, Map<String, dynamic> raw) {
    final values = r.featureVector.values;
    final counts = <String, int>{
      'VALID': 0,
      'ZERO_REPORTED': 0,
      'RESTRICTED': 0,
      'DENIED': 0,
      'UNAVAILABLE': 0,
      'ERROR': 0,
      'UNKNOWN': 0,
    };

    for (final f in values) {
      final s = f.status.toFormattedString();
      counts[s] = (counts[s] ?? 0) + 1;
    }

    final app = Map<String, dynamic>.from(raw['app'] ?? {});
    final net = Map<String, dynamic>.from(raw['network'] ?? {});
    final sensor = Map<String, dynamic>.from(raw['sensorTelemetry'] ?? {});
    final usage = Map<String, dynamic>.from(raw['usageSummary'] ?? {});

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.rule_folder_outlined, color: Colors.pinkAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  'Missingness & Availability Diagnostics',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            const Text(
              'Subsystem Health & Availability:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildAvailabilityBadge('Sensor Privacy', sensor['sensorAvailability']?.toString() ?? 'UNKNOWN'),
                _buildAvailabilityBadge('Usage Stats', (usage['availability'] ?? app['usageAvailability'])?.toString() ?? 'UNKNOWN'),
                _buildAvailabilityBadge('TrafficStats', net['trafficStatsAvailability']?.toString() ?? 'UNKNOWN'),
                _buildAvailabilityBadge('App Network Usage', app['networkUsageAvailability']?.toString() ?? 'UNKNOWN'),
                _buildAvailabilityBadge('Collector Overall', r.collectorHealthStatus),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '32-Feature Availability Breakdown:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: counts.entries.map((e) {
                final color = _getStatusColor(e.key);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${e.key}: ',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                      ),
                      Text(
                        '${e.value}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.info_outline, size: 14, color: Colors.white60),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Strict Invariant: Missing values are never synthesized or converted to fake defaults. ZERO_REPORTED indicates the OS genuinely reported 0 bytes or 0ms, while RESTRICTED or DENIED indicates missing telemetry due to OS privacy boundaries.',
                      style: TextStyle(fontSize: 10, color: Colors.white60, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityBadge(String subsystem, String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$subsystem: ',
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
          Text(
            status,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> items,
    Widget? customFooter,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            ...items.map((item) {
              final label = item['label']?.toString() ?? '';
              final val = item['value']?.toString() ?? 'null';
              final badge = item['badge']?.toString();
              final badgeColor = item['badgeColor'] as Color?;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        label,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              val,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: val == 'null' ? Colors.white38 : Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: (badgeColor ?? Colors.cyanAccent).withValues(alpha: 0.2),
                                border: Border.all(
                                  color: badgeColor ?? Colors.cyanAccent,
                                  width: 0.8,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: badgeColor ?? Colors.cyanAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (customFooter != null) ...[
              const Divider(height: 16),
              customFooter,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsList(Map<String, dynamic> app) {
    final dangerousGranted = (app['dangerousGrantedPermissions'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final dangerousRequested = (app['dangerousRequestedPermissions'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dangerous Granted Permissions:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 6),
        if (dangerousGranted.isEmpty)
          const Text('None', style: TextStyle(fontSize: 11, color: Colors.white38))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: dangerousGranted
                .map((p) => Chip(
                      label: Text(p, style: const TextStyle(fontSize: 10)),
                      backgroundColor: Colors.red.shade900.withValues(alpha: 0.4),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        const SizedBox(height: 10),
        const Text(
          'Dangerous Requested Manifest Permissions:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 6),
        if (dangerousRequested.isEmpty)
          const Text('None', style: TextStyle(fontSize: 11, color: Colors.white38))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: dangerousRequested
                .map((p) => Chip(
                      label: Text(p, style: const TextStyle(fontSize: 10)),
                      backgroundColor: Colors.white10,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
      ],
    );
  }

  Map<String, dynamic> _item(
    String label,
    dynamic value, {
    String? statusBadge,
    Color? badgeColor,
  }) {
    return {
      'label': label,
      'value': value != null ? value.toString() : 'null',
      'badge': statusBadge,
      'badgeColor': badgeColor,
    };
  }

  Widget _buildMetaLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }

  String _formatBool(dynamic v) {
    if (v == null) return 'null';
    if (v is bool) return v ? 'true' : 'false';
    return v.toString();
  }

  String _formatBytes(dynamic v) {
    if (v == null) return 'null';
    final num b = v is num ? v : (num.tryParse(v.toString()) ?? 0);
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatUptime(dynamic v) {
    if (v == null) return 'null';
    final num ms = v is num ? v : (num.tryParse(v.toString()) ?? 0);
    final sec = ms ~/ 1000;
    final min = sec ~/ 60;
    final hrs = min ~/ 60;
    if (hrs > 0) return '${hrs}h ${min % 60}m';
    if (min > 0) return '${min}m ${sec % 60}s';
    return '${sec}s';
  }

  String _formatEpoch(dynamic v) {
    if (v == null || v == 0) return 'null / 0';
    final num ms = v is num ? v : (num.tryParse(v.toString()) ?? 0);
    if (ms <= 0) return '0';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
      return dt.toIso8601String().substring(0, 19).replaceAll('T', ' ');
    } catch (_) {
      return ms.toString();
    }
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
