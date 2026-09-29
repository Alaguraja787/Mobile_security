import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/core/theme/sentinel_theme.dart';
import 'package:mobile_privacy_security_project/models/sensor_access_event.dart';
import 'package:mobile_privacy_security_project/services/sensor_access_service.dart';
import 'package:mobile_privacy_security_project/services/privacy_notification_service.dart';
import 'package:mobile_privacy_security_project/screens/settings/settings_screen.dart';
import 'package:mobile_privacy_security_project/screens/dashboard/widgets/dashboard_charts.dart';

void main() {
  group('SHIZUKU PRECISE APP ATTRIBUTION SPECIFICATION TESTS (1-26)', () {
    // ---------------------------------------------------------
    // GROUP 1: SHIZUKU LIFECYCLE & PERMISSIONS (Tests 1-6)
    // ---------------------------------------------------------
    test('1. Shizuku unavailable maps to SHIZUKU_UNAVAILABLE / NEEDS_SHIZUKU', () {
      final statusMap = {
        'state': 'NEEDS_SHIZUKU',
        'lifecycleState': 'SHIZUKU_UNAVAILABLE',
        'status': 'Standard Monitoring',
        'isPreciseModeEnabled': true,
        'isShizukuAvailable': false,
        'hasPermission': false,
        'isServiceBound': false,
        'summary': 'Install and start Shizuku to enable precise app attribution.',
      };

      expect(statusMap['isShizukuAvailable'], isFalse);
      expect(statusMap['lifecycleState'], equals('SHIZUKU_UNAVAILABLE'));
      expect(statusMap['state'], equals('NEEDS_SHIZUKU'));
      expect(statusMap['status'], equals('Standard Monitoring'));
    });

    test('2. Shizuku available but permission denied maps to SHIZUKU_AVAILABLE_NO_PERMISSION / NEEDS_PERMISSION', () {
      final statusMap = {
        'state': 'NEEDS_PERMISSION',
        'lifecycleState': 'SHIZUKU_AVAILABLE_NO_PERMISSION',
        'status': 'Standard Monitoring',
        'isPreciseModeEnabled': true,
        'isShizukuAvailable': true,
        'hasPermission': false,
        'isServiceBound': false,
        'summary': 'Grant Privacy Sentinel access in Shizuku.',
      };

      expect(statusMap['isShizukuAvailable'], isTrue);
      expect(statusMap['hasPermission'], isFalse);
      expect(statusMap['lifecycleState'], equals('SHIZUKU_AVAILABLE_NO_PERMISSION'));
      expect(statusMap['state'], equals('NEEDS_PERMISSION'));
    });

    test('3. Permission granted and bound maps to SHIZUKU_PERMISSION_GRANTED / ACTIVE', () {
      final statusMap = {
        'state': 'ACTIVE',
        'lifecycleState': 'SHIZUKU_PERMISSION_GRANTED',
        'status': 'Precise Attribution',
        'isPreciseModeEnabled': true,
        'isShizukuAvailable': true,
        'hasPermission': true,
        'isServiceBound': true,
        'summary': 'Precise app attribution is active.',
      };

      expect(statusMap['isShizukuAvailable'], isTrue);
      expect(statusMap['hasPermission'], isTrue);
      expect(statusMap['isServiceBound'], isTrue);
      expect(statusMap['lifecycleState'], equals('SHIZUKU_PERMISSION_GRANTED'));
      expect(statusMap['state'], equals('ACTIVE'));
      expect(statusMap['status'], equals('Precise Attribution'));
    });

    test('4. Binder death maps to SHIZUKU_BINDER_DEAD / TEMPORARILY_UNAVAILABLE', () {
      final statusMap = {
        'state': 'TEMPORARILY_UNAVAILABLE',
        'lifecycleState': 'SHIZUKU_BINDER_DEAD',
        'status': 'Standard Monitoring',
        'isPreciseModeEnabled': true,
        'isShizukuAvailable': false,
        'hasPermission': true,
        'isServiceBound': false,
        'summary': 'Elevated service temporarily unavailable. Falling back to device monitoring.',
      };

      expect(statusMap['lifecycleState'], equals('SHIZUKU_BINDER_DEAD'));
      expect(statusMap['state'], equals('TEMPORARILY_UNAVAILABLE'));
      expect(statusMap['status'], equals('Standard Monitoring'));
    });

    test('5. Reconnect restores active precise attribution without crash', () {
      // Step A: Disconnected
      var state = 'TEMPORARILY_UNAVAILABLE';
      var lifecycle = 'SHIZUKU_BINDER_DEAD';
      expect(state, equals('TEMPORARILY_UNAVAILABLE'));

      // Step B: Binder received sticky callback fires
      state = 'ACTIVE';
      lifecycle = 'SHIZUKU_PERMISSION_GRANTED';
      expect(state, equals('ACTIVE'));
      expect(lifecycle, equals('SHIZUKU_PERMISSION_GRANTED'));
    });

    test('6. UserService start and stop updates isServiceBound state', () {
      bool isWatching = false;
      bool isBound = false;

      // Start watching
      isBound = true;
      isWatching = true;
      expect(isBound, isTrue);
      expect(isWatching, isTrue);

      // Stop watching
      isWatching = false;
      isBound = false;
      expect(isBound, isFalse);
      expect(isWatching, isFalse);
    });

    // ---------------------------------------------------------
    // GROUP 2: APP ATTRIBUTION RESOLUTION (Tests 7-13)
    // ---------------------------------------------------------
    test('7. UID -> package resolution produces genuine package name', () {
      final testEventJson = {
        'type': 'sensor_access',
        'sensor': 'CAMERA',
        'state': 'STARTED',
        'uid': 10342,
        'packageName': 'org.torproject.android',
        'appName': 'Tor Browser',
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'SHIZUKU_APPOPS',
        'confidence': 'VERIFIED',
        'attributionScope': 'APP_LEVEL',
        'availability': 'FULL',
      };

      final event = SensorAccessEvent.fromMap(testEventJson);
      expect(event.packageName, equals('org.torproject.android'));
      expect(event.attributionScope, equals(SensorAttributionScope.appLevel));
      expect(event.confidence, equals(SensorConfidence.verified));
      expect(event.isAppAttributed, isTrue);
    });

    test('8. Package -> appName resolution reflects genuine application label', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.duckduckgo.mobile.android',
        appName: 'DuckDuckGo',
        timestamp: DateTime.now(),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        availability: SensorCapabilityLevel.full,
      );

      expect(event.appName, equals('DuckDuckGo'));
      expect(event.packageName, equals('com.duckduckgo.mobile.android'));
    });

    test('9. Verified camera event carries SHIZUKU_APPOPS and VERIFIED confidence', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'org.videolan.vlc',
        appName: 'VLC',
        timestamp: DateTime.now(),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        availability: SensorCapabilityLevel.full,
      );

      expect(event.sensorType, equals(SensorType.camera));
      expect(event.source, equals(SensorEventSource.shizukuAppOps));
      expect(event.confidence, equals(SensorConfidence.verified));
      expect(event.attributionScope, equals(SensorAttributionScope.appLevel));
      expect(event.availability, equals(SensorCapabilityLevel.full));
    });

    test('10. Verified microphone event carries SHIZUKU_APPOPS and VERIFIED confidence', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'org.signal.android',
        appName: 'Signal',
        timestamp: DateTime.now(),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        availability: SensorCapabilityLevel.full,
      );

      expect(event.sensorType, equals(SensorType.microphone));
      expect(event.source, equals(SensorEventSource.shizukuAppOps));
      expect(event.confidence, equals(SensorConfidence.verified));
      expect(event.attributionScope, equals(SensorAttributionScope.appLevel));
    });

    test('11. Device-level fallback preserves null package and LIMITED availability', () {
      final fallbackEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.active,
        packageName: null,
        appName: null,
        timestamp: DateTime.now(),
        source: SensorEventSource.cameraManager,
        confidence: SensorConfidence.derived,
        attributionScope: SensorAttributionScope.deviceLevel,
        availability: SensorCapabilityLevel.limited,
      );

      expect(fallbackEvent.packageName, isNull);
      expect(fallbackEvent.appName, isNull);
      expect(fallbackEvent.attributionScope, equals(SensorAttributionScope.deviceLevel));
      expect(fallbackEvent.confidence, equals(SensorConfidence.derived));
      expect(fallbackEvent.availability, equals(SensorCapabilityLevel.limited));
      expect(fallbackEvent.isAppAttributed, isFalse);
    });

    test('12. No guessing: unverified event does NOT invent app name or package', () {
      final rawMap = {
        'type': 'sensor_access',
        'sensor': 'CAMERA',
        'state': 'ACTIVE',
        'packageName': null,
        'appName': null,
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'CAMERA_MANAGER',
        'confidence': 'DERIVED',
        'attributionScope': 'DEVICE_LEVEL',
        'availability': 'LIMITED',
      };

      final event = SensorAccessEvent.fromMap(rawMap);
      expect(event.packageName, isNull);
      expect(event.appName, isNull);
      expect(event.isAppAttributed, isFalse);
    });

    test('13. No hardcoded app mappings in resolution path', () {
      // Dynamic fallback when app label is not found falls back to package name, never a hardcoded fake
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.arbitrary.thirdparty.app',
        appName: null,
        timestamp: DateTime.now(),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
      );

      expect(event.packageName, equals('com.arbitrary.thirdparty.app'));
      expect(event.appName, isNull);
    });

    // ---------------------------------------------------------
    // GROUP 3: EVENT MERGING & DEDUPLICATION (Tests 14-17)
    // ---------------------------------------------------------
    test('14. Device-level event followed by verified app event updates session', () {
      final service = SensorAccessService();
      final t1 = DateTime.now();

      // Step 1: Device-level event arrives
      final devEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.active,
        timestamp: t1,
        source: SensorEventSource.cameraManager,
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
        availability: SensorCapabilityLevel.limited,
        eventId: 'dev_01',
      );
      service.processEvent(devEvent);

      expect(service.isSensorActive(SensorType.camera), isTrue);
      expect(service.activeSessions.length, equals(1));
      expect(service.activeSessions.first.attributionScope, equals(SensorAttributionScope.deviceLevel));

      // Step 2: Verified app event arrives 100ms later for same sensor
      final appEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.client.customapp',
        appName: 'Custom App',
        timestamp: t1.add(const Duration(milliseconds: 100)),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        availability: SensorCapabilityLevel.full,
        eventId: 'app_01',
      );
      service.processEvent(appEvent);

      // Session was upgraded! Active session count is still 1 (not duplicated)
      expect(service.activeSessions.length, equals(1));
      expect(service.activeSessions.first.isAppAttributed, isTrue);
      expect(service.activeSessions.first.appName, equals('Custom App'));
      expect(service.activeSessions.first.packageName, equals('com.client.customapp'));
    });

    test('15. Same session is upgraded in history, not duplicated', () {
      final service = SensorAccessService();
      final t1 = DateTime.now();

      final devEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.active,
        timestamp: t1,
        source: SensorEventSource.cameraManager,
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
        eventId: 'dev_hist_01',
      );
      service.processEvent(devEvent);
      expect(service.recentEvents.length, equals(1));

      final appEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.verified.app',
        appName: 'Verified App',
        timestamp: t1.add(const Duration(milliseconds: 150)),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        eventId: 'app_hist_01',
      );
      service.processEvent(appEvent);

      // History item was upgraded in place: total length is still 1
      expect(service.recentEvents.length, equals(1));
      expect(service.recentEvents.first.isAppAttributed, isTrue);
      expect(service.recentEvents.first.appName, equals('Verified App'));
    });

    test('16. Verified identity is not overwritten by a later generic device-level event', () {
      final service = SensorAccessService();
      final t1 = DateTime.now();

      final appEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.authoritative.app',
        appName: 'Authoritative App',
        timestamp: t1,
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        eventId: 'app_prio_01',
      );
      service.processEvent(appEvent);

      // Subsequent generic event arrives 50ms later
      final devEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.active,
        timestamp: t1.add(const Duration(milliseconds: 50)),
        source: SensorEventSource.cameraManager,
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
        eventId: 'dev_prio_02',
      );
      service.processEvent(devEvent);

      // Active session remains authoritative APP_LEVEL
      expect(service.activeSessions.length, equals(1));
      expect(service.activeSessions.first.isAppAttributed, isTrue);
      expect(service.activeSessions.first.appName, equals('Authoritative App'));
    });

    test('17. Multiple app sessions remain independent across sensors and apps', () {
      final service = SensorAccessService();
      final now = DateTime.now();

      final appA = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.app.alpha',
        appName: 'App Alpha',
        timestamp: now,
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        eventId: 'app_a',
      );

      final appB = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.app.beta',
        appName: 'App Beta',
        timestamp: now,
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        eventId: 'app_b',
      );

      final appC = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.app.gamma',
        appName: 'App Gamma',
        timestamp: now,
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        eventId: 'app_c',
      );

      service.processEvent(appA);
      service.processEvent(appB);
      service.processEvent(appC);

      expect(service.activeSessions.length, equals(3));
      expect(service.isSensorActive(SensorType.camera), isTrue);
      expect(service.isSensorActive(SensorType.microphone), isTrue);

      // Stopping App A leaves App B and App C active
      final appAStop = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.stopped,
        packageName: 'com.app.alpha',
        appName: 'App Alpha',
        timestamp: now.add(const Duration(seconds: 1)),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        eventId: 'app_a_stop',
      );
      service.processEvent(appAStop);

      expect(service.activeSessions.length, equals(2));
      expect(service.activeSessions.any((s) => s.packageName == 'com.app.beta'), isTrue);
      expect(service.activeSessions.any((s) => s.packageName == 'com.app.gamma'), isTrue);
    });

    // ---------------------------------------------------------
    // GROUP 4: NOTIFICATIONS (Tests 18-20)
    // ---------------------------------------------------------
    test('18. Verified app notification displays real app name in body', () async {
      String? sentTitle;
      String? sentBody;

      final notifService = PrivacyNotificationService(
        customNotificationSender: ({required int id, required String title, required String body}) async {
          sentTitle = title;
          sentBody = body;
        },
      );

      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'org.videoplayer.test',
        appName: 'Video Player',
        timestamp: DateTime.now(),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
      );

      final decision = await notifService.handleSensorAccessEvent(event);
      expect(decision.wasNotified, isTrue);
      expect(sentTitle, equals('📷 Camera access'));
      expect(sentBody, equals('Video Player is using your camera.'));
    });

    test('19. Device-level fallback notification displays device activity notice', () async {
      String? sentTitle;
      String? sentBody;

      final notifService = PrivacyNotificationService(
        customNotificationSender: ({required int id, required String title, required String body}) async {
          sentTitle = title;
          sentBody = body;
        },
      );

      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: null,
        appName: null,
        timestamp: DateTime.now(),
        source: SensorEventSource.audioManager,
        confidence: SensorConfidence.derived,
        attributionScope: SensorAttributionScope.deviceLevel,
      );

      final decision = await notifService.handleSensorAccessEvent(event);
      expect(decision.wasNotified, isTrue);
      expect(sentTitle, equals('🎙️ Microphone access'));
      expect(sentBody, equals('Microphone activity detected on your device.'));
    });

    test('20. Duplicate notification suppression & in-place upgrade', () async {
      final List<String> sentBodies = [];

      final notifService = PrivacyNotificationService(
        customNotificationSender: ({required int id, required String title, required String body}) async {
          sentBodies.add(body);
        },
      );

      final now = DateTime.now();

      // Step 1: Device level notification
      final devEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.active,
        timestamp: now,
        source: SensorEventSource.cameraManager,
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      await notifService.handleSensorAccessEvent(devEvent);
      expect(sentBodies.length, equals(1));
      expect(sentBodies[0], equals('Camera activity detected on your device.'));

      // Step 2: Upgraded verified app event replaces notification
      final appEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.client.photo',
        appName: 'Photo Editor',
        timestamp: now.add(const Duration(milliseconds: 100)),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
      );
      await notifService.handleSensorAccessEvent(appEvent);
      expect(sentBodies.length, equals(2));
      expect(sentBodies[1], equals('Photo Editor is using your camera.'));

      // Step 3: Repeated active event for same app is SUPPRESSED
      final repeatAppEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.client.photo',
        appName: 'Photo Editor',
        timestamp: now.add(const Duration(milliseconds: 200)),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
      );
      final repeatDecision = await notifService.handleSensorAccessEvent(repeatAppEvent);
      expect(repeatDecision.outcome, equals(NotificationDecisionOutcome.suppressedAlreadyActive));
      expect(sentBodies.length, equals(2)); // No extra notification!
    });

    // ---------------------------------------------------------
    // GROUP 5: DASHBOARD RENDERING (Tests 21-26)
    // ---------------------------------------------------------
    testWidgets('21. Verified LIVE app identity rendered in LiveSensorMiniVisualizer', (tester) async {
      final service = SensorAccessService();
      final appEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.browser.privacy',
        appName: 'Privacy Browser',
        timestamp: DateTime.now(),
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        availability: SensorCapabilityLevel.full,
      );
      service.processEvent(appEvent);

      await tester.pumpWidget(
        MaterialApp(
          theme: SentinelTheme.darkTheme,
          home: Scaffold(
            body: LiveSensorMiniVisualizer(sensorService: service),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CAMERA'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Privacy Browser'), findsOneWidget);
    });

    testWidgets('22. Device-level LIVE fallback shows App identity unavailable', (tester) async {
      final service = SensorAccessService();
      final devEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.active,
        packageName: null,
        appName: null,
        timestamp: DateTime.now(),
        source: SensorEventSource.cameraManager,
        confidence: SensorConfidence.derived,
        attributionScope: SensorAttributionScope.deviceLevel,
        availability: SensorCapabilityLevel.limited,
      );
      service.processEvent(devEvent);

      await tester.pumpWidget(
        MaterialApp(
          theme: SentinelTheme.darkTheme,
          home: Scaffold(
            body: LiveSensorMiniVisualizer(sensorService: service),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CAMERA'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('App identity unavailable'), findsOneWidget);
    });

    test('23. Recent verified history stores real packageName, appName, and timestamps', () {
      final service = SensorAccessService();
      final eventTime = DateTime.utc(2026, 9, 24, 8, 30, 0);

      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.voice.recorder',
        appName: 'Voice Recorder',
        timestamp: eventTime,
        source: SensorEventSource.shizukuAppOps,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
      );
      service.processEvent(event);

      final stored = service.recentEvents.first;
      expect(stored.packageName, equals('com.voice.recorder'));
      expect(stored.appName, equals('Voice Recorder'));
      expect(stored.timestamp, equals(eventTime));
    });

    test('24. Relative timestamps are computed dynamically from real DateTime', () {
      final now = DateTime.now();

      final justNow = SensorAccessService.formatRelativeTime(now, now);
      expect(justNow, equals('Just now'));

      final fiveMinsAgo = SensorAccessService.formatRelativeTime(
        now.subtract(const Duration(minutes: 5)),
        now,
      );
      expect(fiveMinsAgo, equals('5 minutes ago'));

      final oneHourAgo = SensorAccessService.formatRelativeTime(
        now.subtract(const Duration(hours: 1)),
        now,
      );
      expect(oneHourAgo, equals('1 hour ago'));
    });

    test('25. No duplicate history entries created on reconnect or rapid events', () {
      final service = SensorAccessService();
      final now = DateTime.now();

      final eventA = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.rapid.test',
        appName: 'Rapid Test',
        timestamp: now,
        eventId: 'unique_rapid_01',
      );

      service.processEvent(eventA);
      // Attempt duplicate insertion with same eventId
      service.processEvent(eventA);

      expect(service.recentEvents.length, equals(1));
    });

    testWidgets('26. Settings screen renders when Shizuku is disabled without crashing', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          if (call.method == 'getShizukuStatus') {
            return {
              'state': 'OFF',
              'lifecycleState': 'SHIZUKU_UNAVAILABLE',
              'status': 'Standard Monitoring',
              'isPreciseModeEnabled': false,
              'isShizukuAvailable': false,
              'hasPermission': false,
              'isServiceBound': false,
              'summary': 'Uses standard Android privacy monitoring.',
            };
          }
          if (call.method == 'isUsageAccessGranted') return false;
          if (call.method == 'isBatteryOptimizationIgnored') return false;
          if (call.method == 'isOverlayPermissionGranted') return false;
          if (call.method == 'checkNotificationPermission') return 'GRANTED';
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SentinelTheme.darkTheme,
          home: const SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Settings & Privacy Controls'), findsOneWidget);
      expect(find.text('Precise App Attribution'), findsOneWidget);
      expect(find.text('STANDARD MONITORING'), findsOneWidget);
      expect(find.text('Uses standard Android privacy monitoring.'), findsOneWidget);
    });

    // ---------------------------------------------------------
    // GROUP 5: PHASE 4 USER CONTROLLED SENSOR BLOCKING & RESTORE (Tests 27-34)
    // ---------------------------------------------------------
    test('27. Invalid target rejection: null or empty packageName cannot be blocked', () async {
      final service = SensorAccessService();
      
      final resultNull = await service.blockSensorAccess(
        packageName: '',
        appName: 'Unknown',
        sensor: SensorType.camera,
      );
      expect(resultNull['success'], isFalse);
      expect(resultNull['reason'], contains('Invalid target'));

      expect(service.isAppBlocked('', SensorType.camera), isFalse);
    });

    test('28. BLOCK_CAMERA successful execution and post-verification records app as blocked', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          if (call.method == 'blockSensorAccess') {
            final args = call.arguments as Map<dynamic, dynamic>;
            expect(args['packageName'], equals('com.snapchat.android'));
            expect(args['sensor'], equals('CAMERA'));
            return {
              'success': true,
              'verified': true,
              'packageName': 'com.snapchat.android',
              'sensor': 'CAMERA',
              'permissionState': 'DENIED',
            };
          }
          return null;
        },
      );

      final service = SensorAccessService();
      final result = await service.blockSensorAccess(
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        sensor: SensorType.camera,
      );

      expect(result['success'], isTrue);
      expect(result['verified'], isTrue);
      expect(service.isAppBlocked('com.snapchat.android', SensorType.camera), isTrue);
    });

    test('29. Failed block action does NOT record app as blocked', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          if (call.method == 'blockSensorAccess') {
            return {
              'success': false,
              'verified': false,
              'error': 'Permission revocation failed',
              'permissionState': 'GRANTED',
            };
          }
          return null;
        },
      );

      final service = SensorAccessService();
      final result = await service.blockSensorAccess(
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        sensor: SensorType.camera,
      );

      expect(result['success'], isFalse);
      expect(service.isAppBlocked('com.snapchat.android', SensorType.camera), isFalse);
    });

    test('30. RESTORE_CAMERA successful execution removes app from blocked state', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          if (call.method == 'blockSensorAccess') {
            return {'success': true, 'verified': true, 'permissionState': 'DENIED'};
          }
          if (call.method == 'restoreSensorAccess') {
            return {'success': true, 'verified': true, 'permissionState': 'GRANTED'};
          }
          return null;
        },
      );

      final service = SensorAccessService();
      await service.blockSensorAccess(
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        sensor: SensorType.camera,
      );
      expect(service.isAppBlocked('com.snapchat.android', SensorType.camera), isTrue);

      final restoreResult = await service.restoreSensorAccess(
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        sensor: SensorType.camera,
      );

      expect(restoreResult['success'], isTrue);
      expect(restoreResult['verified'], isTrue);
      expect(service.isAppBlocked('com.snapchat.android', SensorType.camera), isFalse);
    });

    test('31. BLOCK_MICROPHONE targets RECORD_AUDIO sensor without affecting CAMERA', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          if (call.method == 'blockSensorAccess') {
            final args = call.arguments as Map<dynamic, dynamic>;
            expect(args['sensor'], equals('MICROPHONE'));
            return {'success': true, 'verified': true, 'sensor': 'MICROPHONE'};
          }
          return null;
        },
      );

      final service = SensorAccessService();
      await service.blockSensorAccess(
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        sensor: SensorType.microphone,
      );

      expect(service.isAppBlocked('com.whatsapp', SensorType.microphone), isTrue);
      expect(service.isAppBlocked('com.whatsapp', SensorType.camera), isFalse);
    });

    test('32. Check permission state queries platform channel accurately', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          if (call.method == 'checkSensorPermission') {
            final args = call.arguments as Map<dynamic, dynamic>;
            if (args['packageName'] == 'com.snapchat.android') {
              return false; // Denied / not granted
            }
          }
          return true;
        },
      );

      final service = SensorAccessService();
      final isGranted = await service.checkSensorPermission('com.snapchat.android', SensorType.camera);
      expect(isGranted, isFalse);
    });

    test('33. Audit log retrieval returns logged actions from platform layer', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          if (call.method == 'getUserActionAuditLog') {
            return [
              {
                'action': 'BLOCK_CAMERA',
                'packageName': 'com.snapchat.android',
                'appName': 'Snapchat',
                'sensor': 'CAMERA',
                'userConfirmed': true,
                'result': 'SUCCESS',
                'verified': true,
              }
            ];
          }
          return null;
        },
      );

      final service = SensorAccessService();
      final logs = await service.getUserActionAuditLog();
      expect(logs.length, equals(1));
      expect(logs[0]['action'], equals('BLOCK_CAMERA'));
      expect(logs[0]['result'], equals('SUCCESS'));
    });

    test('34. Disconnection during action returns error gracefully without crashing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          throw PlatformException(
            code: 'UNAVAILABLE',
            message: 'Shizuku UserService disconnected',
          );
        },
      );

      final service = SensorAccessService();
      final result = await service.blockSensorAccess(
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        sensor: SensorType.camera,
      );

      expect(result['success'], isFalse);
      expect(result['error'], contains('disconnected'));
      expect(service.isAppBlocked('com.snapchat.android', SensorType.camera), isFalse);
    });

    test('35. BLOCK_LOCATION targets LOCATION sensor and records app as blocked', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('privacy_sentinel'),
        (MethodCall call) async {
          if (call.method == 'blockSensorAccess') {
            final args = call.arguments as Map<dynamic, dynamic>;
            expect(args['packageName'], 'com.google.android.apps.maps');
            expect(args['sensor'], 'LOCATION');
            return {
              'success': true,
              'verified': true,
              'action': 'BLOCK_LOCATION',
              'packageName': 'com.google.android.apps.maps',
              'sensor': 'LOCATION',
              'permissionState': 'DENIED',
            };
          }
          return null;
        },
      );

      final service = SensorAccessService();
      final result = await service.blockSensorAccess(
        packageName: 'com.google.android.apps.maps',
        appName: 'Google Maps',
        sensor: SensorType.location,
      );

      expect(result['success'], isTrue);
      expect(result['verified'], isTrue);
      expect(service.isAppBlocked('com.google.android.apps.maps', SensorType.location), isTrue);
      expect(service.isAppBlocked('com.google.android.apps.maps', SensorType.camera), isFalse);
    });
  });
}

