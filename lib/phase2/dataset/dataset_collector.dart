import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';

import '../../models/app_telemetry.dart';
import '../../models/privacy_event.dart';
import '../../services/storage_service.dart';
import '../../telemetry/app_telemetry_builder.dart';
import '../../telemetry/collectors/android_collector.dart';
import '../../utils/device_identity.dart';
import '../feature_engineering/feature_extractor.dart';
import '../schemas/dataset_schema.dart';
import '../schemas/feature_schema.dart';
import 'collection_session.dart';
import 'dataset_quality_diagnostics.dart';
import 'dataset_record.dart';
import 'dataset_validator.dart';

/// Central collector, validator, deduplicator, and local accumulator
/// for converting real device telemetry ([PrivacyEvent] & [AppTelemetry])
/// into validated, persistent training records ([DatasetRecord]).
/// 
/// Invariants:
/// - Consumes legitimate Phase 1 telemetry without inventing synthetic signals.
/// - Validates records against [FeatureSchema] and [DatasetSchema] before storage.
/// - Deduplicates repeated periodic polling snapshots while preserving distinct events.
/// - Supports explicit collection session lifecycle (NOT_COLLECTING, COLLECTING, STOPPING, STOPPED).
/// - Asynchronous and non-blocking failure-isolated persistence.
/// - Enforces bounded FIFO memory and disk retention.
class DatasetCollector {
  final FeatureExtractor featureExtractor;
  final DatasetValidator validator;
  final StorageService? storageService;
  final AppTelemetryBuilder telemetryBuilder;
  final int maxBufferSize;
  final int deduplicationWindowSize;
  final bool enableDeduplication;
  final bool autoPersist;
  final bool requireExplicitSession;

  CollectionState _state = CollectionState.notCollecting;
  CollectionSession? _currentSession;

  final List<DatasetRecord> _records = [];
  final Set<String> _recentRecordIds = <String>{};
  final Queue<String> _recentRecordIdQueue = Queue<String>();
  final List<String> _validationErrors = [];
  final StreamController<CollectionSession> _sessionStateController =
      StreamController<CollectionSession>.broadcast();
  StreamSubscription<PrivacyEvent>? _streamSubscription;

  DatasetCollector({
    FeatureExtractor? featureExtractor,
    DatasetValidator? validator,
    this.storageService,
    AppTelemetryBuilder? telemetryBuilder,
    this.maxBufferSize = 1000,
    this.deduplicationWindowSize = 5000,
    this.enableDeduplication = true,
    this.autoPersist = true,
    this.requireExplicitSession = true,
  })  : featureExtractor = featureExtractor ?? FeatureExtractor(),
        validator = validator ?? DatasetValidator(),
        telemetryBuilder = telemetryBuilder ?? AppTelemetryBuilder() {
    unawaited(DeviceIdentity.getOrCreateDeviceId());
  }

  int get recordCount => _records.length;
  List<DatasetRecord> get records => List.unmodifiable(_records);
  List<String> get validationErrors => List.unmodifiable(_validationErrors);

  CollectionState get state => _state;
  CollectionSession? get currentSession => _currentSession;
  String? get currentSessionId => _currentSession?.sessionId;
  bool get isCollecting => _state == CollectionState.collecting;
  Stream<CollectionSession> get sessionStream => _sessionStateController.stream;

  /// Starts a new explicit dataset collection session
  CollectionSession startCollection({
    String? sessionId,
    String? sessionName,
  }) {
    final now = DateTime.now();
    final effectiveId = sessionId ??
        'session_${now.millisecondsSinceEpoch}_${now.microsecond.toRadixString(16)}';
    final effectiveName = sessionName ??
        'Session ${now.toIso8601String().substring(0, 19).replaceAll("T", " ")}';

    _currentSession = CollectionSession(
      sessionId: effectiveId,
      sessionName: effectiveName,
      startTime: now.toIso8601String(),
      recordCount: 0,
      storageSizeBytes: 0,
      state: CollectionState.collecting,
    );

    _state = CollectionState.collecting;
    _sessionStateController.add(_currentSession!);
    if (Platform.isAndroid) {
      unawaited(AndroidCollector().startCollectionSession(effectiveId));
    }
    developer.log('Started dataset collection session: $effectiveId',
        name: 'DatasetCollector');
    return _currentSession!;
  }

