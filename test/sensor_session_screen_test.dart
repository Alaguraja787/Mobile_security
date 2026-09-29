import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile_privacy_security_project/core/theme/sentinel_theme.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/models/sensor_access_event.dart';
import 'package:mobile_privacy_security_project/screens/dashboard/dashboard_screen.dart';
import 'package:mobile_privacy_security_project/screens/dashboard/sensor_session_screen.dart';
import 'package:mobile_privacy_security_project/services/device_connection_manager.dart';
import 'package:mobile_privacy_security_project/services/privacy_alert_manager.dart';
import 'package:mobile_privacy_security_project/services/sensor_access_service.dart';
import 'package:mobile_privacy_security_project/telemetry/telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dedicated Sensor Session Screen & Navigation Tests', () {
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

    Future<void> pumpDashboard(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: deviceManager),
            ChangeNotifierProvider.value(value: alertManager),
            ChangeNotifierProvider.value(value: sensorService),
          ],
          child: MaterialApp(
            theme: SentinelTheme.darkTheme,
            home: DashboardScreen(
              telemetryService: telemetryService,
              sensorAccessService: sensorService,
            ),
          ),
        ),
      );
      telemetryService.emit(PrivacyEvent.fromMap({}));
      await tester.pumpAndSettle();
    }

    testWidgets('1. Tapping CAMERA tile on Dashboard navigates to Camera Session Screen', (WidgetTester tester) async {
      await pumpDashboard(tester);

      expect(find.text('CAMERA'), findsOneWidget);
      await tester.tap(find.text('CAMERA'));
      await tester.pumpAndSettle();

      expect(find.byType(SensorSessionScreen), findsOneWidget);
      expect(find.text('Camera Session'), findsOneWidget);
      expect(find.text('No Active Camera Access'), findsOneWidget);
    });

    testWidgets('2. Tapping MICROPHONE tile on Dashboard navigates to Microphone Session Screen', (WidgetTester tester) async {
      await pumpDashboard(tester);

      expect(find.text('MICROPHONE'), findsOneWidget);
      await tester.tap(find.text('MICROPHONE'));
      await tester.pumpAndSettle();

      expect(find.byType(SensorSessionScreen), findsOneWidget);
      expect(find.text('Microphone Session'), findsOneWidget);
      expect(find.text('No Active Microphone Access'), findsOneWidget);
    });

    testWidgets('3. Tapping LOCATION tile on Dashboard navigates to Location Session Screen', (WidgetTester tester) async {
      await pumpDashboard(tester);

      expect(find.text('LOCATION'), findsOneWidget);
      await tester.tap(find.text('LOCATION'));
      await tester.pumpAndSettle();

      expect(find.byType(SensorSessionScreen), findsOneWidget);
      expect(find.text('Location Session'), findsOneWidget);
      expect(find.text('No Active Location Access'), findsOneWidget);
    });

    testWidgets('4. Live active app on Microphone displays dedicated active session details', (WidgetTester tester) async {
      final micEvent = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.audiorecorder.app',
        appName: 'Voice Memos',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );
      sensorService.processEvent(micEvent);

      await tester.pumpWidget(
        MaterialApp(
          theme: SentinelTheme.darkTheme,
          home: SensorSessionScreen(
            initialSensorType: SensorType.microphone,
            sensorService: sensorService,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Microphone Session'), findsOneWidget);
      expect(find.text('LIVE'), findsWidgets);
      expect(find.text('HARDWARE SENSOR STREAMING'), findsOneWidget);
      expect(find.text('Voice Memos'), findsWidgets);
      expect(find.text('com.audiorecorder.app'), findsWidgets);
      expect(find.text('VERIFIED APP'), findsOneWidget);
      expect(find.text('BLOCK MICROPHONE'), findsOneWidget);
    });

    testWidgets('5. Sensor switcher tab switches from Camera to Microphone inside session screen', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SentinelTheme.darkTheme,
          home: SensorSessionScreen(
            initialSensorType: SensorType.camera,
            sensorService: sensorService,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Camera Session'), findsOneWidget);

      // Tap the MICROPHONE tab chip at the top
      await tester.tap(find.text('MICROPHONE'));
      await tester.pumpAndSettle();

      expect(find.text('Microphone Session'), findsOneWidget);
      expect(find.text('No Active Microphone Access'), findsOneWidget);
    });
  });
}
