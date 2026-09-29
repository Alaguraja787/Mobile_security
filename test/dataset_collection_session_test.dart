import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/phase2/dataset/collection_session.dart';
import 'package:mobile_privacy_security_project/phase2/dataset/dataset_collector.dart';
import 'package:mobile_privacy_security_project/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  PrivacyEvent createSampleEvent({
    required String timestamp,
    String packageName = 'com.instagram.android',
    int uid = 10245,
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
      ),
      securityContext: SecurityContext(),
      network: NetworkTelemetry(),
      sensorTelemetry: SensorPrivacyTelemetry(),
      usageSummary: UsageSummary(
        usageAccessGranted: true,
        availability: 'VALID',
        totalForegroundTransitions: 5,
        totalForegroundDurationMs: 60000,
      ),
      apps: [
        {
          'packageName': packageName,
          'appName': 'Test App',
          'isSystemApp': false,
          'isEnabled': true,
          'uid': uid,
          'targetSdkVersion': 34,
          'minSdkVersion': 26,
          'firstInstallTime': 1700000000000,
          'requestedPermissions': ['android.permission.CAMERA'],
          'grantedPermissions': ['android.permission.CAMERA'],
          'deniedPermissions': [],
          'dangerousGrantedPermissions': ['CAMERA'],
          'dangerousRequestedPermissions': ['CAMERA'],
          'hasOverlayOp': false,
          'hasUsageAccessOp': false,
          'foregroundDurationMs': 60000,
          'foregroundTransitionCount': 5,
          'isCurrentlyForeground': true,
          'isRecentlyUsedDerived': true,
          'usageAvailability': 'VALID',
          'uploadBytes': 1024,
          'downloadBytes': 4096,
          'networkUsageAvailability': 'VALID',
          'networkUsageSource': 'NetworkStatsManager',
        }
      ],
    );
  }

  group('Session Lifecycle & Event Filtering', () {
    test('Collector starts in NOT_COLLECTING and ignores events when requireExplicitSession is true', () async {
      final storageFile = File('${tempDir.path}/lifecycle_test.jsonl');
      final storage = StorageService(file: storageFile);
      await storage.initialize();

      final collector = DatasetCollector(
        storageService: storage,
        requireExplicitSession: true,
        enableDeduplication: false,
      );

      expect(collector.state, equals(CollectionState.notCollecting));
      expect(collector.isCollecting, isFalse);

      // Event arrives while NOT_COLLECTING -> must NOT be captured
      final event1 = createSampleEvent(timestamp: '2026-08-17T19:00:00.000Z');
      final captured1 = collector.captureEvent(event1);

      expect(captured1, isEmpty);
      expect(collector.recordCount, equals(0));

      // Start Session
      final session = collector.startCollection(sessionName: 'Physical Test Session 1');
      expect(collector.state, equals(CollectionState.collecting));
      expect(collector.isCollecting, isTrue);
      expect(session.sessionId.startsWith('session_'), isTrue);

      // Event arrives while COLLECTING -> must be captured & tagged with sessionId
      final event2 = createSampleEvent(timestamp: '2026-08-17T19:01:00.000Z');
      final captured2 = collector.captureEvent(event2);
      await collector.flush();

      expect(captured2.length, equals(1));
      expect(collector.recordCount, equals(1));
      expect(captured2.first.sessionId, equals(session.sessionId));

      // Stop Session
      final stoppedSession = await collector.stopCollection();
      expect(collector.state, equals(CollectionState.stopped));
      expect(collector.isCollecting, isFalse);
      expect(stoppedSession?.stopTime, isNotNull);

      // Event arrives after STOPPED -> must NOT be captured
      final event3 = createSampleEvent(timestamp: '2026-08-17T19:02:00.000Z');
      final captured3 = collector.captureEvent(event3);
      await collector.flush();
      expect(captured3, isEmpty);
      expect(collector.recordCount, equals(1));
    });
  });

  group('Historical Streaming Queries & Session Summaries', () {
    test('Queries records by sessionId and timestamp range without loading entire file', () async {
      final storageFile = File('${tempDir.path}/queries_test.jsonl');
      final storage = StorageService(file: storageFile);
      await storage.initialize();

      final collector = DatasetCollector(
        storageService: storage,
        enableDeduplication: false,
      );

      // Session A records
      collector.startCollection(sessionId: 'session_alpha', sessionName: 'Alpha');
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:01:00.000Z'));
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:02:00.000Z'));
      await collector.stopCollection();

      // Session B records
      collector.startCollection(sessionId: 'session_beta', sessionName: 'Beta');
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:03:00.000Z'));
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:04:00.000Z'));
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:05:00.000Z'));
      await collector.stopCollection();

      // Query by session
      final alphaRecords = await storage.getRecords(sessionId: 'session_alpha');
      expect(alphaRecords.length, equals(2));
      expect(alphaRecords.every((r) => r.sessionId == 'session_alpha'), isTrue);

      final betaRecords = await storage.getRecords(sessionId: 'session_beta');
      expect(betaRecords.length, equals(3));
      expect(betaRecords.every((r) => r.sessionId == 'session_beta'), isTrue);

      // Pagination query (limit 2, offset 1 on Session B)
      final paginated = await storage.getRecords(sessionId: 'session_beta', limit: 2, offset: 1);
      expect(paginated.length, equals(2));
      expect(paginated[0].timestamp, equals('2026-08-17T19:04:00.000Z'));

      // Session summaries
      final summaries = await storage.getSessionSummaries();
      expect(summaries.length, equals(2));
      final alphaSummary = summaries.firstWhere((s) => s['sessionId'] == 'session_alpha');
      expect(alphaSummary['recordCount'], equals(2));
      final betaSummary = summaries.firstWhere((s) => s['sessionId'] == 'session_beta');
      expect(betaSummary['recordCount'], equals(3));
    });

    test('Deletes specific session records without modifying other sessions', () async {
      final storageFile = File('${tempDir.path}/delete_session_test.jsonl');
      final storage = StorageService(file: storageFile);
      await storage.initialize();

      final collector = DatasetCollector(storageService: storage, enableDeduplication: false);

      collector.startCollection(sessionId: 'session_to_keep');
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:01:00.000Z'));
      await collector.stopCollection();

      collector.startCollection(sessionId: 'session_to_delete');
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:02:00.000Z'));
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:03:00.000Z'));
      await collector.stopCollection();

      expect(storage.cachedRecordCount, equals(3));

      // Delete session_to_delete
      final deleted = await storage.deleteSession('session_to_delete');
      expect(deleted, equals(2));
      expect(storage.cachedRecordCount, equals(1));

      final remaining = await storage.loadRecords();
      expect(remaining.length, equals(1));
      expect(remaining.first.sessionId, equals('session_to_keep'));
    });
  });

  group('Session-Filtered Export & Bounded Storage Bytes', () {
    test('Exports single session to target file adhering to DatasetSchema', () async {
      final storageFile = File('${tempDir.path}/export_session_test.jsonl');
      final storage = StorageService(file: storageFile);
      await storage.initialize();

      final collector = DatasetCollector(storageService: storage, enableDeduplication: false);

      collector.startCollection(sessionId: 'session_export_target');
      collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:10:00.000Z'));
      await collector.stopCollection();

      final exportFile = File('${tempDir.path}/session_exported.json');
      final exported = await collector.exportSessionToFile('session_export_target', exportFile);

      expect(exported, isTrue);
      expect(await exportFile.exists(), isTrue);

      final content = jsonDecode(await exportFile.readAsString()) as Map<String, dynamic>;
      expect(content['sessionId'], equals('session_export_target'));
      expect(content['recordCount'], equals(1));
      expect(content.containsKey('datasetSchema'), isTrue);
      expect(content.containsKey('featureSchema'), isTrue);
    });

    test('Enforces byte-bounded retention limits with FIFO oldest-record pruning', () async {
      final storageFile = File('${tempDir.path}/byte_limit_test.jsonl');
      // Set a strict 15 KB storage limit (each rich telemetry record is ~4.5 KB)
      final storage = StorageService(
        file: storageFile,
        maxStorageBytes: 15 * 1024,
        maxRecords: 1000,
      );
      await storage.initialize();

      final collector = DatasetCollector(
        storageService: storage,
        enableDeduplication: false,
        requireExplicitSession: false,
      );

      // Write 20 records
      for (int i = 0; i < 20; i++) {
        final sec = i.toString().padLeft(2, '0');
        collector.captureEvent(createSampleEvent(timestamp: '2026-08-17T19:20:$sec.000Z'));
      }
      await storage.flush();

      final fileSize = await storage.getStorageSizeBytes();
      expect(fileSize <= 15 * 1024, isTrue);

      // Verify file is still valid JSONL and has oldest records evicted
      final records = await storage.loadRecords();
      expect(records.isNotEmpty, isTrue);
      expect(records.length < 20, isTrue);
      expect(records.last.timestamp, equals('2026-08-17T19:20:19.000Z'));
    });
  });
}
