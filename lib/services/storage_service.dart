import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../phase2/dataset/dataset_quality_diagnostics.dart';
import '../phase2/dataset/dataset_record.dart';
import '../phase2/schemas/dataset_schema.dart';
import '../phase2/schemas/feature_schema.dart';

/// Append-safe, local, persistent storage service for real telemetry [DatasetRecord]s.
/// 
/// Invariants:
/// - Persists records to append-safe JSON Lines (.jsonl) file in application-private storage.
/// - Resilient against corrupted or partially written lines upon recovery.
/// - Enforces bounded FIFO retention limits to prevent unbounded storage growth.
/// - Asynchronous and non-blocking with queued write serialization.
/// - Exports datasets conforming strictly to [DatasetSchema].
class StorageService {
  File _file;
  File get file => _file;
  final int maxRecords;
  final int maxStorageBytes;
  final DatasetSchema datasetSchema;
  final FeatureSchema featureSchema;

  Future<void> _lastOperation = Future.value();
  int _cachedRecordCount = 0;
  bool _isInitialized = false;

  StorageService({
    File? file,
    this.maxRecords = 10000,
    this.maxStorageBytes = 50 * 1024 * 1024, // 50 MB default storage limit
    DatasetSchema? datasetSchema,
    FeatureSchema? featureSchema,
  })  : _file = file ?? File('privacy_sentinel_dataset.jsonl'),
        datasetSchema = datasetSchema ?? const DatasetSchema(),
        featureSchema = featureSchema ?? FeatureSchema.v1;

  /// Serializes operations to avoid concurrent file write interleaving
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _lastOperation = _lastOperation.then((_) async {
      try {
        final result = await operation();
        completer.complete(result);
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }

  /// Initializes storage file in application-private directory and counts existing valid records
  Future<void> initialize() => _enqueue(() async {
        if (_isInitialized) return;
        try {
          if (!p.isAbsolute(_file.path)) {
            try {
              final docsDir = await getApplicationDocumentsDirectory();
              _file = File(p.join(docsDir.path, _file.path));
            } catch (e) {
              // Safe fallback for testing or non-Flutter execution contexts
              developer.log('Application private documents directory note: $e',
                  name: 'StorageService');
            }
          }
          if (!await file.exists()) {
            await file.create(recursive: true);
            _cachedRecordCount = 0;
          } else {
            final records = await _loadRecordsInternal();
            _cachedRecordCount = records.length;
          }
          _isInitialized = true;
        } catch (e) {
          developer.log('StorageService initialization note: $e',
              name: 'StorageService');
          _isInitialized = true;
        }
      });

  /// Persists a single DatasetRecord asynchronously to local JSONL storage
  Future<bool> persistRecord(DatasetRecord record) {
    return _enqueue(() async {
      try {
        if (!await file.exists()) {
          await file.create(recursive: true);
        }

        final line = '${jsonEncode(record.toJson())}\n';
        await file.writeAsString(line, mode: FileMode.append, flush: true);
        _cachedRecordCount++;

        // Enforce bounded retention if record count or size exceeds limit
        await _checkRetentionLimits();
        return true;
      } catch (e) {
        developer.log('Failed to persist record ${record.recordId}: $e',
            name: 'StorageService');
        return false;
      }
    });
  }

  /// Persists a batch of DatasetRecords
  Future<int> persistRecords(List<DatasetRecord> records) {
    if (records.isEmpty) return Future.value(0);
    return _enqueue(() async {
      try {
        if (!await file.exists()) {
          await file.create(recursive: true);
        }

        final buffer = StringBuffer();
        for (final r in records) {
          buffer.writeln(jsonEncode(r.toJson()));
        }

        await file.writeAsString(buffer.toString(),
            mode: FileMode.append, flush: true);
        _cachedRecordCount += records.length;

        await _checkRetentionLimits();
        return records.length;
      } catch (e) {
        developer.log('Failed to persist batch records: $e',
            name: 'StorageService');
        return 0;
      }
    });
  }

  /// Loads all valid DatasetRecords from persistent JSONL storage, skipping corrupted lines
  Future<List<DatasetRecord>> loadRecords() {
    return _enqueue(() async {
      return await _loadRecordsInternal();
    });
  }

  /// Internal line-by-line streaming generator from persistent storage
  Stream<String> _streamLines() async* {
    if (!await file.exists()) return;
    yield* file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
  }

  /// Streams and filters records with pagination without loading entire file into memory
  Future<List<DatasetRecord>> getRecords({
    int? limit,
    int offset = 0,
    String? sessionId,
    DateTime? startTime,
    DateTime? endTime,
    String? packageNameQuery,
    String? availabilityFilter,
    bool? hasMicActivity,
    bool? hasCameraActivity,
    bool? hasForegroundActivity,
    bool? hasNetworkActivity,
  }) {
    return _enqueue(() async {
      if (!await file.exists()) return [];

      final results = <DatasetRecord>[];
      int skipped = 0;

      await for (final line in _streamLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) continue;
          final map = Map<String, dynamic>.from(decoded);

          if (!_recordMatchesFilter(
            map,
            sessionId: sessionId,
            startTime: startTime,
            endTime: endTime,
            packageNameQuery: packageNameQuery,
            availabilityFilter: availabilityFilter,
            hasMicActivity: hasMicActivity,
            hasCameraActivity: hasCameraActivity,
            hasForegroundActivity: hasForegroundActivity,
            hasNetworkActivity: hasNetworkActivity,
          )) {
            continue;
          }

          if (skipped < offset) {
            skipped++;
            continue;
          }

          final record = DatasetRecord.fromJson(map, schema: featureSchema);
          results.add(record);

          if (limit != null && results.length >= limit) {
            break;
          }
        } catch (_) {
          // Skip corrupted lines
        }
      }

      return results;
    });
  }

