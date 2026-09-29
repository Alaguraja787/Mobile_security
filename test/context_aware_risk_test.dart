import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/guardian/context/device_inventory_context.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/services/permission_intelligence_analyzer.dart';

void main() {
  group('Context-Aware Permission Risk Analysis Tests', () {
    final analyzer = PermissionIntelligenceAnalyzer();

    test('1. Camera app with CAMERA permission is NOT marked CRITICAL', () {
      final cameraApp = AppTelemetry(
        appName: 'Google Camera',
        packageName: 'com.google.android.GoogleCamera',
        appCategory: 3, // CATEGORY_IMAGE
        grantedPermissions: [
          'android.permission.CAMERA',
          'android.permission.RECORD_AUDIO',
          'android.permission.READ_MEDIA_IMAGES',
        ],
      );

      final result = analyzer.analyzeApp(cameraApp);

      expect(result.level, isNot(equals(PermissionRiskLevel.critical)));
      expect(result.level, isNot(equals(PermissionRiskLevel.high)));
      expect(result.levelLabel, anyOf('EXPECTED', 'LOW', 'REVIEW'));
    });

    test('2. Video / Streaming app with CAMERA and STORAGE is NOT marked CRITICAL', () {
      final youtubeApp = AppTelemetry(
        appName: 'YouTube',
        packageName: 'com.google.android.youtube',
        appCategory: 2, // CATEGORY_VIDEO
        grantedPermissions: [
          'android.permission.CAMERA',
          'android.permission.RECORD_AUDIO',
          'android.permission.READ_MEDIA_VIDEO',
        ],
      );

      final result = analyzer.analyzeApp(youtubeApp);

      expect(result.level, isNot(equals(PermissionRiskLevel.critical)));
      expect(result.level, isNot(equals(PermissionRiskLevel.high)));
    });

    test('3. Maps app with FINE LOCATION is EXPECTED or LOW, NOT CRITICAL', () {
      final mapsApp = AppTelemetry(
        appName: 'Google Maps',
        packageName: 'com.google.android.apps.maps',
        appCategory: 6, // CATEGORY_MAPS
        grantedPermissions: [
          'android.permission.ACCESS_FINE_LOCATION',
          'android.permission.ACCESS_COARSE_LOCATION',
        ],
      );

      final result = analyzer.analyzeApp(mapsApp);

      expect(result.level, isNot(equals(PermissionRiskLevel.critical)));
      expect(result.level, isNot(equals(PermissionRiskLevel.high)));
      expect(result.levelLabel, anyOf('EXPECTED', 'LOW'));
    });

    test('4. Utility app with excessive sensitive permissions warrants REVIEW or HIGH, never CRITICAL without active combo', () {
      final calculator = AppTelemetry(
        appName: 'Calculator',
        packageName: 'com.example.calculator',
        appCategory: -1, // UNDEFINED / Utility
        grantedPermissions: [
          'android.permission.CAMERA',
          'android.permission.RECORD_AUDIO',
          'android.permission.READ_CONTACTS',
          'android.permission.ACCESS_FINE_LOCATION',
        ],
      );

      final result = analyzer.analyzeApp(calculator);

      expect(result.level, anyOf(equals(PermissionRiskLevel.review), equals(PermissionRiskLevel.high)));
      expect(result.level, isNot(equals(PermissionRiskLevel.critical)));
    });
  });

  group('Device Inventory Context & Deterministic Retrieval Tests', () {
    final inventory = DeviceInventoryContext();

    final testApps = [
      AppTelemetry(
        appName: 'Google Camera',
        packageName: 'com.google.android.GoogleCamera',
        appCategory: 3,
        grantedPermissions: ['android.permission.CAMERA'],
      ),
      AppTelemetry(
        appName: 'YouTube',
        packageName: 'com.google.android.youtube',
        appCategory: 2,
        grantedPermissions: ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO'],
      ),
      AppTelemetry(
        appName: 'Instagram',
        packageName: 'com.instagram.android',
        appCategory: 4,
        grantedPermissions: ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO', 'android.permission.READ_MEDIA_IMAGES'],
      ),
      AppTelemetry(
        appName: 'Calculator',
        packageName: 'com.google.android.calculator',
        appCategory: -1,
        grantedPermissions: const [],
      ),
      AppTelemetry(
        appName: 'Maps',
        packageName: 'com.google.android.apps.maps',
        appCategory: 6,
        grantedPermissions: ['android.permission.ACCESS_FINE_LOCATION'],
      ),
    ];

    inventory.updateApps(testApps);

    test('1. Camera list query returns ALL matching apps, not just one', () {
      final res = inventory.retrieveEvidence('which apps has a permission to open camera list the apps name');

      expect(res.intent, equals(QueryIntent.listAppsByPermission));
      expect(res.targetPermission, equals('CAMERA'));
      expect(res.matchingApps.length, equals(3));
      final appNames = res.matchingApps.map((a) => a.appName).toList();
      expect(appNames, containsAll(['Google Camera', 'YouTube', 'Instagram']));
      expect(appNames, isNot(contains('Calculator')));
      expect(res.evidencePromptBlock, contains('Google Camera'));
      expect(res.evidencePromptBlock, contains('YouTube'));
      expect(res.evidencePromptBlock, contains('Instagram'));
    });

    test('2. Microphone list query returns matching apps', () {
      final res = inventory.retrieveEvidence('which apps have microphone permission?');

      expect(res.intent, equals(QueryIntent.listAppsByPermission));
      expect(res.matchingApps.length, equals(2));
      final appNames = res.matchingApps.map((a) => a.appName).toList();
      expect(appNames, containsAll(['YouTube', 'Instagram']));
    });

    test('3. App explanation query targets specific app without inventing data', () {
      final res = inventory.retrieveEvidence('Why does YouTube need camera permission?');

      expect(res.intent, equals(QueryIntent.appExplanation));
      expect(res.targetApp?.appName, equals('YouTube'));
      expect(res.evidencePromptBlock, contains('TARGET APP: YouTube (com.google.android.youtube)'));
      expect(res.evidencePromptBlock, contains('GRANTED PERMISSIONS:'));
    });
  });
}
