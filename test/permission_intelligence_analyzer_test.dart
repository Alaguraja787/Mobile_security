import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/services/permission_intelligence_analyzer.dart';

void main() {
  group('PermissionIntelligenceAnalyzer Data-Driven Scoring Tests', () {
    final analyzer = PermissionIntelligenceAnalyzer();

    test('Calculator with camera & microphone gets ATTENTION or REVIEW risk score without hardcoded app name', () {
      final calcApp = AppTelemetry(
        appName: 'Simple Calculator',
        packageName: 'com.example.calculator',
        requestedPermissions: [
          'android.permission.CAMERA',
          'android.permission.RECORD_AUDIO',
          'android.permission.READ_CONTACTS',
        ],
        grantedPermissions: [
          'android.permission.CAMERA',
          'android.permission.RECORD_AUDIO',
          'android.permission.READ_CONTACTS',
        ],
        deniedPermissions: [],
      );

      final result = analyzer.analyzeApp(calcApp);

      expect(result.level, anyOf(
        equals(PermissionRiskLevel.high),
        equals(PermissionRiskLevel.attention),
        equals(PermissionRiskLevel.review),
      ));
      expect(result.riskScore, greaterThanOrEqualTo(30));
      expect(result.flaggedPermissions.length, equals(3));
      expect(result.summaryReason.toLowerCase(), contains('permissions'));
    });

    test('Clean App with no dangerous permissions returns NORMAL risk', () {
      final cleanApp = AppTelemetry(
        appName: 'Offline Reader',
        packageName: 'com.example.reader',
        requestedPermissions: ['android.permission.INTERNET'],
        grantedPermissions: ['android.permission.INTERNET'],
        deniedPermissions: [],
      );

      final result = analyzer.analyzeApp(cleanApp);

      expect(result.level, anyOf(equals(PermissionRiskLevel.normal), equals(PermissionRiskLevel.expected)));
      expect(result.riskScore, equals(0));
      expect(result.flaggedPermissions, isEmpty);
    });

    test('Device Privacy Review Score calculation handles list of results accurately', () {
      final app1 = AppTelemetry(
        appName: 'App High Risk',
        packageName: 'com.app.high',
        grantedPermissions: [
          'android.permission.CAMERA',
          'android.permission.RECORD_AUDIO',
          'android.permission.READ_CONTACTS',
          'android.permission.ACCESS_FINE_LOCATION',
        ],
        hasOverlayOp: true,
      );

      final app2 = AppTelemetry(
        appName: 'App Normal',
        packageName: 'com.app.normal',
        grantedPermissions: [],
      );

      final eval1 = analyzer.analyzeApp(app1);
      final eval2 = analyzer.analyzeApp(app2);

      final score = analyzer.calculateDevicePrivacyScore([eval1, eval2]);

      expect(score, lessThan(100));
      expect(score, greaterThanOrEqualTo(10));
    });
  });
}
