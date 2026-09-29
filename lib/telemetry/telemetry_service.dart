import 'dart:async';
import 'dart:developer' as developer;

import '../models/privacy_event.dart';
import '../phase2/dataset/dataset_collector.dart';
import 'collectors/android_collector.dart';

/// Authoritative Telemetry Service for Privacy Sentinel AI.
/// 
/// Architecture:
/// - Unifies EventChannel real-time native push events with controlled interval polling.
/// - Single authoritative source of truth for UI, Agent, and Diagnostics consumers.
/// - Bridges live telemetry snapshots asynchronously into [DatasetCollector] for ML dataset persistence.
class TelemetryService {
  final AndroidCollector collector = AndroidCollector();
  DatasetCollector? datasetCollector;

  StreamController<PrivacyEvent>? _controller;
  StreamSubscription<Map<String, dynamic>>? _nativeStreamSub;
  Timer? _timer;
  bool _isRunning = false;
  PrivacyEvent? _latestEvent;

  TelemetryService({this.datasetCollector});

  PrivacyEvent? get latestEvent => _latestEvent;

  Stream<PrivacyEvent> get stream {
    _ensureController();
    return _controller!.stream;
  }

  void _ensureController() {
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<PrivacyEvent>.broadcast();
    }
  }

  /// Attaches or replaces active DatasetCollector
  void attachDatasetCollector(DatasetCollector collector) {
    datasetCollector = collector;
  }

  /// Detaches DatasetCollector
  void detachDatasetCollector() {
    datasetCollector = null;
  }

  void start({Duration interval = const Duration(seconds: 15)}) {
    if (_isRunning) return;
    _isRunning = true;
    _ensureController();

    // Subscribe to real-time native EventChannel push stream
    try {
      _nativeStreamSub = collector.telemetryStream.listen((data) {
        if (data.isNotEmpty) {
          final event = PrivacyEvent.fromMap(data);
          _latestEvent = event;
          if (_controller != null && !_controller!.isClosed) {
            _controller!.add(event);
          }
          _dispatchToDatasetCollector(event);
        }
      }, onError: (e) {
        developer.log('Native telemetry stream error: $e',
            name: 'TelemetryService');
      });
    } catch (e) {
      developer.log('Failed to subscribe to native telemetry stream: $e',
          name: 'TelemetryService');
    }

    // Trigger immediate initial snapshot fetch
    _pollTelemetry();

    // Periodic check to ensure continuous freshness
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _pollTelemetry());
  }

  Future<PrivacyEvent?> _pollTelemetry({bool forceRefresh = false}) async {
    try {
      final data = await collector.collectTelemetry(forceRefresh: forceRefresh);
      final event = PrivacyEvent.fromMap(data);
      _latestEvent = event;
      if (_controller != null && !_controller!.isClosed) {
        _controller!.add(event);
      }
      _dispatchToDatasetCollector(event);
      return event;
    } catch (e) {
      developer.log('Telemetry polling note: $e', name: 'TelemetryService');
      return null;
    }
  }

  void _dispatchToDatasetCollector(PrivacyEvent event) {
    if (datasetCollector == null) return;
    try {
      datasetCollector!.captureEvent(event);
    } catch (e) {
      developer.log('Dataset collector dispatch isolated error: $e',
          name: 'TelemetryService');
    }
  }

  Future<PrivacyEvent?> refreshOnce({bool forceRefresh = true}) async {
    return await _pollTelemetry(forceRefresh: forceRefresh);
  }

  void emit(PrivacyEvent event) {
    _latestEvent = event;
    _ensureController();
    if (_controller != null && !_controller!.isClosed) {
      _controller!.add(event);
    }
    _dispatchToDatasetCollector(event);
  }

  Future<bool> startForegroundMonitoring() async {
    return await collector.startForegroundService();
  }

  Future<bool> stopForegroundMonitoring() async {
    return await collector.stopForegroundService();
  }

  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    _nativeStreamSub?.cancel();
    _nativeStreamSub = null;
    _controller?.close();
    _controller = null;
  }
}