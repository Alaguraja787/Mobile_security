// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sensor_access_event.dart';
import '../telemetry/collectors/android_collector.dart';

/// Service responsible for managing real-time camera and microphone sensor access events,
/// tracking active sensor states, and maintaining verified recent sensor access history.
///
/// Design Guarantees:
/// - Single source of truth for both user notifications and Dashboard.
/// - Real device observations only (zero synthetic/fake events).
/// - Never infers package identity from sensor type or foreground state alone.
/// - Strictly bounded in-memory recent event history (default max 500).
/// - Dynamic relative time & active duration calculation strictly from real timestamps.
/// - Reactive ChangeNotifier enabling live Dashboard updates without manual reload.
/// - Persistent recent history across app rebuilds, navigation, and restarts.
class SensorAccessService extends ChangeNotifier {
  static const int defaultMaxRecentEvents = 500;

  static SensorAccessService? _sharedInstance;

  /// Returns the shared application-level singleton instance.
  static SensorAccessService get shared {
    _sharedInstance ??= SensorAccessService();
    return _sharedInstance!;
  }

  /// Resets the shared instance (for unit testing).
  @visibleForTesting
  static void resetSharedInstanceForTesting() {
    _sharedInstance?.dispose();
    _sharedInstance = null;
  }

  final AndroidCollector _collector;
  final int maxRecentEvents;

  final List<SensorAccessEvent> _recentEvents = [];
  final Map<String, SensorAccessEvent> _activeSessions = {};
  final Map<String, Set<SensorType>> _blockedApps = {};

  StreamSubscription<Map<String, dynamic>>? _nativeSub;
  StreamController<SensorAccessEvent>? _eventStreamController;
  bool _isListening = false;

  SensorAccessService({
    AndroidCollector? collector,
    this.maxRecentEvents = defaultMaxRecentEvents,
  }) : _collector = collector ?? AndroidCollector() {
    _loadPersistedEvents();
  }

  /// Unmodifiable view of all recent observed sensor access events (newest first).
  List<SensorAccessEvent> get recentEvents => List.unmodifiable(_recentEvents);

  /// Unmodifiable view of only app-attributed, verified recent sensor access events.
  List<SensorAccessEvent> get verifiedRecentEvents => List.unmodifiable(
      _recentEvents.where((e) => e.isAppAttributed).toList());

  /// Unmodifiable view of all events that occurred while the phone screen was LOCKED in background.
  List<SensorAccessEvent> get lockedScreenEvents => List.unmodifiable(
      _recentEvents.where((e) => e.isScreenLocked).toList());

  /// Unmodifiable view of photo, video, and file access events.
  List<SensorAccessEvent> get mediaAccessEvents => List.unmodifiable(
      _recentEvents.where((e) =>
          e.sensorType == SensorType.photos ||
          e.sensorType == SensorType.videos ||
          e.sensorType == SensorType.files ||
          e.sensorType == SensorType.audioFiles).toList());

  /// Snapshot of currently active sensor events (prioritizing verified app sessions).
  Map<SensorType, SensorAccessEvent?> get activeSensors {
    final Map<SensorType, SensorAccessEvent?> map = {
      SensorType.camera: null,
      SensorType.microphone: null,
      SensorType.location: null,
      SensorType.otherSupported: null,
    };
    for (final session in _activeSessions.values) {
      final existing = map[session.sensorType];
      if (existing == null || (!existing.isAppAttributed && session.isAppAttributed)) {
        map[session.sensorType] = session;
      }
    }
    return Map.unmodifiable(map);
  }

  /// List of all currently active sessions across sensors and applications.
  List<SensorAccessEvent> get activeSessions =>
      List.unmodifiable(_activeSessions.values);

  /// Checks if a specific sensor is currently active.
  bool isSensorActive(SensorType type) =>
      _activeSessions.values.any((e) => e.sensorType == type);

  /// Checks if a package is currently marked as blocked for a sensor.
  bool isAppBlocked(String packageName, SensorType sensor) =>
      _blockedApps[packageName]?.contains(sensor) ?? false;

  /// Unmodifiable map of packages to their set of blocked sensors.
  Map<String, Set<SensorType>> get blockedApps => Map.unmodifiable(_blockedApps);

