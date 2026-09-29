import 'package:flutter/material.dart';
import '../../models/privacy_event.dart';
import '../../models/telemetry_diagnostics.dart';
import '../../telemetry/collectors/android_collector.dart';

/// Development diagnostics screen to inspect live real-world telemetry fields,
/// their source Android APIs, scope, collection type, and availability status.
class TelemetryDiagnosticsScreen extends StatefulWidget {
  const TelemetryDiagnosticsScreen({super.key});

  @override
  State<TelemetryDiagnosticsScreen> createState() =>
      _TelemetryDiagnosticsScreenState();
}

class _TelemetryDiagnosticsScreenState
    extends State<TelemetryDiagnosticsScreen> {
  final AndroidCollector _collector = AndroidCollector();
  PrivacyEvent? _latestEvent;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchTelemetry();
  }

  Future<void> _fetchTelemetry() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final raw = await _collector.collectTelemetry();
      if (raw.containsKey("error") && raw["error"] != null) {
        setState(() {
          _errorMessage = raw["error"].toString();
          _isLoading = false;
        });
        return;
      }
      final event = PrivacyEvent.fromMap(raw);
      setState(() {
        _latestEvent = event;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Telemetry Diagnostics"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Telemetry",
            onPressed: _isLoading ? null : _fetchTelemetry,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _latestEvent == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                "Telemetry Error",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchTelemetry,
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    final event = _latestEvent;
    if (event == null) {
      return const Center(child: Text("No telemetry available"));
    }

    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        _buildSnapshotHeader(event),
        const SizedBox(height: 12),
        _buildTelemetryHealthCard(event.telemetryHealth),
        const SizedBox(height: 12),
        _buildDiagnosticsTable(event.diagnostics),
        const SizedBox(height: 16),
        _buildDeviceContextCard(event.deviceContext),
        const SizedBox(height: 12),
        _buildSecurityContextCard(event.securityContext),
        const SizedBox(height: 12),
        _buildNetworkContextCard(event.network),
        const SizedBox(height: 12),
        _buildSensorPrivacyCard(event.sensorTelemetry),
        const SizedBox(height: 12),
        _buildUsageSummaryCard(event.usageSummary),
      ],
    );
  }

  Widget _buildSnapshotHeader(PrivacyEvent event) {
    return Card(
      color: Colors.deepPurple.shade900.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Layer 1: Mobile Device Layer Snapshot",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Timestamp: ${event.timestamp}",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            Text(
              "Monitored Apps: ${event.apps.length}",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryHealthCard(TelemetryHealth health) {
    Widget buildHealthRow(String title, CollectorHealth ch) {
      final isValid = ch.status == "VALID";
      final isRestricted = ch.status == "RESTRICTED";
      final color = isValid ? Colors.green : (isRestricted ? Colors.orange : Colors.red);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color, width: 1),
              ),
              child: Text(ch.status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(
                ch.message,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.health_and_safety, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Telemetry Collectors Health",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 16),
            buildHealthRow("Permissions", health.permissions),
            buildHealthRow("Usage Stats", health.usage),
            buildHealthRow("Network Stats", health.network),
            buildHealthRow("Device Security", health.security),
            buildHealthRow("Sensor Privacy", health.sensors),
            buildHealthRow("Device Context", health.deviceContext),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsTable(List<TelemetryDiagnosticItem> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Platform Verification Matrix",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowHeight: 40,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 64,
                columns: const [
                  DataColumn(label: Text("Field")),
                  DataColumn(label: Text("Value")),
                  DataColumn(label: Text("Source API")),
                  DataColumn(label: Text("Scope")),
                  DataColumn(label: Text("Collection Type")),
                  DataColumn(label: Text("Availability")),
                ],
                rows: items.map((item) {
                  final isAvailable = item.availability == "AVAILABLE";
                  final isRestricted = item.availability == "RESTRICTED";
                  final statusColor = isAvailable
                      ? Colors.green
                      : (isRestricted ? Colors.orange : Colors.red);

                  return DataRow(
                    cells: [
                      DataCell(Text(item.field,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(item.value,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataCell(Text(item.sourceApi,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                      DataCell(Chip(
                        label: Text(item.scope, style: const TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )),
                      DataCell(Text(item.collectionType,
                          style: const TextStyle(fontSize: 11))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: statusColor, width: 1),
                          ),
                          child: Text(
                            item.availability,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceContextCard(DeviceContext ctx) {
    return Card(
      child: ExpansionTile(
        title: const Text("Device Context (Hardware & State)"),
        subtitle: Text(
          "${ctx.manufacturer} ${ctx.model} • Android ${ctx.androidVersion} (API ${ctx.sdkInt})",
          style: const TextStyle(fontSize: 12),
        ),
        leading: const Icon(Icons.phone_android, color: Colors.blueAccent),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _buildInfoRow("Manufacturer / Model", "${ctx.manufacturer} / ${ctx.model}"),
                _buildInfoRow("Brand / Device / Board", "${ctx.brand} / ${ctx.device} / ${ctx.board}"),
                _buildInfoRow("Hardware / SDK", "${ctx.hardware} / API ${ctx.sdkInt}"),
                const Divider(),
                _buildInfoRow("Screen Interactive (On)", ctx.screenOn?.toString() ?? "Unknown"),
                _buildInfoRow("Screen Locked", ctx.screenLocked?.toString() ?? "Unknown"),
                _buildInfoRow("Device Secure (PIN/Bio)", ctx.isDeviceSecure?.toString() ?? "Unknown"),
                const Divider(),
                _buildInfoRow("Battery Level", ctx.batteryPercent != null ? "${ctx.batteryPercent}%" : "Unknown"),
                _buildInfoRow("Battery Status", ctx.batteryStatus),
                _buildInfoRow("Battery Plugged", ctx.batteryPlugged),
                _buildInfoRow("Battery Health", ctx.batteryHealth),
                _buildInfoRow("Battery Temperature", ctx.batteryTemperatureCelsius != null ? "${ctx.batteryTemperatureCelsius!.toStringAsFixed(1)} °C" : "Unknown"),
                _buildInfoRow("Battery Voltage", ctx.batteryVoltageMv != null ? "${ctx.batteryVoltageMv} mV" : "Unknown"),
                const Divider(),
                _buildInfoRow("Power Save Mode", ctx.powerSaveMode?.toString() ?? "Unknown"),
                _buildInfoRow("Device Idle Mode", ctx.deviceIdleMode?.toString() ?? "Unknown"),
                _buildInfoRow("Uptime", "${(ctx.uptimeMs / 1000 / 60).toStringAsFixed(1)} minutes"),
                _buildInfoRow("Timezone / Locale", "${ctx.timezone} / ${ctx.locale}"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityContextCard(SecurityContext sec) {
    return Card(
      child: ExpansionTile(
        title: const Text("Security Context"),
        subtitle: Text(
          "Root Heuristic: ${sec.rootConfidence} • Overlay: ${sec.selfCanDrawOverlays} • Accessibility: ${sec.accessibilityEnabled}",
          style: const TextStyle(fontSize: 12),
        ),
        leading: const Icon(Icons.shield, color: Colors.amberAccent),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _buildInfoRow("Host App Overlay Capability", sec.selfCanDrawOverlays?.toString() ?? "Unknown"),
                _buildInfoRow("Host App Doze Exemption", sec.selfIsIgnoringBatteryOptimizations?.toString() ?? "Unknown"),
                _buildInfoRow("Host App Install Request", sec.selfCanRequestPackageInstalls?.toString() ?? "Unknown"),
                const Divider(),
                _buildInfoRow("Developer Options Enabled", sec.developerOptionsEnabled?.toString() ?? "Unknown"),
                _buildInfoRow("ADB / USB Debugging", sec.adbEnabled?.toString() ?? "Unknown"),
                _buildInfoRow("Accessibility Services Active", sec.accessibilityEnabled?.toString() ?? "Unknown"),
                _buildInfoRow(
                  "Active Accessibility Services",
                  sec.enabledAccessibilityServices == null || sec.enabledAccessibilityServices!.isEmpty
                      ? "None"
                      : sec.enabledAccessibilityServices!.join("\n"),
                ),
                const Divider(),
                _buildInfoRow("Root Heuristic Result", sec.isRootedHeuristic ? "POTENTIALLY ROOTED" : "NO INDICATORS FOUND"),
                _buildInfoRow("Root Confidence", sec.rootConfidence),
                _buildInfoRow(
                  "Matched Root Indicators",
                  sec.rootIndicators.isEmpty ? "None" : sec.rootIndicators.join(", "),
                ),
                if (sec.rootDisclaimer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(
                      sec.rootDisclaimer,
                      style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.white60),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkContextCard(NetworkTelemetry net) {
    return Card(
      child: ExpansionTile(
        title: const Text("Network Telemetry"),
        subtitle: Text(
          "Transport: ${net.transport} • Connected: ${net.isConnected} • VPN: ${net.vpnActive}",
          style: const TextStyle(fontSize: 12),
        ),
        leading: const Icon(Icons.wifi, color: Colors.tealAccent),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _buildInfoRow("Is Connected", net.isConnected.toString()),
                _buildInfoRow("Transport Type", net.transport),
                _buildInfoRow("Is Metered", net.isMetered.toString()),
                _buildInfoRow("VPN Transport Active", net.vpnActive.toString()),
                _buildInfoRow("Downstream Bandwidth", "${net.downstreamBandwidthKbps} Kbps"),
                _buildInfoRow("Upstream Bandwidth", "${net.upstreamBandwidthKbps} Kbps"),
                const Divider(),
                _buildInfoRow("Device Total TX Bytes", net.deviceTotalTxBytes?.toString() ?? "Unsupported"),
                _buildInfoRow("Device Total RX Bytes", net.deviceTotalRxBytes?.toString() ?? "Unsupported"),
                _buildInfoRow("Device Mobile TX Bytes", net.deviceMobileTxBytes?.toString() ?? "Unsupported"),
                _buildInfoRow("Device Mobile RX Bytes", net.deviceMobileRxBytes?.toString() ?? "Unsupported"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorPrivacyCard(SensorPrivacyTelemetry sensor) {
    return Card(
      child: ExpansionTile(
        title: const Text("Sensor Privacy Telemetry"),
        subtitle: Text(
          "Unavailable Camera: ${sensor.cameraUnavailable} • Mic in Use: ${sensor.microphoneHardwareInUse}",
          style: const TextStyle(fontSize: 12),
        ),
        leading: const Icon(Icons.videocam, color: Colors.purpleAccent),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _buildInfoRow("Camera Unavailable", sensor.cameraUnavailable?.toString() ?? "Unknown"),
                _buildInfoRow("Unavailable Camera Count", sensor.unavailableCamerasCount?.toString() ?? "Unknown"),
                _buildInfoRow("Microphone In Use", sensor.microphoneHardwareInUse?.toString() ?? "Unknown"),
                _buildInfoRow("Active Audio Recordings", sensor.activeAudioRecordingsCount?.toString() ?? "Unknown"),
                _buildInfoRow("Microphone Muted", sensor.isMicrophoneMuted?.toString() ?? "Unknown"),
                _buildInfoRow("Audio Mode", sensor.audioMode),
                _buildInfoRow("Attribution Scope", sensor.attributionScope),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageSummaryCard(UsageSummary usage) {
    return Card(
      child: ExpansionTile(
        title: const Text("Usage Stats Summary"),
        subtitle: Text(
          "Access Granted: ${usage.usageAccessGranted} • Total Transitions: ${usage.totalForegroundTransitions ?? 0}",
          style: const TextStyle(fontSize: 12),
        ),
        leading: const Icon(Icons.bar_chart, color: Colors.orangeAccent),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _buildInfoRow("Usage Access Granted", usage.usageAccessGranted.toString()),
                _buildInfoRow("Availability Status", usage.availability),
                if (usage.reason.isNotEmpty)
                  _buildInfoRow("Status Reason", usage.reason),
                _buildInfoRow("Current Observed Foreground App", usage.currentForegroundApp ?? "None"),
                _buildInfoRow(
                  "Total Foreground Duration",
                  usage.totalForegroundDurationMs != null
                      ? "${(usage.totalForegroundDurationMs! / 1000 / 60).toStringAsFixed(1)} minutes"
                      : "Unknown",
                ),
                _buildInfoRow("Total Foreground Transitions", usage.totalForegroundTransitions?.toString() ?? "Unknown"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