  /// Stops the active collection session
  Future<CollectionSession?> stopCollection() async {
    if (_state != CollectionState.collecting && _state != CollectionState.notCollecting) {
      return _currentSession;
    }

    _state = CollectionState.stopping;
    if (Platform.isAndroid) {
      await AndroidCollector().stopCollectionSession();
    }
    await flush();

    final now = DateTime.now();
    final finalSize = await storageService?.getStorageSizeBytes() ?? 0;

    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        stopTime: now.toIso8601String(),
        state: CollectionState.stopped,
        storageSizeBytes: finalSize,
      );
      _sessionStateController.add(_currentSession!);
    }

    _state = CollectionState.stopped;
    developer.log('Stopped dataset collection session: ${_currentSession?.sessionId}',
        name: 'DatasetCollector');
    return _currentSession;
  }

  /// Returns current collection session status
  CollectionSession getCollectionStatus() {
    if (_currentSession != null) {
      return _currentSession!;
    }
    return CollectionSession(
      sessionId: 'none',
      sessionName: 'Idle',
      startTime: DateTime.now().toIso8601String(),
      state: _state,
    );
  }

  /// Captures and validates a single [DatasetRecord] from an [AppTelemetry] and [PrivacyEvent].
  /// Returns the record if valid and unique; returns null if deduplicated, invalid, or inactive.
  DatasetRecord? captureRecord({
    required AppTelemetry app,
    required PrivacyEvent event,
    String? label,
    bool bypassDeduplication = false,
    bool bypassSessionCheck = false,
  }) {
    // 0. Enforce explicit collection session lifecycle if required
    if (requireExplicitSession && !bypassSessionCheck && _state != CollectionState.collecting) {
      return null;
    }

    final recordId = '${event.timestamp}_${app.packageName}_${app.uid}';

    // 1. Deduplication check against sliding window of recent record IDs
    if (enableDeduplication && !bypassDeduplication && _recentRecordIds.contains(recordId)) {
      return null;
    }

    // 2. Deterministic feature extraction
    final featureVector = featureExtractor.extract(app, event);
    final deviceIdHash = DeviceIdentity.syncDeviceId;

    final androidVersion = event.deviceContext.androidVersion.isNotEmpty
        ? event.deviceContext.androidVersion
        : (event.deviceContext.sdkInt > 0
            ? 'Android SDK ${event.deviceContext.sdkInt}'
            : 'UNKNOWN');
    final collectorHealthStatus =
        event.telemetryHealth.permissions.status.isNotEmpty
            ? event.telemetryHealth.permissions.status
            : 'UNKNOWN';
    final sdkInt =
        event.deviceContext.sdkInt > 0 ? event.deviceContext.sdkInt : 1;

    final record = DatasetRecord(
      recordId: recordId,
      sessionId: _currentSession?.sessionId,
      deviceIdHash: deviceIdHash,
      androidVersion: androidVersion,
      sdkInt: sdkInt,
      timestamp: event.timestamp,
      packageName: app.packageName,
      collectorHealthStatus: collectorHealthStatus,
      rawTelemetry: {
        'app': app.toJson(),
        'deviceContext': event.deviceContext.toJson(),
        'securityContext': event.securityContext.toJson(),
        'network': event.network.toJson(),
        'sensorTelemetry': event.sensorTelemetry.toJson(),
        'usageSummary': event.usageSummary.toJson(),
      },
      featureVector: featureVector,
      label: label,
    );

    // 3. Validation before storage
    final errors = validator.validateRecord(record);
    if (errors.isNotEmpty) {
      _validationErrors.addAll(errors);
      developer.log(
        'DatasetRecord validation rejected (${record.packageName}): ${errors.join("; ")}',
        name: 'DatasetCollector',
      );
      return null;
    }

    // 4. Update deduplication sliding window
    _recentRecordIds.add(recordId);
    _recentRecordIdQueue.add(recordId);
    if (deduplicationWindowSize > 0 &&
        _recentRecordIdQueue.length > deduplicationWindowSize) {
      final evicted = _recentRecordIdQueue.removeFirst();
      _recentRecordIds.remove(evicted);
    }

    // 5. Enforce persistence and record counter semantics (RECEIVED != VALIDATED != PERSISTED)
    if (storageService == null || !autoPersist) {
      if (_records.length >= maxBufferSize && maxBufferSize > 0) {
        _records.removeAt(0);
      }
      _records.add(record);

      if (_currentSession != null) {
        _currentSession = _currentSession!.copyWith(
          recordCount: _currentSession!.recordCount + 1,
        );
        _sessionStateController.add(_currentSession!);
      }
    } else {
      // 6. Asynchronous non-blocking persistence with verified success counting
      unawaited(_safePersist(record));
    }

    return record;
  }

  /// Batch-converts an entire live [PrivacyEvent] snapshot into validated [DatasetRecord]s.
  List<DatasetRecord> captureEvent(PrivacyEvent event, {String? label}) {
    if (requireExplicitSession && _state != CollectionState.collecting) {
      return [];
    }

    final apps = telemetryBuilder.build(event);
    final captured = <DatasetRecord>[];

    for (final app in apps) {
      final record = captureRecord(app: app, event: event, label: label);
      if (record != null) {
        captured.add(record);
      }
    }

    return captured;
  }

  Future<bool> _safePersist(DatasetRecord record) async {
    try {
      final success = await storageService?.persistRecord(record) ?? false;
      if (success) {
        if (_records.length >= maxBufferSize && maxBufferSize > 0) {
          _records.removeAt(0);
        }
        _records.add(record);

        if (_currentSession != null) {
          _currentSession = _currentSession!.copyWith(
            recordCount: _currentSession!.recordCount + 1,
          );
          _sessionStateController.add(_currentSession!);
        }
        return true;
      } else {
        _validationErrors.add(
            'Storage persistence failed for record ${record.recordId}');
        developer.log(
            'Storage persistence returned false for record ${record.recordId}',
            name: 'DatasetCollector');
        return false;
      }
    } catch (e) {
      _validationErrors.add(
          'Storage persistence error for record ${record.recordId}: $e');
      developer.log('Error persisting telemetry record: $e',
          name: 'DatasetCollector');
      return false;
    }
  }

  /// Subscribes directly to a real-time [PrivacyEvent] telemetry stream
  void attachToTelemetryStream(Stream<PrivacyEvent> stream) {
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen(
      (event) {
        captureEvent(event);
      },
      onError: (e) {
        developer.log('Telemetry stream error in collector: $e',
            name: 'DatasetCollector');
      },
    );
  }

  /// Unsubscribes from the active telemetry stream
  void unsubscribe() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  /// Loads historical records from persistent storage into memory buffer
  Future<List<DatasetRecord>> loadFromStorage({String? sessionId}) async {
    if (storageService == null) return _records;
    try {
      final loaded = await storageService!.loadRecords();
      _records.clear();
      _recentRecordIds.clear();
      _recentRecordIdQueue.clear();

      final filtered = sessionId != null
          ? loaded.where((r) => r.sessionId == sessionId).toList()
          : loaded;

      for (final r in filtered) {
        if (_records.length >= maxBufferSize && maxBufferSize > 0) {
          _records.removeAt(0);
        }
        _records.add(r);
        _recentRecordIds.add(r.recordId);
        _recentRecordIdQueue.add(r.recordId);
        if (deduplicationWindowSize > 0 &&
            _recentRecordIdQueue.length > deduplicationWindowSize) {
          _recentRecordIds.remove(_recentRecordIdQueue.removeFirst());
        }
      }
      return _records;
    } catch (e) {
      developer.log('Failed to load dataset from storage: $e',
          name: 'DatasetCollector');
      return _records;
    }
  }

  /// Returns storage size in bytes
  Future<int> getStorageSize() async {
    return await storageService?.getStorageSizeBytes() ?? 0;
  }

  /// Queries records with filters without loading all files in RAM
  Future<List<DatasetRecord>> getRecords({
    int? limit,
    int offset = 0,
    String? sessionId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (storageService != null) {
      return await storageService!.getRecords(
        limit: limit,
        offset: offset,
        sessionId: sessionId,
        startTime: startTime,
        endTime: endTime,
      );
    }
    return _records;
  }

  /// Returns summary information for historical sessions
  Future<List<Map<String, dynamic>>> getSessionSummaries() async {
    return await storageService?.getSessionSummaries() ?? [];
  }

  /// Deletes a specific historical session
  Future<int> deleteSession(String sessionId) async {
    return await storageService?.deleteSession(sessionId) ?? 0;
  }

  /// Exports a specific session to a target file
  Future<bool> exportSessionToFile(
    String sessionId,
    File targetFile, {
    bool asJsonLines = false,
  }) async {
    return await storageService?.exportToFile(
          targetFile,
          sessionId: sessionId,
          asJsonLines: asJsonLines,
        ) ??
        false;
  }

  /// Clears in-memory records and optionally wipes storage
  Future<void> clear({bool clearStorage = false}) async {
    _records.clear();
    _recentRecordIds.clear();
    _recentRecordIdQueue.clear();
    _validationErrors.clear();
    if (clearStorage && storageService != null) {
      await storageService!.clear();
    }
  }

  /// Flushes pending storage operations
  Future<void> flush() async {
    await storageService?.flush();
  }

  /// Disposes active subscriptions and resources
  void dispose() {
    unsubscribe();
    _sessionStateController.close();
  }

  /// Exports accumulated records as JSON list
  List<Map<String, dynamic>> exportJson() {
    return _records.map((r) => r.toJson()).toList();
  }

  /// Exports full structured dataset map conforming to [DatasetSchema]
  Future<Map<String, dynamic>> exportDatasetMap({String? sessionId}) async {
    if (storageService != null) {
      return await storageService!.exportDatasetMap(sessionId: sessionId);
    }
    final recordsToExport = sessionId != null
        ? _records.where((r) => r.sessionId == sessionId).toList()
        : _records;

    return {
      'datasetSchema': const DatasetSchema().toJson(),
      'featureSchema': FeatureSchema.v1.toJson(),
      'exportedAt': DateTime.now().toIso8601String(),
      'sessionId': sessionId,
      'recordCount': recordsToExport.length,
      'records': recordsToExport.map((r) => r.toJson()).toList(),
    };
  }

  /// Validates all accumulated records
  DatasetValidationReport validateAccumulated() {
    return validator.validateDataset(_records);
  }

  /// Calculates DatasetQualityDiagnostics for accumulated or stored records
  Future<DatasetQualityDiagnostics> getQualityDiagnostics({String? sessionId}) async {
    if (storageService != null) {
      return await storageService!.getQualityDiagnostics(sessionId: sessionId);
    }
    final recordsToAnalyze = sessionId != null
        ? _records.where((r) => r.sessionId == sessionId).toList()
        : _records;
    return DatasetQualityDiagnostics.fromRecords(recordsToAnalyze);
  }
}