  /// Retrieves the active event for a specific sensor type, or null if idle.
  SensorAccessEvent? getActiveEvent(SensorType type) {
    for (final session in _activeSessions.values) {
      if (session.sensorType == type) return session;
    }
    return null;
  }

  /// Stream of incoming deserialized SensorAccessEvents.
  Stream<SensorAccessEvent> get eventStream {
    _ensureController();
    return _eventStreamController!.stream;
  }

  void _ensureController() {
    if (_eventStreamController == null || _eventStreamController!.isClosed) {
      _eventStreamController = StreamController<SensorAccessEvent>.broadcast();
    }
  }

  /// Begins listening to the native Android sensor access event stream.
  void start() {
    if (_isListening) return;
    _isListening = true;
    _ensureController();

    try {
      _nativeSub = _collector.sensorAccessStream.listen(
        (data) {
          if (data.isNotEmpty) {
            final event = SensorAccessEvent.fromMap(data);
            processEvent(event);
          }
        },
        onError: (e) {
          developer.log('SensorAccessService stream error: $e',
              name: 'SensorAccessService');
        },
      );
    } catch (e) {
      developer.log('Failed to subscribe to sensor access stream: $e',
              name: 'SensorAccessService');
    }
  }

  String _sessionKeyFor(SensorAccessEvent event) {
    if (event.isAppAttributed && event.packageName != null) {
      if (event.fileName != null) {
        return '${event.sensorType.toJson()}_${event.packageName}_${event.fileName}';
      }
      return '${event.sensorType.toJson()}_${event.packageName}';
    }
    return '${event.sensorType.toJson()}_DEVICE_LEVEL';
  }

  /// Processes an individual event, updating active sensor sessions, history, and notifying listeners.
  void processEvent(SensorAccessEvent event) {
    _ensureController();

    // Deduplication check: prevent duplicate entries from reconnects or rebuilds
    if (event.eventId != null && _recentEvents.any((e) => e.eventId == event.eventId)) {
      print('DUPLICATE_SENSOR_EVENT_SUPPRESSED: eventId=${event.eventId}');
      return;
    }
    if (_recentEvents.isNotEmpty) {
      final first = _recentEvents.first;
      if (first.sensorType == event.sensorType &&
          first.state == event.state &&
          first.packageName == event.packageName &&
          event.timestamp.difference(first.timestamp).inMilliseconds.abs() < 100) {
        print('RAPID_DUPLICATE_SENSOR_EVENT_SUPPRESSED: ${event.sensorType.toJson()}');
        return;
      }
    }

    final sessionKey = _sessionKeyFor(event);
    final deviceLevelKey = '${event.sensorType.toJson()}_DEVICE_LEVEL';

    // Update active sensor sessions and apply event priority / deduplication
    if (event.state == SensorAccessState.started ||
        event.state == SensorAccessState.active) {
      if (event.isAppAttributed) {
        // APP_LEVEL + VERIFIED event arrives:
        // If an unverified DEVICE_LEVEL session exists for this sensor, upgrade it
        if (_activeSessions.containsKey(deviceLevelKey)) {
          print('UPGRADING_DEVICE_LEVEL_SESSION_TO_APP_LEVEL: ${event.sensorType.toJson()} -> ${event.packageName}');
          _activeSessions.remove(deviceLevelKey);
        }
        _activeSessions[sessionKey] = event;

        // Upgrade existing device-level history item rather than creating a duplicate
        final recentDeviceIdx = _recentEvents.indexWhere((e) =>
            e.sensorType == event.sensorType &&
            e.attributionScope == SensorAttributionScope.deviceLevel &&
            (e.state == SensorAccessState.started || e.state == SensorAccessState.active) &&
            event.timestamp.difference(e.timestamp).inSeconds.abs() <= 15);

        if (recentDeviceIdx != -1) {
          print('UPGRADING_HISTORY_ITEM: index=$recentDeviceIdx to ${event.appName ?? event.packageName}');
          _recentEvents[recentDeviceIdx] = event;
        } else {
          _recentEvents.insert(0, event);
        }
      } else if (event.attributionScope == SensorAttributionScope.deviceLevel) {
        // DEVICE_LEVEL event arrives:
        // If an app-attributed verified session is ALREADY active for this sensor,
        // do not overwrite the verified identity or create a duplicate session
        final hasActiveAppSession = _activeSessions.values.any((s) =>
            s.sensorType == event.sensorType && s.isAppAttributed);

        if (hasActiveAppSession) {
          print('SUPPRESSING_GENERIC_DEVICE_LEVEL_DUE_TO_ACTIVE_APP: ${event.sensorType.toJson()}');
          return;
        }

        _activeSessions[sessionKey] = event;
        _recentEvents.insert(0, event);
      } else {
        _activeSessions[sessionKey] = event;
        _recentEvents.insert(0, event);
      }

      // Discrete media/file accesses represent access events rather than perpetual streams
      // Keep visible in Live Privacy Activity for 8s, then smoothly transition to recent history
      if (event.sensorType == SensorType.photos ||
          event.sensorType == SensorType.files ||
          event.sensorType == SensorType.videos ||
          event.sensorType == SensorType.audioFiles) {
        Timer(const Duration(seconds: 8), () {
          if (_activeSessions[sessionKey] == event) {
            _activeSessions.remove(sessionKey);
            notifyListeners();
          }
        });
      }
    } else if (event.state == SensorAccessState.stopped) {
      if (event.packageName != null) {
        _activeSessions.remove(sessionKey);
      } else {
        // Device-level STOPPED confirms sensor hardware is closed; clear all active sessions for this sensor type
        _activeSessions.removeWhere((_, s) => s.sensorType == event.sensorType);
      }
      _recentEvents.insert(0, event);
    }

    print('ACTIVE_SENSOR_UPDATED: sensor=${event.sensorType.toJson()} state=${event.state.toJson()} isActive=${isSensorActive(event.sensorType)} activeCount=${_activeSessions.length}');

    if (_recentEvents.length > maxRecentEvents) {
      _recentEvents.removeRange(maxRecentEvents, _recentEvents.length);
    }

    print('SENSOR_EVENT_STORED: eventId=${event.eventId} sensor=${event.sensorType.toJson()} state=${event.state.toJson()} historyCount=${_recentEvents.length}');

    // Persist event metadata asynchronously
    _persistEvent(event);

    // Broadcast to stream listeners
    if (_eventStreamController != null && !_eventStreamController!.isClosed) {
      _eventStreamController!.add(event);
    }

    // Notify UI subscribers (e.g. Dashboard Live Privacy Activity & Recent Sensor Activity)
    notifyListeners();
  }

