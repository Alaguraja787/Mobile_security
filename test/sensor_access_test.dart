import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/sensor_access_event.dart';
import 'package:mobile_privacy_security_project/services/sensor_access_service.dart';
import 'package:mobile_privacy_security_project/services/privacy_notification_service.dart';

void main() {
  group('SensorAccessEvent Model Tests', () {
    test('1. SensorAccessEvent serialization and deserialization round-trip', () {
      final now = DateTime.utc(2026, 9, 23, 10, 0, 0);
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'org.example.testapp',
        appName: 'Test Camera App',
        timestamp: now,
        source: SensorEventSource.appops,
        confidence: SensorConfidence.verified,
        attributionScope: SensorAttributionScope.appLevel,
        availability: SensorCapabilityLevel.full,
        reason: 'Verified AppOps observation',
        eventId: 'test_cam_001',
      );

      final json = event.toJson();
      expect(json['sensor'], 'CAMERA');
      expect(json['state'], 'STARTED');
      expect(json['packageName'], 'org.example.testapp');
      expect(json['appName'], 'Test Camera App');
      expect(json['source'], 'APPOPS');
      expect(json['confidence'], 'VERIFIED');
      expect(json['attributionScope'], 'APP_LEVEL');
      expect(json['availability'], 'FULL');
      expect(json['eventId'], 'test_cam_001');

      final deserialized = SensorAccessEvent.fromMap(json);
      expect(deserialized.sensorType, SensorType.camera);
      expect(deserialized.state, SensorAccessState.started);
      expect(deserialized.packageName, 'org.example.testapp');
      expect(deserialized.appName, 'Test Camera App');
      expect(deserialized.timestamp, now);
      expect(deserialized.source, SensorEventSource.appops);
      expect(deserialized.confidence, SensorConfidence.verified);
      expect(deserialized.attributionScope, SensorAttributionScope.appLevel);
      expect(deserialized.availability, SensorCapabilityLevel.full);
      expect(deserialized.isAppAttributed, isTrue);
      expect(deserialized.isStarted, isTrue);
      expect(deserialized.isStopped, isFalse);
    });

    test('2. Camera event parsing for device-level observation', () {
      final rawMap = {
        'type': 'sensor_access',
        'sensor': 'CAMERA',
        'state': 'ACTIVE',
        'packageName': null,
        'appName': null,
        'timestamp': '2026-09-23T10:15:30.000Z',
        'source': 'CAMERA_MANAGER',
        'confidence': 'DERIVED',
        'attributionScope': 'DEVICE_LEVEL',
        'availability': 'LIMITED',
        'reason': 'Camera hardware unavailable callback'
      };

      final event = SensorAccessEvent.fromMap(rawMap);
      expect(event.sensorType, SensorType.camera);
      expect(event.state, SensorAccessState.active);
      expect(event.attributionScope, SensorAttributionScope.deviceLevel);
      expect(event.confidence, SensorConfidence.derived);
      expect(event.availability, SensorCapabilityLevel.limited);
      expect(event.packageName, isNull);
      expect(event.appName, isNull);
      expect(event.isAppAttributed, isFalse);
    });

    test('3. Microphone event parsing for device-level audio recording', () {
      final rawMap = {
        'type': 'sensor_access',
        'sensor': 'MICROPHONE',
        'state': 'STARTED',
        'packageName': null,
        'appName': null,
        'timestamp': '2026-09-23T10:16:00.000Z',
        'source': 'AUDIO_MANAGER',
        'confidence': 'DERIVED',
        'attributionScope': 'DEVICE_LEVEL',
        'availability': 'LIMITED',
      };

      final event = SensorAccessEvent.fromMap(rawMap);
      expect(event.sensorType, SensorType.microphone);
      expect(event.state, SensorAccessState.started);
      expect(event.source, SensorEventSource.audioManager);
      expect(event.attributionScope, SensorAttributionScope.deviceLevel);
      expect(event.isAppAttributed, isFalse);
      expect(event.isStarted, isTrue);
    });

    test('4. STARTED event updates active sensor in service', () {
      final service = SensorAccessService();
      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
      );

      service.processEvent(event);
      expect(service.isSensorActive(SensorType.microphone), isTrue);
      expect(service.activeSensors[SensorType.microphone], equals(event));
      expect(service.isSensorActive(SensorType.camera), isFalse);
    });

    test('5. STOPPED event clears active sensor in service', () {
      final service = SensorAccessService();
      final startEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
      );
      service.processEvent(startEvent);
      expect(service.isSensorActive(SensorType.camera), isTrue);

      final stopEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.stopped,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
      );
      service.processEvent(stopEvent);
      expect(service.isSensorActive(SensorType.camera), isFalse);
      expect(service.activeSensors[SensorType.camera], isNull);
    });

    test('6. UNKNOWN attribution is handled without guessing', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.otherSupported,
        state: SensorAccessState.unknown,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.unknown,
        confidence: SensorConfidence.unknown,
        availability: SensorCapabilityLevel.unavailable,
      );

      expect(event.isAppAttributed, isFalse);
      expect(event.packageName, isNull);
      expect(event.appName, isNull);
      expect(event.attributionScope, SensorAttributionScope.unknown);
    });

    test('7. LIMITED capability parsing and representation', () {
      final rawCapMap = {
        'camera': {
          'activeMonitoring': 'LIMITED',
          'appAttribution': 'UNAVAILABLE',
          'recentHistory': 'LIMITED',
        },
        'microphone': {
          'activeMonitoring': 'LIMITED',
          'appAttribution': 'UNAVAILABLE',
          'recentHistory': 'LIMITED',
        },
        'platformSdkInt': 36,
        'isCameraWatcherRegistered': true,
        'isAudioWatcherRegistered': true,
        'isAppOpsWatcherRegistered': false,
      };

      final caps = SensorMonitoringCapabilities.fromMap(rawCapMap);
      expect(caps.camera.activeMonitoring, SensorCapabilityLevel.limited);
      expect(caps.camera.appAttribution, SensorCapabilityLevel.unavailable);
      expect(caps.camera.recentHistory, SensorCapabilityLevel.limited);
      expect(caps.microphone.activeMonitoring, SensorCapabilityLevel.limited);
      expect(caps.microphone.appAttribution, SensorCapabilityLevel.unavailable);
      expect(caps.platformSdkInt, 36);
      expect(caps.isCameraWatcherRegistered, isTrue);
      expect(caps.isAudioWatcherRegistered, isTrue);
      expect(caps.isAppOpsWatcherRegistered, isFalse);
    });

    test('8. UNAVAILABLE capability defaults', () {
      final defaultCaps = SensorMonitoringCapabilities.defaultUnknown();
      expect(defaultCaps.camera.activeMonitoring, SensorCapabilityLevel.unavailable);
      expect(defaultCaps.camera.appAttribution, SensorCapabilityLevel.unavailable);
      expect(defaultCaps.microphone.activeMonitoring, SensorCapabilityLevel.unavailable);
    });

    test('9. No fake package attribution: unverified events are excluded from verifiedRecentEvents', () {
      final service = SensorAccessService();
      final deviceLevelCam = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.active,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      final verifiedMic = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.verified.testapp',
        appName: 'Test Recorder',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      service.processEvent(deviceLevelCam);
      service.processEvent(verifiedMic);

      expect(service.recentEvents.length, 2);
      expect(service.verifiedRecentEvents.length, 1);
      expect(service.verifiedRecentEvents.first.packageName, 'com.verified.testapp');
      expect(service.recentEvents.any((e) => e.packageName == null), isTrue);
    });

    test('10. Timestamp conversion and dynamic relative time formatting', () {
      final now = DateTime(2026, 9, 23, 12, 0, 0);

      final justNow = now.subtract(const Duration(seconds: 20));
      expect(SensorAccessService.formatRelativeTime(justNow, now), 'Just now');

      final oneMinAgo = now.subtract(const Duration(minutes: 1));
      expect(SensorAccessService.formatRelativeTime(oneMinAgo, now), '1 minute ago');

      final fiveMinAgo = now.subtract(const Duration(minutes: 5));
      expect(SensorAccessService.formatRelativeTime(fiveMinAgo, now), '5 minutes ago');

      final twelveMinAgo = now.subtract(const Duration(minutes: 12));
      expect(SensorAccessService.formatRelativeTime(twelveMinAgo, now), '12 minutes ago');

      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      expect(SensorAccessService.formatRelativeTime(twoHoursAgo, now), '2 hours ago');

      final threeDaysAgo = now.subtract(const Duration(days: 3));
      expect(SensorAccessService.formatRelativeTime(threeDaysAgo, now), '3 days ago');
    });

    test('11. Recent event ordering (newest first) and 500-event bounding', () {
      final service = SensorAccessService(maxRecentEvents: 10);
      for (int i = 0; i < 20; i++) {
        service.processEvent(SensorAccessEvent(
          sensorType: SensorType.camera,
          state: SensorAccessState.started,
          timestamp: DateTime.now().add(Duration(seconds: i)),
          eventId: 'evt_$i',
        ));
      }

      // Max bounded size should be 10
      expect(service.recentEvents.length, 10);
      // Newest event (i = 19) must be first
      expect(service.recentEvents.first.eventId, 'evt_19');
      // Oldest kept event (i = 10) must be last
      expect(service.recentEvents.last.eventId, 'evt_10');
    });
  });

  group('PrivacyNotificationService Tests', () {
    late PrivacyNotificationService notificationService;
    final List<Map<String, dynamic>> dispatchedNotifications = [];

    setUp(() {
      dispatchedNotifications.clear();
      notificationService = PrivacyNotificationService(
        cooldownDuration: const Duration(seconds: 30),
        customNotificationSender: ({required id, required title, required body}) async {
          dispatchedNotifications.add({
            'id': id,
            'title': title,
            'body': body,
          });
        },
      );
    });

    test('12. Deduplication: repeated ACTIVE event while already active is suppressed', () async {
      final now = DateTime(2026, 9, 23, 10, 0, 0);
      final event1 = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.alpha.camera',
        appName: 'Alpha Cam',
        timestamp: now,
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final decision1 = await notificationService.handleSensorAccessEvent(event1, now: now);
      expect(decision1.wasNotified, isTrue);
      expect(dispatchedNotifications.length, 1);
      expect(dispatchedNotifications.first['body'], contains('Alpha Cam is using your camera'));

      // Event arrives again while sensor is already active
      final decision2 = await notificationService.handleSensorAccessEvent(event1, now: now.add(const Duration(seconds: 5)));
      expect(decision2.outcome, NotificationDecisionOutcome.suppressedAlreadyActive);
      expect(dispatchedNotifications.length, 1); // No new notification sent
    });

    test('13. Notification cooldown: sensor restarted within cooldown window is suppressed', () async {
      final t0 = DateTime(2026, 9, 23, 10, 0, 0);
      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.beta.audio',
        appName: 'Beta Audio',
        timestamp: t0,
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      // Initial start -> notified
      final d1 = await notificationService.handleSensorAccessEvent(event, now: t0);
      expect(d1.wasNotified, isTrue);
      expect(dispatchedNotifications.length, 1);

      // Stop at t0 + 5s
      final stopEvent = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.stopped,
        packageName: 'com.beta.audio',
        timestamp: t0.add(const Duration(seconds: 5)),
      );
      final d2 = await notificationService.handleSensorAccessEvent(stopEvent, now: t0.add(const Duration(seconds: 5)));
      expect(d2.outcome, NotificationDecisionOutcome.suppressedStoppedState);

      // Restart at t0 + 15s (within 30s cooldown) -> suppressed due to cooldown
      final d3 = await notificationService.handleSensorAccessEvent(event, now: t0.add(const Duration(seconds: 15)));
      expect(d3.outcome, NotificationDecisionOutcome.suppressedCooldown);
      expect(dispatchedNotifications.length, 1);

      // Restart at t0 + 35s (after 30s cooldown) -> notified!
      final d4 = await notificationService.handleSensorAccessEvent(event, now: t0.add(const Duration(seconds: 35)));
      expect(d4.wasNotified, isTrue);
      expect(dispatchedNotifications.length, 2);
    });

    test('14. Duplicate STARTED event suppression while sensor is active', () async {
      final t0 = DateTime(2026, 9, 23, 10, 0, 0);
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.gamma.app',
        appName: 'Gamma App',
        timestamp: t0,
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final d1 = await notificationService.handleSensorAccessEvent(event, now: t0);
      expect(d1.wasNotified, isTrue);

      final d2 = await notificationService.handleSensorAccessEvent(event, now: t0.add(const Duration(seconds: 1)));
      expect(d2.outcome, NotificationDecisionOutcome.suppressedAlreadyActive);
      expect(dispatchedNotifications.length, 1);
    });

    test('15. Different app events remain independent', () async {
      final t0 = DateTime(2026, 9, 23, 10, 0, 0);
      final appA = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.app.alpha',
        appName: 'App Alpha',
        timestamp: t0,
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );
      final appB = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.app.beta',
        appName: 'App Beta',
        timestamp: t0,
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      // App A starts -> notified
      final dA = await notificationService.handleSensorAccessEvent(appA, now: t0);
      expect(dA.wasNotified, isTrue);
      expect(dispatchedNotifications.last['body'], contains('App Alpha'));

      // App B starts -> also notified independently
      final dB = await notificationService.handleSensorAccessEvent(appB, now: t0);
      expect(dB.wasNotified, isTrue);
      expect(dispatchedNotifications.last['body'], contains('App Beta'));
      expect(dispatchedNotifications.length, 2);

      // App A stops -> App B remains active and unaffected
      final stopA = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.stopped,
        packageName: 'com.app.alpha',
        timestamp: t0.add(const Duration(seconds: 2)),
      );
      await notificationService.handleSensorAccessEvent(stopA);

      // App B sending repeated active -> suppressed because B is still active
      final repeatB = await notificationService.handleSensorAccessEvent(appB, now: t0.add(const Duration(seconds: 3)));
      expect(repeatB.outcome, NotificationDecisionOutcome.suppressedAlreadyActive);
    });

    test('16. buildRecentAccessBody formats accurately without hardcoded apps', () {
      final eventTime = DateTime(2026, 9, 23, 10, 0, 0);
      final now = DateTime(2026, 9, 23, 10, 5, 0);
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.stopped,
        packageName: 'org.sample.videochat',
        appName: 'Sample Video Chat',
        timestamp: eventTime,
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final body = PrivacyNotificationService.buildRecentAccessBody(event: event, now: now);
      expect(body, 'Sample Video Chat used your camera 5 minutes ago.');
    });

    test('17. Photo access notification formats real file name when present', () async {
      final List<Map<String, dynamic>> dispatchedNotifications = [];
      final notificationService = PrivacyNotificationService(
        customNotificationSender: ({required int id, required String title, required String body}) async {
          dispatchedNotifications.add({'id': id, 'title': title, 'body': body});
        },
      );

      final photoEvent = SensorAccessEvent(
        sensorType: SensorType.photos,
        state: SensorAccessState.active,
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        fileName: 'IMG_2026.jpg',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final decision = await notificationService.handleSensorAccessEvent(photoEvent);
      expect(decision.wasNotified, isTrue);
      expect(decision.title, '🖼️ Photos access');
      expect(decision.body, 'Instagram accessed photo "IMG_2026.jpg".');
      expect(dispatchedNotifications.length, 1);
      expect(dispatchedNotifications.first['body'], 'Instagram accessed photo "IMG_2026.jpg".');
    });

    test('18. Photo access notification formats general photos when fileName is null', () async {
      final List<Map<String, dynamic>> dispatchedNotifications = [];
      final notificationService = PrivacyNotificationService(
        customNotificationSender: ({required int id, required String title, required String body}) async {
          dispatchedNotifications.add({'id': id, 'title': title, 'body': body});
        },
      );

      final photoEvent = SensorAccessEvent(
        sensorType: SensorType.photos,
        state: SensorAccessState.started,
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final decision = await notificationService.handleSensorAccessEvent(photoEvent);
      expect(decision.wasNotified, isTrue);
      expect(decision.title, '🖼️ Photos access');
      expect(decision.body, 'Instagram accessed your photos.');
    });

    test('19. Locked screen photo access formats suspicious background alert', () async {
      final List<Map<String, dynamic>> dispatchedNotifications = [];
      final notificationService = PrivacyNotificationService(
        customNotificationSender: ({required int id, required String title, required String body}) async {
          dispatchedNotifications.add({'id': id, 'title': title, 'body': body});
        },
      );

      final lockedEvent = SensorAccessEvent(
        sensorType: SensorType.photos,
        state: SensorAccessState.active,
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        fileName: 'IMG_2026.jpg',
        isScreenLocked: true,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final decision = await notificationService.handleSensorAccessEvent(lockedEvent);
      expect(decision.wasNotified, isTrue);
      expect(decision.title, '🚨 Screen Locked: Photo Access Alert');
      expect(decision.body, contains('Instagram accessed "IMG_2026.jpg" in the background while your screen was locked!'));
    });

    test('20. Location access notification formats active app usage when screen is unlocked', () async {
      final List<Map<String, dynamic>> dispatchedNotifications = [];
      final notificationService = PrivacyNotificationService(
        customNotificationSender: ({required int id, required String title, required String body}) async {
          dispatchedNotifications.add({'id': id, 'title': title, 'body': body});
        },
      );

      final locEvent = SensorAccessEvent(
        sensorType: SensorType.location,
        state: SensorAccessState.started,
        packageName: 'com.google.android.apps.maps',
        appName: 'Google Maps',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final decision = await notificationService.handleSensorAccessEvent(locEvent);
      expect(decision.wasNotified, isTrue);
      expect(decision.title, '📍 Location access');
      expect(decision.body, 'Google Maps is using your location.');
      expect(dispatchedNotifications.length, 1);
      expect(dispatchedNotifications.first['body'], 'Google Maps is using your location.');
    });

    test('21. Locked screen location access formats suspicious background alert', () async {
      final List<Map<String, dynamic>> dispatchedNotifications = [];
      final notificationService = PrivacyNotificationService(
        customNotificationSender: ({required int id, required String title, required String body}) async {
          dispatchedNotifications.add({'id': id, 'title': title, 'body': body});
        },
      );

      final lockedLocEvent = SensorAccessEvent(
        sensorType: SensorType.location,
        state: SensorAccessState.active,
        packageName: 'com.sneaky.tracker',
        appName: 'Sneaky Tracker',
        isScreenLocked: true,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final decision = await notificationService.handleSensorAccessEvent(lockedLocEvent);
      expect(decision.wasNotified, isTrue);
      expect(decision.title, '🚨 Screen Locked: Location Alert');
      expect(decision.body, contains('Sneaky Tracker accessed your location in the background while your screen was locked!'));
    });

    test('22. Location STARTED and STOPPED updates SensorAccessService activeSessions and activeSensors', () {
      final service = SensorAccessService();

      final startEvent = SensorAccessEvent(
        sensorType: SensorType.location,
        state: SensorAccessState.started,
        packageName: 'com.google.android.apps.maps',
        appName: 'Google Maps',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      service.processEvent(startEvent);
      expect(service.isSensorActive(SensorType.location), isTrue);
      expect(service.activeSensors[SensorType.location], isNotNull);
      expect(service.activeSensors[SensorType.location]?.appName, 'Google Maps');

      final stopEvent = SensorAccessEvent(
        sensorType: SensorType.location,
        state: SensorAccessState.stopped,
        packageName: 'com.google.android.apps.maps',
        appName: 'Google Maps',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      service.processEvent(stopEvent);
      expect(service.isSensorActive(SensorType.location), isFalse);
      expect(service.activeSensors[SensorType.location], isNull);
      expect(service.recentEvents.length, 2);
    });
  });
}
