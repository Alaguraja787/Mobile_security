import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';

void main() {
  test('DEVICE INVENTORY AND GENERAL QUERY TEST', () async {
    final guardianService = GuardianService();
    guardianService.updateTelemetryContext([
      AppTelemetry(
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        isSystemApp: false,
        grantedPermissions: ['CAMERA', 'RECORD_AUDIO'],
      ),
      AppTelemetry(
        packageName: 'com.google.android.GoogleCamera',
        appName: 'Camera',
        isSystemApp: true,
        grantedPermissions: ['CAMERA'],
      )
    ]);

    // Test 1: Phone specific question
    final phoneMsg = await guardianService.askGuardian('tell me about my phone');
    print('\n[PHONE QUERY RESPONSE]:\n${phoneMsg.text}\n');
    expect(phoneMsg.text.isNotEmpty, isTrue);

    // Test 2: General question
    final generalMsg = await guardianService.askGuardian('what is location permission and why should I care?');
    print('\n[GENERAL QUERY RESPONSE]:\n${generalMsg.text}\n');
    expect(generalMsg.text.isNotEmpty, isTrue);
  });
}