  Future<File?> _getHistoryFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/privacy_sentinel_sensor_events.jsonl');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPersistedEvents() async {
    try {
      final file = await _getHistoryFile();
      if (file != null && await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final map = jsonDecode(trimmed);
            if (map is Map) {
              final event = SensorAccessEvent.fromMap(map);
              if (!_recentEvents.any((e) => e.eventId != null && e.eventId == event.eventId)) {
                _recentEvents.add(event);
              }
            }
          } catch (_) {}
        }
        _recentEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (_recentEvents.length > maxRecentEvents) {
          _recentEvents.removeRange(maxRecentEvents, _recentEvents.length);
        }
        notifyListeners();
      }
    } catch (e) {
      developer.log('Load persisted sensor events note: $e', name: 'SensorAccessService');
    }
  }

  Future<void> _persistEvent(SensorAccessEvent event) async {
    try {
      final file = await _getHistoryFile();
      if (file != null) {
        final line = '${jsonEncode(event.toJson())}\n';
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      }
    } catch (e) {
      developer.log('Persist sensor event note: $e', name: 'SensorAccessService');
    }
  }

  /// Queries runtime sensor monitoring capabilities from the Android platform.
  Future<SensorMonitoringCapabilities> getCapabilities() async {
    try {
      final raw = await _collector.getSensorCapabilities();
      if (raw.isNotEmpty && raw['error'] == null) {
        return SensorMonitoringCapabilities.fromMap(raw);
      }
      return SensorMonitoringCapabilities.defaultUnknown();
    } catch (e) {
      developer.log('Failed to fetch sensor capabilities: $e',
          name: 'SensorAccessService');
      return SensorMonitoringCapabilities.defaultUnknown();
    }
  }

  final List<Map<String, dynamic>> _guardianEvidenceLog = [];

  /// Structured verified evidence exposed for Guardian analysis.
  List<Map<String, dynamic>> get guardianEvidenceLog =>
      List.unmodifiable(_guardianEvidenceLog);

  /// Performs lightweight state reconciliation with the native platform without high-frequency polling.
  ///
  /// Clears stale in-memory active sessions if native hardware reports idle.
  /// Synchronizes blocked state against actual Android permission truth.
  /// Never fabricates artificial events.
  Future<void> reconcileWithPlatform() async {
    try {
      final state = await _collector.reconcileSensorState();
      final micCount = (state['activeAudioRecordingsCount'] as num?)?.toInt() ?? 0;
      final camCount = (state['unavailableCamerasCount'] as num?)?.toInt() ?? 0;

      bool changed = false;
      if (micCount == 0 && isSensorActive(SensorType.microphone)) {
        _activeSessions.removeWhere((_, s) => s.sensorType == SensorType.microphone);
        changed = true;
      }
      if (camCount == 0 && isSensorActive(SensorType.camera)) {
        _activeSessions.removeWhere((_, s) => s.sensorType == SensorType.camera);
        changed = true;
      }

      // Re-verify blockedApps against genuine Android permission state
      for (final pkg in _blockedApps.keys.toList()) {
        final sensors = _blockedApps[pkg]?.toList() ?? [];
        for (final sensor in sensors) {
          final isGranted = await checkSensorPermission(pkg, sensor);
          if (isGranted) {
            _blockedApps[pkg]?.remove(sensor);
            changed = true;
          }
        }
        if (_blockedApps[pkg]?.isEmpty ?? false) {
          _blockedApps.remove(pkg);
          changed = true;
        }
      }

      if (changed) {
        notifyListeners();
      }
    } catch (e) {
      developer.log('State reconciliation note: $e', name: 'SensorAccessService');
    }
  }

  /// Calculates dynamic relative elapsed time from a real timestamp.
  /// Never hardcodes "5 minutes ago" or any synthetic time.
  static String formatRelativeTime(DateTime eventTime, [DateTime? now]) {
    final reference = now ?? DateTime.now();
    final difference = reference.difference(eventTime);

    if (difference.isNegative || difference.inSeconds < 45) {
      return 'Just now';
    }
    if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return mins <= 1 ? '1 minute ago' : '$mins minutes ago';
    }
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return hours <= 1 ? '1 hour ago' : '$hours hours ago';
    }
    final days = difference.inDays;
    return days <= 1 ? '1 day ago' : '$days days ago';
  }

  /// Calculates dynamic elapsed active duration from a real start timestamp.
  /// Example: "Active for 12s", "Active for 1m 30s".
  static String formatActiveDuration(DateTime startTime, [DateTime? now]) {
    final current = now ?? DateTime.now();
    final diff = current.difference(startTime);
    final totalSeconds = diff.inSeconds;
    if (totalSeconds < 1) return 'Active for 0s';
    if (totalSeconds < 60) return 'Active for ${totalSeconds}s';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes < 60) {
      return seconds > 0 ? 'Active for ${minutes}m ${seconds}s' : 'Active for ${minutes}m';
    }
    final hours = minutes ~/ 60;
    final remMinutes = minutes % 60;
    return 'Active for ${hours}h ${remMinutes}m';
  }

  /// Clears in-memory history and active states.
  void clearHistory() {
    _recentEvents.clear();
    _activeSessions.clear();
    _getHistoryFile().then((file) async {
      try {
        if (file != null && await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });
    notifyListeners();
  }

  /// Phase 4 User Action: Blocks camera or microphone permission for a verified app via UserService.
  Future<Map<String, dynamic>> blockSensorAccess({
    required String packageName,
    required SensorType sensor,
    required String appName,
  }) async {
    final cleanPkg = packageName.trim();
    if (cleanPkg.isEmpty ||
        cleanPkg == 'null' ||
        (sensor != SensorType.camera &&
            sensor != SensorType.microphone &&
            sensor != SensorType.location)) {
      final err = {
        'success': false,
        'verified': false,
        'error': 'Invalid target: package name and camera/microphone/location sensor required',
        'reason': 'Invalid target: package name and camera/microphone/location sensor required',
      };
      print('PHASE4_ACTION_FAILED: Invalid target: $packageName on ${sensor.toJson()}');
      return err;
    }

    print('PHASE4_ACTION_REQUESTED: Requesting block for $packageName ($appName) on ${sensor.toJson()}');
    final result = await _collector.blockSensorAccess(cleanPkg, sensor.toJson());
    final success = result['success'] == true;
    final verified = result['verified'] == true;

    if (success && verified) {
      _blockedApps.putIfAbsent(cleanPkg, () => <SensorType>{}).add(sensor);
      // Remove any active session for this blocked app and sensor
      final key = '${sensor.toJson()}_$cleanPkg';
      _activeSessions.remove(key);

      // Record blocked event in recent history
      final blockEvent = SensorAccessEvent(
        sensorType: sensor,
        state: SensorAccessState.stopped,
        packageName: cleanPkg,
        appName: appName,
        timestamp: DateTime.now(),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        permissionState: 'DENIED',
        blockedState: true,
        reason: 'User blocked ${sensor.label} access.',
      );
      _recentEvents.insert(0, blockEvent);

      // Expose structured action evidence to Guardian
      _guardianEvidenceLog.add({
        'packageName': cleanPkg,
        'appName': appName,
        'sensor': sensor.toJson(),
        'action': 'BLOCK_${sensor.toJson()}',
        'userConfirmed': true,
        'result': 'SUCCESS',
        'verified': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
      if (_guardianEvidenceLog.length > 50) _guardianEvidenceLog.removeAt(0);

      notifyListeners();
      print('PHASE4_ACTION_SUCCESS: $cleanPkg successfully blocked on ${sensor.toJson()} and verified');
    } else {
      print('PHASE4_ACTION_FAILED: Failed to block or verify $cleanPkg on ${sensor.toJson()}: ${result['error']}');
    }
    return result;
  }

  /// Phase 4 User Action: Restores camera or microphone permission for an app via UserService.
  Future<Map<String, dynamic>> restoreSensorAccess({
    required String packageName,
    required SensorType sensor,
    required String appName,
  }) async {
    final cleanPkg = packageName.trim();
    if (cleanPkg.isEmpty ||
        cleanPkg == 'null' ||
        (sensor != SensorType.camera &&
            sensor != SensorType.microphone &&
            sensor != SensorType.location)) {
      final err = {
        'success': false,
        'verified': false,
        'error': 'Invalid target: package name and camera/microphone/location sensor required',
        'reason': 'Invalid target: package name and camera/microphone/location sensor required',
      };
      print('PHASE4_ACTION_FAILED: Invalid target for restore: $packageName on ${sensor.toJson()}');
      return err;
    }

    print('PHASE4_ACTION_REQUESTED: Requesting restore for $packageName ($appName) on ${sensor.toJson()}');
    final result = await _collector.restoreSensorAccess(cleanPkg, sensor.toJson());
    final success = result['success'] == true;
    final verified = result['verified'] == true;

    if (success && verified) {
      _blockedApps[cleanPkg]?.remove(sensor);
      if (_blockedApps[cleanPkg]?.isEmpty ?? false) {
        _blockedApps.remove(cleanPkg);
      }

      // Expose structured restore evidence to Guardian
      _guardianEvidenceLog.add({
        'packageName': cleanPkg,
        'appName': appName,
        'sensor': sensor.toJson(),
        'action': 'RESTORE_${sensor.toJson()}',
        'userConfirmed': true,
        'result': 'SUCCESS',
        'verified': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
      if (_guardianEvidenceLog.length > 50) _guardianEvidenceLog.removeAt(0);

      notifyListeners();
      print('PHASE4_RESTORE_RESULT: $packageName successfully restored on ${sensor.toJson()} and verified');
    } else {
      print('PHASE4_RESTORE_RESULT: Failed to restore or verify $packageName on ${sensor.toJson()}: ${result['error']}');
    }
    return result;
  }

  /// Checks actual system permission state for a package and sensor.
  Future<bool> checkSensorPermission(String packageName, SensorType sensor) async {
    return await _collector.checkSensorPermission(packageName, sensor.toJson());
  }

  /// Retrieves user action audit trail.
  Future<List<Map<String, dynamic>>> getUserActionAuditLog() async {
    return await _collector.getUserActionAuditLog();
  }

  /// Disposes active subscriptions and stream controllers.
  @override
  void dispose() {
    if (_sharedInstance == this) {
      _sharedInstance = null;
    }
    _isListening = false;
    _nativeSub?.cancel();
    _nativeSub = null;
    _eventStreamController?.close();
    _eventStreamController = null;
    super.dispose();
  }
}
