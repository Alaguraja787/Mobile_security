import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/services/privacy_alert_manager.dart';

void main() {
  group('PrivacyAlertManager Real-Time Alert Generation Tests', () {
    test('Detects permission transition from DENIED to GRANTED accurately', () {
      final alertManager = PrivacyAlertManager();

      final snapshot1 = AppTelemetry(
        appName: 'Chat App',
        packageName: 'com.example.chatapp',
        requestedPermissions: ['android.permission.RECORD_AUDIO'],
        grantedPermissions: [],
        deniedPermissions: ['android.permission.RECORD_AUDIO'],
      );

      final snapshot2 = AppTelemetry(
        appName: 'Chat App',
        packageName: 'com.example.chatapp',
        requestedPermissions: ['android.permission.RECORD_AUDIO'],
        grantedPermissions: ['android.permission.RECORD_AUDIO'],
        deniedPermissions: [],
      );

      alertManager.processTelemetryBatch([snapshot1]);
      final initialAlertCount = alertManager.alerts.length;

      alertManager.processTelemetryBatch([snapshot2]);

      expect(alertManager.alerts.length, equals(initialAlertCount + 1));
      final latestAlert = alertManager.alerts.first;

      expect(latestAlert.appName, equals('Chat App'));
      expect(latestAlert.permission, contains('RECORD_AUDIO'));
      expect(latestAlert.previousState, equals('DENIED'));
      expect(latestAlert.currentState, equals('GRANTED'));
      expect(latestAlert.severity, anyOf(equals(AlertSeverity.review), equals(AlertSeverity.critical)));
    });
  });
}
