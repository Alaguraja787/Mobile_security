import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/phase2/dataset/dataset_collector.dart';
import 'package:mobile_privacy_security_project/screens/dataset/dataset_viewer_screen.dart';
import 'package:mobile_privacy_security_project/screens/dataset/record_detail_screen.dart';
import 'package:mobile_privacy_security_project/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dataset_viewer_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PrivacyEvent createMockEvent({
    required String timestamp,
    required String packageName,
    String appName = 'Test App',
    bool micInUse = false,
    bool camInUse = false,
    bool isForeground = false,
    int uploadBytes = 0,
    int downloadBytes = 0,
    int uid = 10001,
  }) {
    return PrivacyEvent(
      timestamp: timestamp,
      deviceContext: DeviceContext(
        manufacturer: 'Google',
        model: 'Pixel 6',
        brand: 'google',
        device: 'oriole',
        board: 'oriole',
        hardware: 'tensor',
        androidVersion: '14',
        sdkInt: 34,
        screenOn: true,
        screenLocked: false,
        isDeviceSecure: true,
        batteryPercent: 85,
        isCharging: false,
      ),
      securityContext: SecurityContext(
        developerOptionsEnabled: false,
        adbEnabled: false,
      ),
      network: NetworkTelemetry(
        isConnected: true,
        transport: 'WIFI',
        deviceTotalTxBytes: uploadBytes,
        deviceTotalRxBytes: downloadBytes,
      ),
      sensorTelemetry: SensorPrivacyTelemetry(
        microphoneHardwareInUse: micInUse,
        cameraHardwareInUse: camInUse,
        activeAudioRecordingsCount: micInUse ? 1 : 0,
        sensorAvailability: 'VALID',
      ),
      usageSummary: UsageSummary(
        usageAccessGranted: true,
        availability: 'VALID',
        currentForegroundApp: isForeground ? packageName : null,
      ),
      apps: [
        {
          'packageName': packageName,
          'appName': appName,
          'uid': uid,
          'isSystemApp': false,
          'isEnabled': true,
          'targetSdkVersion': 34,
          'minSdkVersion': 26,
          'isCurrentlyForeground': isForeground,
          'uploadBytes': uploadBytes,
          'downloadBytes': downloadBytes,
          'requestedPermissions': ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO'],
          'grantedPermissions': ['android.permission.CAMERA'],
          'deniedPermissions': ['android.permission.RECORD_AUDIO'],
          'dangerousGrantedPermissions': ['CAMERA'],
          'dangerousRequestedPermissions': ['CAMERA', 'RECORD_AUDIO'],
          'usageAvailability': 'VALID',
          'networkUsageAvailability': 'VALID',
        }
      ],
    );
  }

  group('StorageService Advanced Querying & Aggregation', () {
    test('Queries records with pagination and multi-criteria filters', () async {
      final file = File('${tempDir.path}/viewer_storage.jsonl');
      final storage = StorageService(file: file);
      await storage.initialize();

      final collector = DatasetCollector(
        storageService: storage,
        enableDeduplication: false,
      );

      // Session 1: Instagram (foreground + network)
      collector.startCollection(sessionId: 'session_insta');
      collector.captureEvent(createMockEvent(
        timestamp: '2026-08-18T10:00:00.000Z',
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        isForeground: true,
        uploadBytes: 4096,
        downloadBytes: 16384,
      ));
      collector.captureEvent(createMockEvent(
        timestamp: '2026-08-18T10:01:00.000Z',
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        isForeground: true,
        camInUse: true,
        uploadBytes: 8192,
        downloadBytes: 32768,
      ));
      await collector.stopCollection();

      // Session 2: Voice Recorder (mic in use)
      collector.startCollection(sessionId: 'session_recorder');
      collector.captureEvent(createMockEvent(
        timestamp: '2026-08-18T10:05:00.000Z',
        packageName: 'com.google.android.soundrecorder',
        appName: 'Recorder',
        micInUse: true,
        isForeground: true,
      ));
      collector.captureEvent(createMockEvent(
        timestamp: '2026-08-18T10:06:00.000Z',
        packageName: 'com.google.android.dialer',
        appName: 'Phone',
        micInUse: true,
        isForeground: false,
      ));
      await collector.stopCollection();

      // Total count across all sessions
      final total = await storage.countRecords();
      expect(total, equals(4));

      // Pagination: limit 2, offset 0
      final page1 = await storage.getRecords(limit: 2, offset: 0);
      expect(page1.length, equals(2));
      expect(page1[0].packageName, equals('com.instagram.android'));

      // Pagination: limit 2, offset 2
      final page2 = await storage.getRecords(limit: 2, offset: 2);
      expect(page2.length, equals(2));
      expect(page2[0].packageName, equals('com.google.android.soundrecorder'));

      // Session filter
      final instaRecords = await storage.getRecords(sessionId: 'session_insta');
      expect(instaRecords.length, equals(2));
      expect(instaRecords.every((r) => r.sessionId == 'session_insta'), isTrue);

      // Package query search
      final searchRecorder = await storage.getRecords(packageNameQuery: 'soundrecorder');
      expect(searchRecorder.length, equals(1));
      expect(searchRecorder.first.packageName, equals('com.google.android.soundrecorder'));

      // Mic activity filter
      final micRecords = await storage.getRecords(hasMicActivity: true);
      expect(micRecords.length, equals(2));

      // Camera activity filter
      final camRecords = await storage.getRecords(hasCameraActivity: true);
      expect(camRecords.length, equals(1));
      expect(camRecords.first.packageName, equals('com.instagram.android'));

      // Available packages list
      final packages = await storage.getAvailablePackages();
      expect(packages, containsAll([
        'com.instagram.android',
        'com.google.android.soundrecorder',
        'com.google.android.dialer',
      ]));
    });

    test('Calculates accurate real summary statistics from persisted records', () async {
      final file = File('${tempDir.path}/summary_storage.jsonl');
      final storage = StorageService(file: file);
      await storage.initialize();

      final collector = DatasetCollector(
        storageService: storage,
        enableDeduplication: false,
      );

      collector.startCollection(sessionId: 'test_session_stats');
      // 1. Instagram with Camera
      collector.captureEvent(createMockEvent(
        timestamp: '2026-08-18T12:00:00.000Z',
        packageName: 'com.instagram.android',
        camInUse: true,
        isForeground: true,
        uploadBytes: 1000,
        downloadBytes: 2000,
      ));
      // 2. Sound Recorder with Mic
      collector.captureEvent(createMockEvent(
        timestamp: '2026-08-18T12:05:00.000Z',
        packageName: 'com.google.android.soundrecorder',
        micInUse: true,
        isForeground: true,
      ));
      await collector.stopCollection();

      final summary = await storage.getSessionSummaryDetails(sessionId: 'test_session_stats');

      expect(summary['recordCount'], equals(2));
      expect(summary['firstTimestamp'], equals('2026-08-18T12:00:00.000Z'));
      expect(summary['lastTimestamp'], equals('2026-08-18T12:05:00.000Z'));
      expect(summary['durationSeconds'], equals(300)); // 5 minutes difference
      expect(summary['micActiveRecords'], equals(1));
      expect(summary['cameraActiveRecords'], equals(1));
      expect(summary['foregroundRecords'], equals(2));
      expect(summary['networkActiveRecords'], equals(1));
      expect(summary['uniquePackages'], containsAll(['com.instagram.android', 'com.google.android.soundrecorder']));
      expect(summary['availabilityBreakdown']['VALID'], greaterThan(0));
    });
  });

  group('Dataset Viewer Widgets & Navigation Tests', () {
    testWidgets('DatasetViewerScreen renders records tab, summary tab, and sessions tab',
        (tester) async {
      await tester.runAsync(() async {
        final file = File('${tempDir.path}/ui_test.jsonl');
        final storage = StorageService(file: file);
        await storage.initialize();

        final collector = DatasetCollector(
          storageService: storage,
          enableDeduplication: false,
          requireExplicitSession: false,
        );

        collector.startCollection(sessionId: 'session_ui_test');
        collector.captureEvent(createMockEvent(
          timestamp: '2026-08-18T14:00:00.000Z',
          packageName: 'com.instagram.android',
          appName: 'Instagram',
          isForeground: true,
          uploadBytes: 5000,
        ));
        await storage.flush();
        await collector.stopCollection();

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: DatasetViewerScreen(
              storage: storage,
              collector: collector,
              enableLiveTicker: false,
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();

        // Verify Screen Title and Tabs
        expect(find.text('Dataset Viewer'), findsOneWidget);
        expect(find.textContaining('Records'), findsOneWidget);
        expect(find.text('Summary'), findsOneWidget);
        expect(find.text('Sessions (1)'), findsOneWidget);

        // Verify Persisted Record is displayed in the list
        expect(find.textContaining('com.instagram.android'), findsOneWidget);
        expect(find.text('FOREGROUND'), findsOneWidget);

        // Cleanly unmount
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    });

    testWidgets('RecordDetailScreen accurately renders availability statuses',
        (tester) async {
      await tester.runAsync(() async {
        final file = File('${tempDir.path}/detail_test.jsonl');
        final storage = StorageService(file: file);
        await storage.initialize();

        final collector = DatasetCollector(
          storageService: storage,
          enableDeduplication: false,
          requireExplicitSession: false,
        );

        collector.startCollection(sessionId: 'detail_session');
        final record = collector.captureRecord(
          app: collector.telemetryBuilder.build(createMockEvent(
            timestamp: '2026-08-18T15:00:00.000Z',
            packageName: 'com.whatsapp',
            appName: 'WhatsApp',
            micInUse: true,
          )).first,
          event: createMockEvent(
            timestamp: '2026-08-18T15:00:00.000Z',
            packageName: 'com.whatsapp',
            micInUse: true,
          ),
        );
        await collector.stopCollection();

        expect(record, isNotNull);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: RecordDetailScreen(record: record!),
          ),
        );
        await tester.pump();

        expect(find.text('Device Context'), findsOneWidget);
        expect(find.text('Pixel 6'), findsOneWidget);
        expect(find.text('com.whatsapp'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    });
  });
}
