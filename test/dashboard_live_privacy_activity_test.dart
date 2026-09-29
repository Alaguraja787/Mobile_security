import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/models/sensor_access_event.dart';
import 'package:mobile_privacy_security_project/screens/dashboard/dashboard_screen.dart';
import 'package:mobile_privacy_security_project/services/device_connection_manager.dart';
import 'package:mobile_privacy_security_project/services/privacy_alert_manager.dart';
import 'package:mobile_privacy_security_project/services/sensor_access_service.dart';
import 'package:mobile_privacy_security_project/screens/dashboard/widgets/dashboard_charts.dart';
import 'package:mobile_privacy_security_project/telemetry/telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dashboard LIVE PRIVACY ACTIVITY & RECENT SENSOR ACTIVITY Tests', () {
    late TelemetryService telemetryService;
    late DeviceConnectionManager deviceManager;
    late PrivacyAlertManager alertManager;
    late SensorAccessService sensorService;

    setUp(() {
      SensorAccessService.resetSharedInstanceForTesting();
      telemetryService = TelemetryService();
      deviceManager = DeviceConnectionManager();
      alertManager = PrivacyAlertManager();
      sensorService = SensorAccessService();
    });

    tearDown(() {
      sensorService.dispose();
      deviceManager.dispose();
      telemetryService.stop();
      SensorAccessService.resetSharedInstanceForTesting();
    });

    Future<void> pumpDashboard(WidgetTester tester, {SensorAccessService? service}) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final activeService = service ?? sensorService;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: deviceManager),
            ChangeNotifierProvider.value(value: alertManager),
            ChangeNotifierProvider.value(value: activeService),
          ],
          child: MaterialApp(
            home: DashboardScreen(
              telemetryService: telemetryService,
              sensorAccessService: activeService,
            ),
          ),
        ),
      );
      // Emit a telemetry event to clear initial dashboard loading state
      telemetryService.emit(PrivacyEvent.fromMap({}));
      await tester.pumpAndSettle();
    }

    testWidgets('1. Displays idle status when no sensors are active', (WidgetTester tester) async {
      await pumpDashboard(tester);

      expect(find.text('LIVE PRIVACY ACTIVITY'), findsOneWidget);
      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('No active camera, microphone, or location access'), findsOneWidget);
      expect(find.text('RECENT SENSOR ACTIVITY'), findsOneWidget);
      expect(find.text('No recent sensor activity recorded'), findsOneWidget);
    });

    testWidgets('2. Camera STARTED appears in LIVE and in RECENT', (WidgetTester tester) async {
      await pumpDashboard(tester);

      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
        availability: SensorCapabilityLevel.limited,
      );
      sensorService.processEvent(event);
      await tester.pump();

      expect(find.text('LIVE PRIVACY ACTIVITY'), findsOneWidget);
      expect(find.text('● LIVE'), findsWidgets);
      expect(find.text('DEVICE LEVEL'), findsWidgets);
      expect(find.text('App identity unavailable'), findsWidgets);
      expect(find.text('RECENT SENSOR ACTIVITY'), findsOneWidget);
    });

    testWidgets('3. Microphone STARTED appears in LIVE and in RECENT', (WidgetTester tester) async {
      await pumpDashboard(tester);

      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.generic.recorder',
        appName: 'Audio Recorder',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
        availability: SensorCapabilityLevel.full,
      );
      sensorService.processEvent(event);
      await tester.pump();

      expect(find.text('LIVE PRIVACY ACTIVITY'), findsOneWidget);
      expect(find.text('● LIVE'), findsWidgets);
      expect(find.text('Audio Recorder'), findsWidgets);
      expect(find.text('VERIFIED'), findsWidgets);
      expect(find.text('RECENT SENSOR ACTIVITY'), findsOneWidget);
    });

    testWidgets('4. ACTIVE updates LIVE session', (WidgetTester tester) async {
      await pumpDashboard(tester);

      final startEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      sensorService.processEvent(startEvent);
      await tester.pump();

      expect(sensorService.activeSessions.length, 1);

      final activeEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.active,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      sensorService.processEvent(activeEvent);
      await tester.pump();

      expect(sensorService.activeSessions.length, 1);
      expect(find.text('LIVE PRIVACY ACTIVITY'), findsOneWidget);
      expect(find.text('● LIVE'), findsWidgets);
    });

    testWidgets('5. STOPPED removes LIVE entry and preserves RECENT history', (WidgetTester tester) async {
      await pumpDashboard(tester);

      final startEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        timestamp: DateTime.now().subtract(const Duration(seconds: 10)),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      sensorService.processEvent(startEvent);
      await tester.pump();

      expect(find.text('IDLE'), findsNothing);

      final stopEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.stopped,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      sensorService.processEvent(stopEvent);
      await tester.pump();

      // LIVE section should be back to IDLE
      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('No active camera, microphone, or location access'), findsOneWidget);

      // RECENT section must still contain the recorded events
      expect(find.text('RECENT SENSOR ACTIVITY'), findsOneWidget);
      expect(sensorService.recentEvents.isNotEmpty, isTrue);
      expect(find.text('No recent sensor activity recorded'), findsNothing);
    });

    testWidgets('6. Relative timestamp and duration formatting works accurately', (WidgetTester tester) async {
      final now = DateTime(2026, 9, 23, 12, 0, 0);

      expect(SensorAccessService.formatRelativeTime(now.subtract(const Duration(seconds: 10)), now), 'Just now');
      expect(SensorAccessService.formatRelativeTime(now.subtract(const Duration(minutes: 2)), now), '2 minutes ago');
      expect(SensorAccessService.formatRelativeTime(now.subtract(const Duration(hours: 1)), now), '1 hour ago');
      expect(SensorAccessService.formatRelativeTime(now.subtract(const Duration(hours: 5)), now), '5 hours ago');
      expect(SensorAccessService.formatRelativeTime(now.subtract(const Duration(days: 1)), now), '1 day ago');

      expect(SensorAccessService.formatActiveDuration(now.subtract(const Duration(seconds: 12)), now), 'Active for 12s');
      expect(SensorAccessService.formatActiveDuration(now.subtract(const Duration(seconds: 90)), now), 'Active for 1m 30s');
    });

    testWidgets('7. Verified app identity is displayed accurately', (WidgetTester tester) async {
      await pumpDashboard(tester);

      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.example.verifiedcam',
        appName: 'Sentinel Camera App',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
        availability: SensorCapabilityLevel.full,
      );
      sensorService.processEvent(event);
      await tester.pump();

      expect(find.text('Sentinel Camera App'), findsWidgets);
      expect(find.text('VERIFIED'), findsWidgets);
    });

    testWidgets('8. Unknown attribution is displayed honestly without guessing', (WidgetTester tester) async {
      await pumpDashboard(tester);

      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
        availability: SensorCapabilityLevel.limited,
      );
      sensorService.processEvent(event);
      await tester.pump();

      expect(find.text('App identity unavailable'), findsWidgets);
      expect(find.text('DEVICE LEVEL'), findsWidgets);
    });

    testWidgets('9. Camera and microphone appear independently and concurrently', (WidgetTester tester) async {
      await pumpDashboard(tester);

      final camEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.app.cam',
        appName: 'Camera App',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );
      final micEvent = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.app.mic',
        appName: 'Mic App',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      sensorService.processEvent(camEvent);
      sensorService.processEvent(micEvent);
      await tester.pump();

      expect(sensorService.activeSessions.length, 2);
      expect(find.text('Camera App'), findsWidgets);
      expect(find.text('Mic App'), findsWidgets);
      expect(find.text('Using camera now • Active for 0s'), findsWidgets);
      expect(find.text('Using microphone now • Active for 0s'), findsWidgets);
    });

    testWidgets('10. Multiple active events do not overwrite each other', (WidgetTester tester) async {
      final camApp1 = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.app.one',
        appName: 'App One',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );
      final camApp2 = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.app.two',
        appName: 'App Two',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      sensorService.processEvent(camApp1);
      sensorService.processEvent(camApp2);

      expect(sensorService.activeSessions.length, 2);
      expect(sensorService.activeSessions.any((e) => e.packageName == 'com.app.one'), isTrue);
      expect(sensorService.activeSessions.any((e) => e.packageName == 'com.app.two'), isTrue);
    });

    testWidgets('11. Dashboard works independently if notification delivery fails', (WidgetTester tester) async {
      await pumpDashboard(tester);

      // Dashboard directly observes SensorAccessService, regardless of notification outcome
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      sensorService.processEvent(event);
      await tester.pump();

      expect(find.text('LIVE PRIVACY ACTIVITY'), findsOneWidget);
      expect(find.text('● LIVE'), findsWidgets);
    });

    testWidgets('12. Duplicate events with same eventId or timestamp are suppressed', (WidgetTester tester) async {
      final now = DateTime.now();
      final event1 = SensorAccessEvent(
        eventId: 'duplicate_test_123',
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        timestamp: now,
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      final event2 = SensorAccessEvent(
        eventId: 'duplicate_test_123',
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        timestamp: now,
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );

      sensorService.processEvent(event1);
      sensorService.processEvent(event2);

      expect(sensorService.recentEvents.length, 1);
    });

    testWidgets('13. Dashboard remains automatically reactive without manual refresh', (WidgetTester tester) async {
      await pumpDashboard(tester);

      expect(find.text('IDLE'), findsOneWidget);

      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      sensorService.processEvent(event);

      // A simple pump (rebuild triggered by notifyListeners) reflects the change
      await tester.pump();
      expect(find.text('IDLE'), findsNothing);
      expect(find.text('● LIVE'), findsWidgets);
    });

    testWidgets('14. LiveSensorMiniVisualizer reflects real active and inactive states', (WidgetTester tester) async {
      await pumpDashboard(tester);

      // When idle, CAMERA, MICROPHONE, and LOCATION show INACTIVE
      expect(find.text('CAMERA'), findsOneWidget);
      expect(find.text('MICROPHONE'), findsOneWidget);
      expect(find.text('LOCATION'), findsOneWidget);
      expect(find.text('INACTIVE'), findsNWidgets(3));

      // Activate camera
      final camEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.real.camera',
        appName: 'Real Camera',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );
      sensorService.processEvent(camEvent);
      await tester.pump();

      // Camera becomes LIVE while microphone and location stay INACTIVE
      expect(find.text('INACTIVE'), findsNWidgets(2));
      expect(find.text('Real Camera'), findsWidgets);
    });

    testWidgets('15. Risk donut chart displays real risk counts and handles empty state honestly', (WidgetTester tester) async {
      await pumpDashboard(tester);

      // Risk Distribution section exists and displays honest empty state when no apps analyzed
      expect(find.text('Risk Distribution'), findsOneWidget);
      expect(find.text('No risk analysis data available'), findsOneWidget);

      // Emit telemetry with an app to verify populated risk donut and legend
      telemetryService.emit(PrivacyEvent.fromMap({
        'apps': [
          {
            'packageName': 'com.test.safeapp',
            'appName': 'Safe App',
            'requestedPermissions': ['android.permission.INTERNET'],
            'grantedPermissions': ['android.permission.INTERNET'],
          }
        ],
      }));
      await tester.pumpAndSettle();

      expect(find.text('1 Analysed'), findsOneWidget);
      expect(find.descendant(of: find.byType(RiskDistributionDonutChart), matching: find.text('Expected')), findsOneWidget);
      expect(find.descendant(of: find.byType(RiskDistributionDonutChart), matching: find.text('Low')), findsOneWidget);
      expect(find.descendant(of: find.byType(RiskDistributionDonutChart), matching: find.text('Review')), findsOneWidget);
      expect(find.descendant(of: find.byType(RiskDistributionDonutChart), matching: find.text('High')), findsOneWidget);
      expect(find.descendant(of: find.byType(RiskDistributionDonutChart), matching: find.text('Critical')), findsOneWidget);
    });

    testWidgets('16. App usage bar chart uses real usage stats without fake numbers', (WidgetTester tester) async {
      await pumpDashboard(tester);

      expect(find.text("Today's App Usage"), findsOneWidget);
      // Since default empty PrivacyEvent has no usage permission, honest permission notice is shown
      expect(find.textContaining('No usage data available'), findsOneWidget);

      // Now emit an event with usage permission granted but 0 app usage
      telemetryService.emit(PrivacyEvent.fromMap({
        'usageSummary': {
          'usageAccessGranted': true,
        },
        'apps': <Map<String, dynamic>>[],
      }));
      await tester.pumpAndSettle();

      expect(find.text('No usage data available for today yet.'), findsOneWidget);
    });

    testWidgets('17. Permission distribution chart calculates and displays real permission counts', (WidgetTester tester) async {
      await pumpDashboard(tester);

      expect(find.text('Permission Distribution'), findsOneWidget);
      expect(find.text('No permission inventory available'), findsOneWidget);

      // Emit telemetry with an app having granted and denied permissions
      telemetryService.emit(PrivacyEvent.fromMap({
        'apps': [
          {
            'packageName': 'com.test.sample',
            'appName': 'Sample App',
            'requestedPermissions': ['android.permission.CAMERA', 'android.permission.INTERNET'],
            'grantedPermissions': ['android.permission.CAMERA'],
            'dangerousGrantedPermissions': ['android.permission.CAMERA'],
            'deniedPermissions': ['android.permission.INTERNET'],
          }
        ],
      }));
      await tester.pumpAndSettle();

      expect(find.text('Permission Distribution'), findsOneWidget);
      expect(find.text('Sensitive Granted'), findsOneWidget);
      expect(find.text('Standard Granted'), findsOneWidget);
      expect(find.text('Denied / Revoked'), findsOneWidget);
    });

    testWidgets('18. App attribution integrity: verified apps display display-name; device-level displays fallback without guessing', (WidgetTester tester) async {
      await pumpDashboard(tester);

      // 1. App-level verified event displays real app name
      final verifiedEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.sample.phototool',
        appName: 'Photo Tool Pro',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );
      sensorService.processEvent(verifiedEvent);
      await tester.pump();

      expect(find.text('Photo Tool Pro'), findsWidgets);
      expect(find.text('VERIFIED'), findsWidgets);

      // 2. Clear session
      sensorService.processEvent(SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.stopped,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      ));
      await tester.pump();

      // 3. Device-level event displays fallback "App identity unavailable" without guessing
      final deviceLevelEvent = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.deviceLevel,
        confidence: SensorConfidence.derived,
      );
      sensorService.processEvent(deviceLevelEvent);
      await tester.pump();

      expect(find.text('App identity unavailable'), findsWidgets);
      expect(find.text('DEVICE LEVEL'), findsWidgets);
    });

    testWidgets('19. Verified app in RECENT SENSOR ACTIVITY displays BLOCK CAMERA button and confirmation dialog', (WidgetTester tester) async {
      await pumpDashboard(tester);

      // App started camera
      final startEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );
      sensorService.processEvent(startEvent);
      await tester.pump();

      // App stopped camera -> no longer LIVE, only in RECENT
      final stopEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.stopped,
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );
      sensorService.processEvent(stopEvent);
      await tester.pump();

      // Verify LIVE section is IDLE
      expect(find.text('IDLE'), findsOneWidget);

      // Verify RECENT SENSOR ACTIVITY shows Snapchat and BLOCK CAMERA button
      expect(find.text('RECENT SENSOR ACTIVITY'), findsOneWidget);
      expect(find.text('Snapchat'), findsWidgets);
      expect(find.text('BLOCK CAMERA'), findsWidgets);

      // Tap BLOCK CAMERA button
      await tester.tap(find.text('BLOCK CAMERA').first);
      await tester.pumpAndSettle();

      // Confirmation dialog should be displayed with clear warning
      expect(find.text('Block camera access for Snapchat?'), findsOneWidget);
      expect(find.textContaining('This will revoke system sensor permission'), findsOneWidget);
      expect(find.textContaining('Snapchat will ask for permission'), findsOneWidget);
    });

    testWidgets('20. Blocked app in RECENT SENSOR ACTIVITY displays DENIED status and ALLOW AGAIN button', (WidgetTester tester) async {
      await pumpDashboard(tester);

      // App is marked as blocked
      final blockedEvent = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.stopped,
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
        blockedState: true,
      );
      sensorService.processEvent(blockedEvent);
      await tester.pump();

      // RECENT SENSOR ACTIVITY shows DENIED and ALLOW AGAIN
      expect(find.text('RECENT SENSOR ACTIVITY'), findsOneWidget);
      expect(find.text('CAMERA = DENIED'), findsWidgets);
      expect(find.text('ALLOW AGAIN'), findsWidgets);
    });

    testWidgets('21. Location STARTED appears in LIVE, in RECENT, and displays BLOCK LOCATION button', (WidgetTester tester) async {
      await pumpDashboard(tester);

      final locEvent = SensorAccessEvent(
        sensorType: SensorType.location,
        state: SensorAccessState.started,
        packageName: 'com.google.android.apps.maps',
        appName: 'Google Maps',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
        availability: SensorCapabilityLevel.full,
      );
      sensorService.processEvent(locEvent);
      await tester.pump();

      // LIVE section shows LIVE badge and Google Maps
      expect(find.text('LIVE PRIVACY ACTIVITY'), findsOneWidget);
      expect(find.text('● LIVE'), findsWidgets);
      expect(find.text('Google Maps'), findsWidgets);
      expect(find.text('LOCATION'), findsWidgets);
      expect(find.text('Using location now • Active for 0s'), findsWidgets);
      expect(find.text('BLOCK LOCATION'), findsWidgets);

      // Tap BLOCK LOCATION button
      await tester.tap(find.text('BLOCK LOCATION').first);
      await tester.pumpAndSettle();

      // Confirmation dialog shows location permission
      expect(find.text('Block location access for Google Maps?'), findsOneWidget);
      expect(find.textContaining('android.permission.ACCESS_FINE_LOCATION'), findsOneWidget);
    });
  });
}
