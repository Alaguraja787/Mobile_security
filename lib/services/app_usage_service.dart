import '../telemetry/collectors/android_collector.dart';

/// Legacy service delegating to [AndroidCollector] to eliminate MethodChannel duplication.
class AppUsageService {
  final AndroidCollector _collector = AndroidCollector();

  Future<Map<String, dynamic>> getTelemetry() async {
    return await _collector.collectTelemetry();
  }
}