  /// Counts total records matching the given filter without instantiating objects
  Future<int> countRecords({
    String? sessionId,
    DateTime? startTime,
    DateTime? endTime,
    String? packageNameQuery,
    String? availabilityFilter,
    bool? hasMicActivity,
    bool? hasCameraActivity,
    bool? hasForegroundActivity,
    bool? hasNetworkActivity,
  }) {
    return _enqueue(() async {
      if (!await file.exists()) return 0;

      int matchCount = 0;
      await for (final line in _streamLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) continue;
          final map = Map<String, dynamic>.from(decoded);

          if (_recordMatchesFilter(
            map,
            sessionId: sessionId,
            startTime: startTime,
            endTime: endTime,
            packageNameQuery: packageNameQuery,
            availabilityFilter: availabilityFilter,
            hasMicActivity: hasMicActivity,
            hasCameraActivity: hasCameraActivity,
            hasForegroundActivity: hasForegroundActivity,
            hasNetworkActivity: hasNetworkActivity,
          )) {
            matchCount++;
          }
        } catch (_) {}
      }

      return matchCount;
    });
  }

  /// Extracts list of unique package names observed in storage (optionally filtered by session)
  Future<List<String>> getAvailablePackages({String? sessionId}) {
    return _enqueue(() async {
      if (!await file.exists()) return [];

      final packages = <String>{};
      await for (final line in _streamLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) continue;
          final map = Map<String, dynamic>.from(decoded);

          if (sessionId != null && map['sessionId'] != sessionId) {
            continue;
          }

          final pkg = map['packageName']?.toString();
          if (pkg != null && pkg.isNotEmpty) {
            packages.add(pkg);
          }
        } catch (_) {}
      }

      final list = packages.toList()..sort();
      return list;
    });
  }

  /// Calculates aggregate summary metrics directly from actual persisted records
  Future<Map<String, dynamic>> getSessionSummaryDetails({String? sessionId}) {
    return _enqueue(() async {
      if (!await file.exists()) {
        return {
          'sessionId': sessionId ?? 'all',
          'recordCount': 0,
          'firstTimestamp': '',
          'lastTimestamp': '',
          'durationSeconds': 0,
          'storageSizeBytes': 0,
          'uniquePackages': <String>[],
          'packageCounts': <String, int>{},
          'micActiveRecords': 0,
          'cameraActiveRecords': 0,
          'networkActiveRecords': 0,
          'foregroundRecords': 0,
          'availabilityBreakdown': <String, int>{
            'VALID': 0,
            'ZERO_REPORTED': 0,
            'RESTRICTED': 0,
            'DENIED': 0,
            'UNAVAILABLE': 0,
            'ERROR': 0,
            'UNKNOWN': 0,
          },
        };
      }

      int totalCount = 0;
      int totalSizeBytes = 0;
      String firstTs = '';
      String lastTs = '';
      final packageCounts = <String, int>{};
      int micActive = 0;
      int cameraActive = 0;
      int networkActive = 0;
      int foregroundActive = 0;

      final availBreakdown = <String, int>{
        'VALID': 0,
        'ZERO_REPORTED': 0,
        'RESTRICTED': 0,
        'DENIED': 0,
        'UNAVAILABLE': 0,
        'ERROR': 0,
        'UNKNOWN': 0,
      };

      await for (final line in _streamLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) continue;
          final map = Map<String, dynamic>.from(decoded);

          if (sessionId != null && map['sessionId'] != sessionId) {
            continue;
          }

          totalCount++;
          totalSizeBytes += utf8.encode(trimmed).length;

          final ts = map['timestamp']?.toString() ?? '';
          if (firstTs.isEmpty) firstTs = ts;
          lastTs = ts;

          final pkg = map['packageName']?.toString() ?? 'unknown';
          packageCounts[pkg] = (packageCounts[pkg] ?? 0) + 1;

          final raw = map['rawTelemetry'] is Map
              ? Map<String, dynamic>.from(map['rawTelemetry'] as Map)
              : <String, dynamic>{};

          final sensor = raw['sensorTelemetry'] is Map
              ? Map<String, dynamic>.from(raw['sensorTelemetry'] as Map)
              : <String, dynamic>{};

          final app = raw['app'] is Map
              ? Map<String, dynamic>.from(raw['app'] as Map)
              : <String, dynamic>{};

          final network = raw['network'] is Map
              ? Map<String, dynamic>.from(raw['network'] as Map)
              : <String, dynamic>{};

          // Microphone activity
          final isMicInUse = sensor['microphoneHardwareInUse'] == true ||
              (sensor['activeAudioRecordingsCount'] as num? ?? 0) > 0;
          if (isMicInUse) micActive++;

          // Camera usage vs availability (CameraManager.AvailabilityCallback)
          final isCamInUse = sensor['cameraHardwareInUse'] == true;
          if (isCamInUse) cameraActive++;

          // Foreground activity
          final isForeground = app['isCurrentlyForeground'] == true ||
              raw['usageSummary']?['currentForegroundApp'] == pkg;
          if (isForeground) foregroundActive++;

          // Network activity
          final appTx = (app['uploadBytes'] as num? ?? 0);
          final appRx = (app['downloadBytes'] as num? ?? 0);
          final devTx = (network['deviceTotalTxBytes'] as num? ?? 0);
          final devRx = (network['deviceTotalRxBytes'] as num? ?? 0);
          if (appTx > 0 || appRx > 0 || devTx > 0 || devRx > 0) {
            networkActive++;
          }

          // Availability breakdown from features
          final fv = map['featureVector'];
          if (fv is Map) {
            final fList = (fv['values'] as List?) ?? (fv['features'] as List?);
            if (fList != null) {
              for (final item in fList) {
                if (item is Map) {
                  final status = item['status']?.toString().toUpperCase() ?? 'UNKNOWN';
                  if (availBreakdown.containsKey(status)) {
                    availBreakdown[status] = availBreakdown[status]! + 1;
                  } else {
                    availBreakdown[status] = 1;
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      int durationSec = 0;
      if (firstTs.isNotEmpty && lastTs.isNotEmpty) {
        final start = DateTime.tryParse(firstTs);
        final end = DateTime.tryParse(lastTs);
        if (start != null && end != null) {
          durationSec = end.difference(start).inSeconds.abs();
        }
      }

      return {
        'sessionId': sessionId ?? 'all',
        'recordCount': totalCount,
        'firstTimestamp': firstTs,
        'lastTimestamp': lastTs,
        'durationSeconds': durationSec,
        'storageSizeBytes': totalSizeBytes,
        'uniquePackages': packageCounts.keys.toList(),
        'packageCounts': packageCounts,
        'micActiveRecords': micActive,
        'cameraActiveRecords': cameraActive,
        'networkActiveRecords': networkActive,
        'foregroundRecords': foregroundActive,
        'availabilityBreakdown': availBreakdown,
      };
    });
  }

  /// Calculates a complete DatasetQualityDiagnostics summary for persisted records
  Future<DatasetQualityDiagnostics> getQualityDiagnostics({String? sessionId}) {
    return _enqueue(() async {
      final records = await _loadRecordsInternal();
      final filtered = sessionId != null
          ? records.where((r) => r.sessionId == sessionId).toList()
          : records;
      final storageSize = await file.exists() ? await file.length() : 0;
      return DatasetQualityDiagnostics.fromRecords(
        filtered,
        storageSize: storageSize,
      );
    });
  }

  /// Internal filter matching helper
  bool _recordMatchesFilter(
    Map<String, dynamic> map, {
    String? sessionId,
    DateTime? startTime,
    DateTime? endTime,
    String? packageNameQuery,
    String? availabilityFilter,
    bool? hasMicActivity,
    bool? hasCameraActivity,
    bool? hasForegroundActivity,
    bool? hasNetworkActivity,
  }) {
    // Session filter
    if (sessionId != null && map['sessionId'] != sessionId) {
      return false;
    }

    // Timestamp range filter
    if (startTime != null || endTime != null) {
      final tsStr = map['timestamp']?.toString();
      if (tsStr == null) return false;
      final recordTime = DateTime.tryParse(tsStr);
      if (recordTime == null) return false;
      if (startTime != null && recordTime.isBefore(startTime)) return false;
      if (endTime != null && recordTime.isAfter(endTime)) return false;
    }

    final raw = map['rawTelemetry'] is Map
        ? Map<String, dynamic>.from(map['rawTelemetry'] as Map)
        : <String, dynamic>{};
    final app = raw['app'] is Map
        ? Map<String, dynamic>.from(raw['app'] as Map)
        : <String, dynamic>{};
    final sensor = raw['sensorTelemetry'] is Map
        ? Map<String, dynamic>.from(raw['sensorTelemetry'] as Map)
        : <String, dynamic>{};
    final network = raw['network'] is Map
        ? Map<String, dynamic>.from(raw['network'] as Map)
        : <String, dynamic>{};

    // Package query filter
    if (packageNameQuery != null && packageNameQuery.trim().isNotEmpty) {
      final q = packageNameQuery.trim().toLowerCase();
      final pkg = (map['packageName']?.toString() ?? '').toLowerCase();
      final appName = (app['appName']?.toString() ?? '').toLowerCase();
      if (!pkg.contains(q) && !appName.contains(q)) {
        return false;
      }
    }

    // Mic activity filter
    if (hasMicActivity == true) {
      final isMic = sensor['microphoneHardwareInUse'] == true ||
          (sensor['activeAudioRecordingsCount'] as num? ?? 0) > 0;
      if (!isMic) return false;
    }

    // Camera activity filter (confirmed usage only)
    if (hasCameraActivity == true) {
      final isCam = sensor['cameraHardwareInUse'] == true;
      if (!isCam) return false;
    }

    // Foreground activity filter
    if (hasForegroundActivity == true) {
      final isFg = app['isCurrentlyForeground'] == true ||
          raw['usageSummary']?['currentForegroundApp'] == map['packageName'];
      if (!isFg) return false;
    }

    // Network activity filter
    if (hasNetworkActivity == true) {
      final appTx = (app['uploadBytes'] as num? ?? 0);
      final appRx = (app['downloadBytes'] as num? ?? 0);
      final devTx = (network['deviceTotalTxBytes'] as num? ?? 0);
      final devRx = (network['deviceTotalRxBytes'] as num? ?? 0);
      if (appTx <= 0 && appRx <= 0 && devTx <= 0 && devRx <= 0) {
        return false;
      }
    }

    // Availability status filter
    if (availabilityFilter != null && availabilityFilter.isNotEmpty) {
      final targetStatus = availabilityFilter.toUpperCase();
      bool foundStatus = false;

      if ((map['collectorHealthStatus']?.toString().toUpperCase() ?? '') == targetStatus) {
        foundStatus = true;
      }

      if (!foundStatus) {
        final fv = map['featureVector'];
        if (fv is Map) {
          final fList = (fv['values'] as List?) ?? (fv['features'] as List?);
          if (fList != null) {
            for (final item in fList) {
              if (item is Map &&
                  item['status']?.toString().toUpperCase() == targetStatus) {
                foundStatus = true;
                break;
              }
            }
          }
        }
      }

      if (!foundStatus) return false;
    }

    return true;
  }

  /// Returns session summaries grouped by sessionId
  Future<List<Map<String, dynamic>>> getSessionSummaries() {
    return _enqueue(() async {
      if (!await file.exists()) return [];

      final sessionMap = <String, Map<String, dynamic>>{};
      await for (final line in _streamLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) continue;
          final map = Map<String, dynamic>.from(decoded);

          final sId = map['sessionId']?.toString() ?? 'unassigned_session';
          final ts = map['timestamp']?.toString() ?? '';

          if (!sessionMap.containsKey(sId)) {
            sessionMap[sId] = {
              'sessionId': sId,
              'sessionName': sId,
              'firstTimestamp': ts,
              'lastTimestamp': ts,
              'recordCount': 1,
              'approxSizeBytes': utf8.encode(trimmed).length,
              'status': 'COMPLETED',
            };
          } else {
            final summary = sessionMap[sId]!;
            summary['recordCount'] = (summary['recordCount'] as int) + 1;
            summary['lastTimestamp'] = ts;
            summary['approxSizeBytes'] =
                (summary['approxSizeBytes'] as int) + utf8.encode(trimmed).length;
          }
        } catch (_) {}
      }

      // Compute durations
      for (final s in sessionMap.values) {
        final start = DateTime.tryParse(s['firstTimestamp']?.toString() ?? '');
        final end = DateTime.tryParse(s['lastTimestamp']?.toString() ?? '');
        if (start != null && end != null) {
          s['durationSeconds'] = end.difference(start).inSeconds.abs();
        } else {
          s['durationSeconds'] = 0;
        }
      }

      return sessionMap.values.toList();
    });
  }

  /// Deletes all records belonging to a specific sessionId
  Future<int> deleteSession(String sessionId) {
    return _enqueue(() async {
      if (!await file.exists()) return 0;

      final remainingRecords = <DatasetRecord>[];
      int deletedCount = 0;

      await for (final line in _streamLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            final map = Map<String, dynamic>.from(decoded);
            if (map['sessionId'] == sessionId) {
              deletedCount++;
            } else {
              remainingRecords.add(DatasetRecord.fromJson(map, schema: featureSchema));
            }
          }
        } catch (_) {}
      }

      if (deletedCount > 0) {
        final buffer = StringBuffer();
        for (final r in remainingRecords) {
          buffer.writeln(jsonEncode(r.toJson()));
        }
        await file.writeAsString(buffer.toString(),
            mode: FileMode.write, flush: true);
        _cachedRecordCount = remainingRecords.length;
      }

      return deletedCount;
    });
  }

  Future<List<DatasetRecord>> _loadRecordsInternal() async {
    if (!await file.exists()) {
      return [];
    }

    final validRecords = <DatasetRecord>[];
    int corruptedLines = 0;
    int lineIndex = 0;

    try {
      await for (final rawLine in _streamLines()) {
        lineIndex++;
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) {
            final record =
                DatasetRecord.fromJson(decoded, schema: featureSchema);
            validRecords.add(record);
          } else if (decoded is Map) {
            final map = Map<String, dynamic>.from(decoded);
            final record =
                DatasetRecord.fromJson(map, schema: featureSchema);
            validRecords.add(record);
          } else {
            corruptedLines++;
          }
        } catch (e) {
          corruptedLines++;
          developer.log(
              'Skipping corrupted JSON line #$lineIndex in ${file.path}: $e',
              name: 'StorageService');
        }
      }

      _cachedRecordCount = validRecords.length;
      if (corruptedLines > 0) {
        developer.log(
            'Loaded ${validRecords.length} valid records ($corruptedLines corrupted lines skipped)',
            name: 'StorageService');
      }
    } catch (e) {
      developer.log('Error reading storage file: $e',
          name: 'StorageService');
    }

    return validRecords;
  }

  /// Checks both record count and file size limits
  Future<void> _checkRetentionLimits() async {
    try {
      final currentSize = await file.exists() ? await file.length() : 0;
      final exceedsCount = maxRecords > 0 && _cachedRecordCount > maxRecords;
      final exceedsSize = maxStorageBytes > 0 && currentSize > maxStorageBytes;

      if (exceedsCount || exceedsSize) {
        await _enforceRetentionInternal();
      }
    } catch (_) {}
  }

  /// Enforces maximum storage retention by keeping newest lines under count and size limits
  Future<void> _enforceRetentionInternal() async {
    try {
      final records = await _loadRecordsInternal();
      if (records.isEmpty) return;

      int targetCount = records.length;
      if (maxRecords > 0 && targetCount > maxRecords) {
        targetCount = maxRecords;
      }

      var trimmedRecords = records.sublist(records.length - targetCount);

      // If still exceeding byte size, trim oldest lines until under limit
      if (maxStorageBytes > 0) {
        while (trimmedRecords.length > 1) {
          final approxSize = trimmedRecords.fold<int>(
              0, (sum, r) => sum + jsonEncode(r.toJson()).length + 1);
          if (approxSize <= maxStorageBytes) break;
          trimmedRecords.removeAt(0); // Evict oldest
        }
      }

      final buffer = StringBuffer();
      for (final r in trimmedRecords) {
        buffer.writeln(jsonEncode(r.toJson()));
      }

      await file.writeAsString(buffer.toString(),
          mode: FileMode.write, flush: true);
      _cachedRecordCount = trimmedRecords.length;
    } catch (e) {
      developer.log('Retention enforcement warning: $e',
          name: 'StorageService');
    }
  }

  /// Exports accumulated records formatted in machine-readable JSON adhering to DatasetSchema
  Future<Map<String, dynamic>> exportDatasetMap({String? sessionId}) {
    return _enqueue(() async {
      return await _exportDatasetMapInternal(sessionId: sessionId);
    });
  }

  Future<Map<String, dynamic>> _exportDatasetMapInternal({String? sessionId}) async {
    final allRecords = await _loadRecordsInternal();
    final records = sessionId != null
        ? allRecords.where((r) => r.sessionId == sessionId).toList()
        : allRecords;

    return {
      'datasetSchema': datasetSchema.toJson(),
      'featureSchema': featureSchema.toJson(),
      'exportedAt': DateTime.now().toIso8601String(),
      'sessionId': sessionId,
      'recordCount': records.length,
      'records': records.map((r) => r.toJson()).toList(),
    };
  }

  /// Exports accumulated records as a JSON list
  Future<List<Map<String, dynamic>>> exportJsonList({String? sessionId}) {
    return _enqueue(() async {
      final records = await _loadRecordsInternal();
      final filtered = sessionId != null
          ? records.where((r) => r.sessionId == sessionId).toList()
          : records;
      return filtered.map((r) => r.toJson()).toList();
    });
  }

  /// Exports accumulated records directly to a machine-readable target file (JSON or JSONL)
  Future<bool> exportToFile(
    File targetFile, {
    String? sessionId,
    bool asJsonLines = false,
  }) {
    return _enqueue(() async {
      try {
        if (!await targetFile.exists()) {
          await targetFile.create(recursive: true);
        }

        if (asJsonLines) {
          final allRecords = await _loadRecordsInternal();
          final records = sessionId != null
              ? allRecords.where((r) => r.sessionId == sessionId).toList()
              : allRecords;
          final buffer = StringBuffer();
          for (final r in records) {
            buffer.writeln(jsonEncode(r.toJson()));
          }
          await targetFile.writeAsString(buffer.toString(),
              mode: FileMode.write, flush: true);
        } else {
          final dataset = await _exportDatasetMapInternal(sessionId: sessionId);
          final formatted =
              const JsonEncoder.withIndent('  ').convert(dataset);
          await targetFile.writeAsString(formatted,
              mode: FileMode.write, flush: true);
        }
        return true;
      } catch (e) {
        developer.log('Failed to export dataset to ${targetFile.path}: $e',
            name: 'StorageService');
        return false;
      }
    });
  }

  /// Returns storage file size in bytes
  Future<int> getStorageSizeBytes() async {
    try {
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Returns count of persisted records
  int get cachedRecordCount => _cachedRecordCount;

  /// Clears storage
  Future<void> clear() => _enqueue(() async {
        if (await file.exists()) {
          await file.writeAsString('', mode: FileMode.write, flush: true);
        }
        _cachedRecordCount = 0;
      });

  /// Flushes pending operations
  Future<void> flush() => _enqueue(() async {
        if (await file.exists()) {
          final sink = file.openWrite(mode: FileMode.append);
          await sink.flush();
          await sink.close();
        }
      });
}
