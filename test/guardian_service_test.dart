import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';

void main() {
  group('GuardianService Evidence-Based Inquiry Tests', () {
    final service = GuardianService();

    test('askGuardian routes query through GuardianEngine reasoning pipeline', () async {
      final appList = [
        AppTelemetry(
          appName: 'Voice Recorder',
          packageName: 'com.example.voicerecorder',
          grantedPermissions: ['android.permission.RECORD_AUDIO'],
        ),
        AppTelemetry(
          appName: 'Calc',
          packageName: 'com.example.calc',
          grantedPermissions: [],
        ),
      ];

      service.updateTelemetryContext(appList);

      final reply = await service.askGuardian('Why does Voice Recorder need microphone permission?');

      expect(reply.isUser, isFalse);
      expect(reply.text, isNotEmpty);
      expect(reply.decision, isNotNull);
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
