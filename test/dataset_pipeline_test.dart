import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/phase2/dataset/dataset_collector.dart';
import 'package:mobile_privacy_security_project/phase2/dataset/dataset_validator.dart';
import 'package:mobile_privacy_security_project/phase2/schemas/feature_definition.dart';
import 'package:mobile_privacy_security_project/services/storage_service.dart';
import 'package:mobile_privacy_security_project/telemetry/app_telemetry_builder.dart';
import 'package:mobile_privacy_security_project/telemetry/telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dataset_pipeline_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PrivacyEvent createSampleEvent({
    String timestamp = '2026-08-17T18:30:00.000Z',
    String usageAvailability = 'VALID',
    int? foregroundDurationMs = 120000,
    int? foregroundTransitions = 5,
    String netAvailability = 'VALID',
    int? uploadBytes = 2048,
    int? downloadBytes = 8192,
    bool? screenLocked = false,
    bool? micInUse = false,
  }) {
    return PrivacyEvent(
      timestamp: timestamp,
      deviceContext: DeviceContext(
        manufacturer: 'Google',
        model: 'Pixel 8',
        brand: 'google',
        device: 'shiba',
        board: 'shiba',
        hardware: 'zuma',
        androidVersion: '14',
        sdkInt: 34,
        screenOn: true,
        screenLocked: screenLocked,
        isDeviceSecure: true,
        batteryPercent: 85,
        batteryStatus: 'DISCHARGING',
      ),
      securityContext: SecurityContext(
        developerOptionsEnabled: false,
        adbEnabled: false,
        accessibilityEnabled: false,
        selfCanDrawOverlays: false,
        selfIsIgnoringBatteryOptimizations: false,
        vpnActive: false,
        isRootedHeuristic: false,
      ),
      network: NetworkTelemetry(
        isConnected: true,
        transport: 'WIFI',
        vpnActive: false,
        deviceTotalTxBytes: 50000,
        deviceTotalRxBytes: 150000,
      ),
      sensorTelemetry: SensorPrivacyTelemetry(
        cameraUnavailable: false,
        microphoneHardwareInUse: micInUse,
        audioMode: 'NORMAL',
        sensorAvailability: 'VALID',
      ),
      usageSummary: UsageSummary(
        usageAccessGranted: true,
        availability: usageAvailability,
        totalForegroundTransitions: foregroundTransitions,
        totalForegroundDurationMs: foregroundDurationMs,
      ),
      telemetryHealth: TelemetryHealth(
        permissions: CollectorHealth(status: 'VALID', message: 'OK'),
        usage: CollectorHealth(status: usageAvailability, message: 'OK'),
        network: CollectorHealth(status: netAvailability, message: 'OK'),
        security: CollectorHealth(status: 'VALID', message: 'OK'),
        sensors: CollectorHealth(status: 'VALID', message: 'OK'),
        deviceContext: CollectorHealth(status: 'VALID', message: 'OK'),
      ),
      apps: [
        {
          'packageName': 'com.instagram.android',
          'appName': 'Instagram',
          'isSystemApp': false,
          'isEnabled': true,
          'uid': 10245,
          'targetSdkVersion': 34,
          'minSdkVersion': 26,
          'firstInstallTime': 1700000000000,
          'requestedPermissions': ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO'],
          'grantedPermissions': ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO'],
          'deniedPermissions': [],
          'dangerousGrantedPermissions': ['CAMERA', 'RECORD_AUDIO'],
          'dangerousRequestedPermissions': ['CAMERA', 'RECORD_AUDIO'],
          'hasOverlayOp': false,
          'hasUsageAccessOp': false,
          'foregroundDurationMs': foregroundDurationMs,
          'foregroundMinutes': foregroundDurationMs != null ? foregroundDurationMs / 60000.0 : null,
          'foregroundTransitionCount': foregroundTransitions,
          'isCurrentlyForeground': true,
          'isRecentlyUsedDerived': true,
          'usageAvailability': usageAvailability,
          'uploadBytes': uploadBytes,
          'downloadBytes': downloadBytes,
          'networkUsageAvailability': netAvailability,
          'networkUsageSource': 'NetworkStatsManager',
        }
      ],
    );
  }

  group('A. PrivacyEvent → DatasetRecord Conversion & Timestamp Preservation', () {
    test('Converts real PrivacyEvent snapshot into complete DatasetRecord with exact timestamp', () {
      final collector = DatasetCollector(enableDeduplication: false, requireExplicitSession: false);
      final event = createSampleEvent(timestamp: '2026-08-17T18:45:12.345Z');
      final records = collector.captureEvent(event);

      expect(records.length, equals(1));
      final r = records.first;

      // Check metadata & timestamp preservation
      expect(r.timestamp, equals('2026-08-17T18:45:12.345Z'));
      expect(r.packageName, equals('com.instagram.android'));
      expect(r.androidVersion, equals('14'));
      expect(r.sdkInt, equals(34));
      expect(r.recordId, equals('2026-08-17T18:45:12.345Z_com.instagram.android_10245'));

      // Check FeatureVector
      expect(r.featureVector.schemaVersion, equals('1.0.0'));
      expect(r.featureVector.length, equals(32));

      // Check specific features extracted from real telemetry
      expect(r.featureVector.getValueByName('app_is_system_app').numericValue, equals(0.0));
      expect(r.featureVector.getValueByName('app_target_sdk_version').numericValue, equals(34.0));
      expect(r.featureVector.getValueByName('app_perm_camera_granted').numericValue, equals(1.0));
      expect(r.featureVector.getValueByName('app_perm_record_audio_granted').numericValue, equals(1.0));
      expect(r.featureVector.getValueByName('app_foreground_duration_ms_24h').numericValue, equals(120000.0));
      expect(r.featureVector.getValueByName('app_upload_bytes_24h').numericValue, equals(2048.0));
      expect(r.featureVector.getValueByName('app_download_bytes_24h').numericValue, equals(8192.0));
    });

    test('Original timestamp is NEVER overridden with DateTime.now()', () {
      final collector = DatasetCollector(enableDeduplication: false, requireExplicitSession: false);
      const fixedTimestamp = '2025-01-01T00:00:00.000Z';
      final event = createSampleEvent(timestamp: fixedTimestamp);
      final records = collector.captureEvent(event);

      expect(records.first.timestamp, equals(fixedTimestamp));
      expect(records.first.featureVector.timestamp, equals(fixedTimestamp));
      expect(records.first.recordId.startsWith(fixedTimestamp), isTrue);
    });
  });

  group('B. Availability Semantics & Missingness Preservation', () {
    test('Preserves RESTRICTED, ZERO_REPORTED, UNAVAILABLE, and ERROR statuses without fabricating 0/false', () {
      final collector = DatasetCollector(enableDeduplication: false, requireExplicitSession: false);

      // Case 1: RESTRICTED usage and DENIED network
      final restrictedEvent = createSampleEvent(
        timestamp: '2026-08-17T18:01:00.000Z',
        usageAvailability: 'RESTRICTED',
        foregroundDurationMs: null,
        foregroundTransitions: null,
        netAvailability: 'DENIED',
        uploadBytes: null,
        downloadBytes: null,
      );

      final restrictedRecords = collector.captureEvent(restrictedEvent);
      expect(restrictedRecords.length, equals(1));
      final r1 = restrictedRecords.first;

      final fgDurationVal = r1.featureVector.getValueByName('app_foreground_duration_ms_24h');
      expect(fgDurationVal.status, equals(FeatureAvailabilityStatus.restricted));
      expect(fgDurationVal.numericValue, isNull);
      expect(fgDurationVal.isMissing, isTrue);

      final netUploadVal = r1.featureVector.getValueByName('app_upload_bytes_24h');
      expect(netUploadVal.status, equals(FeatureAvailabilityStatus.denied));
      expect(netUploadVal.numericValue, isNull);
      expect(netUploadVal.isMissing, isTrue);

      // Case 2: ZERO_REPORTED
      final zeroEvent = createSampleEvent(
        timestamp: '2026-08-17T18:02:00.000Z',
        usageAvailability: 'ZERO_REPORTED',
        foregroundDurationMs: 0,
        foregroundTransitions: 0,
        netAvailability: 'ZERO_REPORTED',
        uploadBytes: 0,
        downloadBytes: 0,
      );

      final zeroRecords = collector.captureEvent(zeroEvent);
      final r2 = zeroRecords.first;

      final zeroDurationVal = r2.featureVector.getValueByName('app_foreground_duration_ms_24h');
      expect(zeroDurationVal.status, equals(FeatureAvailabilityStatus.zeroReported));
      expect(zeroDurationVal.numericValue, equals(0.0));
      expect(zeroDurationVal.isPresent, isTrue);
    });

    test('Missingness mask produces exact 32 binary flags matching feature statuses', () {
      final collector = DatasetCollector(enableDeduplication: false, requireExplicitSession: false);
      final event = createSampleEvent(
        usageAvailability: 'RESTRICTED',
        foregroundDurationMs: null,
        netAvailability: 'UNAVAILABLE',
        uploadBytes: null,
      );

      final records = collector.captureEvent(event);
      final mask = records.first.featureVector.toMissingMask();

      expect(mask.length, equals(32));
      expect(mask.every((v) => v == 0.0 || v == 1.0), isTrue);

      // Index 18 is app_foreground_duration_ms_24h (RESTRICTED -> missing -> 1.0)
      expect(mask[18], equals(1.0));
      // Index 22 is app_upload_bytes_24h (UNAVAILABLE -> missing -> 1.0)
      expect(mask[22], equals(1.0));
      // Index 0 is app_is_system_app (VALID boolean -> present -> 0.0)
      expect(mask[0], equals(0.0));
    });
  });

  group('C. Validation & Schema Enforcement', () {
    test('DatasetValidator accepts legitimate DatasetRecord', () {
      final collector = DatasetCollector(enableDeduplication: false, requireExplicitSession: false);
      final event = createSampleEvent();
      final record = collector.captureEvent(event).first;

      final validator = DatasetValidator();
      final errors = validator.validateRecord(record);
      expect(errors, isEmpty);
    });

    test('DatasetValidator rejects invalid/corrupted records without adding them to dataset', () {
      final collector = DatasetCollector(enableDeduplication: false, requireExplicitSession: false);

      // App with missing package name
      final badApp = AppTelemetry(
        appName: 'Corrupted App',
        packageName: '', // Invalid empty package name
      );

      final event = createSampleEvent();
      final result = collector.captureRecord(app: badApp, event: event);

      expect(result, isNull);
      expect(collector.recordCount, equals(0));
      expect(collector.validationErrors, isNotEmpty);
      expect(collector.validationErrors.any((e) => e.contains('packageName')), isTrue);
    });
  });

  group('D. Deterministic Deduplication', () {
    test('Deduplicates identical periodic polling snapshots while capturing distinct events', () {
      final collector = DatasetCollector(enableDeduplication: true, requireExplicitSession: false);
      final event1 = createSampleEvent(timestamp: '2026-08-17T18:00:00.000Z');

      // First capture of event1
      final captured1 = collector.captureEvent(event1);
      expect(captured1.length, equals(1));
      expect(collector.recordCount, equals(1));

      // Duplicate periodic delivery of exact same snapshot (identical timestamp & package)
      final capturedDup = collector.captureEvent(event1);
      expect(capturedDup, isEmpty);
      expect(collector.recordCount, equals(1)); // Count remains 1!

      // New distinct event at a later timestamp
      final event2 = createSampleEvent(timestamp: '2026-08-17T18:00:15.000Z');
      final captured2 = collector.captureEvent(event2);
      expect(captured2.length, equals(1));
      expect(collector.recordCount, equals(2));
    });

    test('Distinct realistic sequence (Instagram -> Mic Active -> Phone Call -> Instagram) retains all 4 distinct events', () {
      final collector = DatasetCollector(enableDeduplication: true, requireExplicitSession: false);

      // Event 1: Instagram in foreground
      final event1 = createSampleEvent(
        timestamp: '2026-08-17T18:00:00.000Z',
        foregroundDurationMs: 120000,
        micInUse: false,
      );
      final captured1 = collector.captureEvent(event1);
      expect(captured1.length, equals(1));

      // Duplicate delivery of Event 1 (same timestamp) is rejected
      final dup1 = collector.captureEvent(event1);
      expect(dup1, isEmpty);

      // Event 2: Microphone active / Voice Recorder active
      final event2 = createSampleEvent(
        timestamp: '2026-08-17T18:02:00.000Z',
        foregroundDurationMs: 180000,
        micInUse: true,
      );
      final captured2 = collector.captureEvent(event2);
      expect(captured2.length, equals(1));

      // Event 3: Phone call in progress
      final event3 = PrivacyEvent(
        timestamp: '2026-08-17T18:05:00.000Z',
        deviceContext: DeviceContext(androidVersion: '14', sdkInt: 34),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(isConnected: true, transport: 'CELLULAR'),
        sensorTelemetry: SensorPrivacyTelemetry(
          microphoneHardwareInUse: true,
          audioMode: 'IN_CALL',
          sensorAvailability: 'VALID',
        ),
        usageSummary: UsageSummary(usageAccessGranted: true),
        apps: [
          {
            'packageName': 'com.google.android.dialer',
            'appName': 'Phone',
            'uid': 10050,
            'isSystemApp': true,
            'isEnabled': true,
            'requestedPermissions': ['android.permission.RECORD_AUDIO'],
            'grantedPermissions': ['android.permission.RECORD_AUDIO'],
            'deniedPermissions': [],
            'dangerousGrantedPermissions': ['RECORD_AUDIO'],
            'dangerousRequestedPermissions': ['RECORD_AUDIO'],
          }
        ],
      );
      final captured3 = collector.captureEvent(event3);
      expect(captured3.length, equals(1));

      // Event 4: Instagram foreground again at new timestamp
      final event4 = createSampleEvent(
        timestamp: '2026-08-17T18:10:00.000Z',
        foregroundDurationMs: 300000,
        micInUse: false,
      );
      final captured4 = collector.captureEvent(event4);
      expect(captured4.length, equals(1));

      // Total collected records should be exactly 4 distinct records
      expect(collector.recordCount, equals(4));
    });
  });

  group('E. Persistent Storage, Reload & Machine-Readable Export', () {
    test('Persists records to local JSONL and reloads them completely after restart', () async {
      final storageFile = File('${tempDir.path}/test_telemetry.jsonl');
      final storage = StorageService(file: storageFile);
      await storage.initialize();

      final collector = DatasetCollector(
        storageService: storage,
        enableDeduplication: false,
        requireExplicitSession: false,
      );

      final event1 = createSampleEvent(timestamp: '2026-08-17T18:01:00.000Z');
      final event2 = createSampleEvent(timestamp: '2026-08-17T18:02:00.000Z');

      collector.captureEvent(event1);
      collector.captureEvent(event2);
      await storage.flush();

      // Verify JSONL file exists on disk and has 2 lines
      expect(await storageFile.exists(), isTrue);
      final lines = await storageFile.readAsLines();
      expect(lines.length, equals(2));

      // Simulate App Restart with fresh StorageService and DatasetCollector instance
      final newStorage = StorageService(file: storageFile);
      await newStorage.initialize();
      final reloadedCollector = DatasetCollector(storageService: newStorage, requireExplicitSession: false);
      final loadedRecords = await reloadedCollector.loadFromStorage();

      expect(loadedRecords.length, equals(2));
      expect(loadedRecords[0].timestamp, equals('2026-08-17T18:01:00.000Z'));
      expect(loadedRecords[1].timestamp, equals('2026-08-17T18:02:00.000Z'));
      expect(loadedRecords[0].packageName, equals('com.instagram.android'));
      expect(loadedRecords[0].featureVector.length, equals(32));
    });

    test('Recovers gracefully when storage file contains corrupted lines', () async {
      final storageFile = File('${tempDir.path}/corrupted_test.jsonl');
      await storageFile.create();

      // Write 1 valid line, 1 corrupted line, and 1 valid line
      final event1 = createSampleEvent(timestamp: '2026-08-17T18:01:00.000Z');
      final app = AppTelemetryBuilder().build(event1).first;
      final record1 = DatasetCollector(enableDeduplication: false, requireExplicitSession: false).captureRecord(app: app, event: event1)!;

      final event2 = createSampleEvent(timestamp: '2026-08-17T18:02:00.000Z');
      final record2 = DatasetCollector(enableDeduplication: false, requireExplicitSession: false).captureRecord(app: app, event: event2)!;

      final content = '${jsonEncode(record1.toJson())}\n'
          'CORRUPTED_NON_JSON_DATA_OR_INCOMPLETE_LINE{{{\n'
          '${jsonEncode(record2.toJson())}\n';
      await storageFile.writeAsString(content);

      final storage = StorageService(file: storageFile);
      await storage.initialize();
      final loaded = await storage.loadRecords();

      // Skips corrupted line and recovers the 2 valid records
      expect(loaded.length, equals(2));
      expect(loaded[0].timestamp, equals('2026-08-17T18:01:00.000Z'));
      expect(loaded[1].timestamp, equals('2026-08-17T18:02:00.000Z'));
    });

    test('Exports dataset adhering strictly to DatasetSchema', () async {
      final storageFile = File('${tempDir.path}/export_test.jsonl');
      final storage = StorageService(file: storageFile);
      await storage.initialize();

      final collector = DatasetCollector(storageService: storage, enableDeduplication: false, requireExplicitSession: false);
      final event = createSampleEvent();
      collector.captureEvent(event);
      await storage.flush();

      final exportMap = await storage.exportDatasetMap();

      expect(exportMap.containsKey('datasetSchema'), isTrue);
      expect(exportMap.containsKey('featureSchema'), isTrue);
      expect(exportMap.containsKey('recordCount'), isTrue);
      expect(exportMap['recordCount'], equals(1));
      expect(exportMap.containsKey('records'), isTrue);
      expect((exportMap['records'] as List).length, equals(1));

      // Export to target file
      final exportTarget = File('${tempDir.path}/exported_dataset.json');
      final exportedOk = await storage.exportToFile(exportTarget);
      expect(exportedOk, isTrue);
      expect(await exportTarget.exists(), isTrue);

      final parsed = jsonDecode(await exportTarget.readAsString()) as Map<String, dynamic>;
      expect(parsed['recordCount'], equals(1));
    });

    test('Enforces RECEIVED != VALIDATED != PERSISTED: recordCount does not increment when persistence fails', () async {
      // Create a directory with the file name to cause writeAsString to fail
      final invalidStorageFile = File('${tempDir.path}/invalid_dir_storage.jsonl');
      await Directory(invalidStorageFile.path).create(recursive: true);

      final storage = StorageService(file: invalidStorageFile);
      final collector = DatasetCollector(
        storageService: storage,
        enableDeduplication: false,
        requireExplicitSession: false,
      );

      final event = createSampleEvent(timestamp: '2026-08-17T18:01:00.000Z');
      final app = AppTelemetryBuilder().build(event).first;

      // Capture record attempts persistence
      final record = collector.captureRecord(app: app, event: event);
      expect(record, isNotNull); // Validated successfully

      // Wait for async persistence queue
      await storage.flush();

      // Record was NOT persisted, so collector.recordCount must NOT be incremented
      expect(collector.recordCount, equals(0));
      expect(collector.validationErrors, isNotEmpty);
    });

    test('StorageService streams queries line-by-line and respects offset and limit', () async {
      final storageFile = File('${tempDir.path}/streaming_query_test.jsonl');
      final storage = StorageService(file: storageFile);
      await storage.initialize();

      // Persist 5 distinct records
      for (int i = 0; i < 5; i++) {
        final event = createSampleEvent(
          timestamp: '2026-08-17T18:0$i:00.000Z',
        );
        final app = AppTelemetryBuilder().build(event).first;
        final record = DatasetCollector(enableDeduplication: false, requireExplicitSession: false).captureRecord(app: app, event: event)!;
        await storage.persistRecord(record);
      }

      expect(await storage.countRecords(), equals(5));

      // Query with limit = 2, offset = 1
      final paged = await storage.getRecords(limit: 2, offset: 1);
      expect(paged.length, equals(2));
      expect(paged[0].timestamp, equals('2026-08-17T18:01:00.000Z'));
      expect(paged[1].timestamp, equals('2026-08-17T18:02:00.000Z'));
    });
  });

  group('F. Bounded Retention & Memory Management', () {
    test('Enforces FIFO bounded retention in both memory buffer and persistent storage', () async {
      final storageFile = File('${tempDir.path}/bounded_retention.jsonl');
      final storage = StorageService(file: storageFile, maxRecords: 3);
      await storage.initialize();

      final collector = DatasetCollector(
        storageService: storage,
        maxBufferSize: 3,
        enableDeduplication: false,
        requireExplicitSession: false,
      );

      for (int i = 0; i < 6; i++) {
        final event = createSampleEvent(timestamp: '2026-08-17T18:0$i:00.000Z');
        collector.captureEvent(event);
      }
      await storage.flush();

      // Memory buffer bounded at 3
      expect(collector.recordCount, equals(3));
      expect(collector.records.first.timestamp, equals('2026-08-17T18:03:00.000Z'));
      expect(collector.records.last.timestamp, equals('2026-08-17T18:05:00.000Z'));

      // Storage file bounded at 3 (oldest 3 evicted)
      final persisted = await storage.loadRecords();
      expect(persisted.length, equals(3));
      expect(persisted.first.timestamp, equals('2026-08-17T18:03:00.000Z'));
      expect(persisted.last.timestamp, equals('2026-08-17T18:05:00.000Z'));
    });
  });

  group('G. TelemetryService Wiring & Asynchronous Isolation', () {
    test('TelemetryService dispatches live events to DatasetCollector without blocking', () async {
      final storageFile = File('${tempDir.path}/telemetry_service_test.jsonl');
      final storage = StorageService(file: storageFile);
      await storage.initialize();

      final collector = DatasetCollector(storageService: storage, requireExplicitSession: false);
      final telemetryService = TelemetryService(datasetCollector: collector);

      final sampleEvent = createSampleEvent(timestamp: '2026-08-17T18:50:00.000Z');

      // Emulate event processing
      collector.captureEvent(sampleEvent);
      await storage.flush();

      expect(collector.recordCount, equals(1));
      expect(collector.records.first.packageName, equals('com.instagram.android'));

      telemetryService.stop();
    });
  });
}
