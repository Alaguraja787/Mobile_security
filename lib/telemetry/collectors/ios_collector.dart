/// iOS Collector stub.
/// Real telemetry collection for iOS would require Apple NetworkExtension, ScreenTime, and DeviceCheck frameworks.
class IosCollector {
  Future<Map<String, dynamic>> collectTelemetry() async {
    return {
      "platform": "iOS",
      "supported": false,
      "message": "iOS native telemetry collection requires iOS target configuration",
      "timestamp": DateTime.now().toIso8601String(),
    };
  }
}
