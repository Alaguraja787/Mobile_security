import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/main.dart';
import 'package:mobile_privacy_security_project/services/device_connection_manager.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';
import 'package:mobile_privacy_security_project/services/privacy_alert_manager.dart';
import 'package:mobile_privacy_security_project/services/voice_guardian_service.dart';
import 'package:mobile_privacy_security_project/telemetry/telemetry_service.dart';

void main() {
  testWidgets('PrivacySentinelApp smoke test', (WidgetTester tester) async {
    final telemetryService = TelemetryService();
    final deviceManager = DeviceConnectionManager();
    final alertManager = PrivacyAlertManager();
    final guardianService = GuardianService();
    final voiceService = VoiceGuardianService(guardianService: guardianService);

    await tester.pumpWidget(PrivacySentinelApp(
      telemetryService: telemetryService,
      deviceManager: deviceManager,
      alertManager: alertManager,
      guardianService: guardianService,
      voiceService: voiceService,
    ));

    await tester.pump();

    expect(find.textContaining('Dashboard'), findsWidgets);

    // Clean up timers & subscriptions
    deviceManager.dispose();
    voiceService.dispose();
    telemetryService.stop();
  });
}
