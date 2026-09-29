import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/guardian/context/device_inventory_context.dart';
import 'package:mobile_privacy_security_project/guardian/models/device_snapshot.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';
import 'package:mobile_privacy_security_project/telemetry/app_telemetry_builder.dart';

void main() {
  group('Device Usage Intelligence & Context Fix Tests', () {
    // 1. UsageStats parsing
    test('1. Parses usage telemetry from raw map into AppTelemetry', () {
      final builder = AppTelemetryBuilder();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final rawEvent = PrivacyEvent.fromMap({
        'timestamp': DateTime.now().toIso8601String(),
        'apps': [
          {
            'appName': 'YouTube',
            'packageName': 'com.google.android.youtube',
            'usageTodayMs': 5040000, // 1h 24m
            'foregroundDurationMs': 5040000,
            'foregroundMinutes': 84.0,
            'lastUsedTimestamp': nowMs - 100000,
            'lastTimeUsedMs': nowMs - 100000,
            'visibleTimeMs': 5200000,
            'foregroundServiceTimeMs': 300000,
            'usageAvailability': 'VALID',
            'usageDataState': 'AVAILABLE',
            'requestedPermissions': ['android.permission.INTERNET', 'android.permission.CAMERA'],
            'grantedPermissions': ['android.permission.INTERNET', 'android.permission.CAMERA'],
          }
        ]
      });

      final apps = builder.build(rawEvent);
      expect(apps.length, 1);
      final yt = apps.first;
      expect(yt.usageTodayMs, 5040000);
      expect(yt.visibleTimeMs, 5200000);
      expect(yt.foregroundServiceTimeMs, 300000);
      expect(yt.lastUsedTimestamp, nowMs - 100000);
      expect(yt.usageDataState, 'AVAILABLE');
    });

    // 2. Today's usage calculation & formatting
    test('2. Formats today usage correctly across different duration spans', () {
      final app0 = AppTelemetry(
        appName: 'Unused',
        packageName: 'com.test.unused',
        usageTodayMs: 0,
        usageDataState: 'AVAILABLE',
      );
      expect(app0.usageTodayFormatted, '0m');

      final appSec = AppTelemetry(
        appName: 'Brief',
        packageName: 'com.test.brief',
        usageTodayMs: 45000, // 45s
        usageDataState: 'AVAILABLE',
      );
      expect(appSec.usageTodayFormatted, '45s');

      final appMin = AppTelemetry(
        appName: 'Short',
        packageName: 'com.test.short',
        usageTodayMs: 900000, // 15m
        usageDataState: 'AVAILABLE',
      );
      expect(appMin.usageTodayFormatted, '15m');

      final appHours = AppTelemetry(
        appName: 'Long',
        packageName: 'com.test.long',
        usageTodayMs: 5040000, // 1h 24m
        usageDataState: 'AVAILABLE',
      );
      expect(appHours.usageTodayFormatted, '1h 24m');
    });

    // 3. Last-used timestamp formatting
    test('3. Formats last-used timestamp into relative and time strings', () {
      final now = DateTime.now();
      final appRecent = AppTelemetry(
        appName: 'Recent',
        packageName: 'com.test.recent',
        lastUsedTimestamp: now.millisecondsSinceEpoch - 30000, // 30s ago
      );
      expect(appRecent.lastUsedFormatted, 'Just now');

      final app10mAgo = AppTelemetry(
        appName: 'TenMinAgo',
        packageName: 'com.test.ten',
        lastUsedTimestamp: now.millisecondsSinceEpoch - (10 * 60 * 1000), // 10m ago
      );
      expect(app10mAgo.lastUsedFormatted, '10m ago');

      final appZero = AppTelemetry(
        appName: 'Never',
        packageName: 'com.test.never',
        lastUsedTimestamp: 0,
      );
      expect(appZero.lastUsedFormatted, 'Not used today');
    });

    // 4. Usage Access unavailable handling
    test('4. Handles USAGE_DATA_UNAVAILABLE honestly without inventing numbers', () {
      final appRestricted = AppTelemetry(
        appName: 'PrivateApp',
        packageName: 'com.test.private',
        usageTodayMs: null,
        usageDataState: 'USAGE_DATA_UNAVAILABLE',
        usageAvailability: 'USAGE_DATA_UNAVAILABLE',
      );

      expect(appRestricted.usageTodayFormatted, 'Usage Access Required');
      expect(appRestricted.isUsageStatsAvailable, isFalse);

      final snapshot = DeviceSnapshot.fromAppTelemetryList([appRestricted]);
      expect(snapshot.isUsageAccessGranted, isFalse);

      final context = DeviceInventoryContext();
      context.updateApps([appRestricted]);
      final result = context.retrieveEvidence('Which apps did I use the most today?');
      expect(result.evidencePromptBlock, contains('USAGE_DATA_UNAVAILABLE'));
      expect(result.evidencePromptBlock, contains('PACKAGE_USAGE_STATS permission is not granted'));
    });

    // 5. Usage query retrieval
    test('5. Retrieves verified usage facts for specific app queries', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final yt = AppTelemetry(
        appName: 'YouTube',
        packageName: 'com.google.android.youtube',
        usageTodayMs: 5040000,
        lastUsedTimestamp: nowMs - 600000,
        usageDataState: 'AVAILABLE',
        usageAvailability: 'VALID',
      );
      final wa = AppTelemetry(
        appName: 'WhatsApp',
        packageName: 'com.whatsapp',
        usageTodayMs: 1800000,
        lastUsedTimestamp: nowMs - 120000,
        usageDataState: 'AVAILABLE',
        usageAvailability: 'VALID',
      );

      final context = DeviceInventoryContext();
      context.updateApps([yt, wa]);

      final result = context.retrieveEvidence('How much time did I use YouTube today?');
      expect(result.intent, QueryIntent.appUsageQuery);
      expect(result.targetApp?.appName, 'YouTube');
      expect(result.evidencePromptBlock, contains('1h 24m'));
      expect(result.evidencePromptBlock, contains('5040000 ms'));
      expect(result.evidencePromptBlock, contains('AVAILABLE'));
    });

    // 6. Top-used apps retrieval
    test('6. Deterministically sorts and returns top-used apps today', () {
      final app1 = AppTelemetry(
        appName: 'App1',
        packageName: 'com.test.app1',
        usageTodayMs: 600000, // 10m
        usageDataState: 'AVAILABLE',
      );
      final app2 = AppTelemetry(
        appName: 'App2',
        packageName: 'com.test.app2',
        usageTodayMs: 3600000, // 1h
        usageDataState: 'AVAILABLE',
      );
      final app3 = AppTelemetry(
        appName: 'App3',
        packageName: 'com.test.app3',
        usageTodayMs: 1800000, // 30m
        usageDataState: 'AVAILABLE',
      );

      final snapshot = DeviceSnapshot.fromAppTelemetryList([app1, app2, app3]);
      final top = snapshot.getTopUsedApps(limit: 3);

      expect(top.length, 3);
      expect(top[0].appName, 'App2'); // 1h
      expect(top[1].appName, 'App3'); // 30m
      expect(top[2].appName, 'App1'); // 10m

      final context = DeviceInventoryContext();
      context.updateApps([app1, app2, app3]);
      final queryResult = context.retrieveEvidence('Which apps did I use the most today?');
      expect(queryResult.intent, QueryIntent.topUsageApps);
      expect(queryResult.evidencePromptBlock, contains('1. App2'));
      expect(queryResult.evidencePromptBlock, contains('2. App3'));
      expect(queryResult.evidencePromptBlock, contains('3. App1'));
    });

    // 7. Unused apps retrieval
    test('7. Identifies apps with 0 usage today', () {
      final usedApp = AppTelemetry(
        appName: 'UsedApp',
        packageName: 'com.test.used',
        usageTodayMs: 300000,
        usageDataState: 'AVAILABLE',
      );
      final unusedApp1 = AppTelemetry(
        appName: 'UnusedApp1',
        packageName: 'com.test.unused1',
        usageTodayMs: 0,
        usageDataState: 'AVAILABLE',
      );
      final unusedApp2 = AppTelemetry(
        appName: 'UnusedApp2',
        packageName: 'com.test.unused2',
        usageTodayMs: 0,
        usageDataState: 'AVAILABLE',
      );

      final snapshot = DeviceSnapshot.fromAppTelemetryList([usedApp, unusedApp1, unusedApp2]);
      final unused = snapshot.getUnusedAppsToday();

      expect(unused.length, 2);
      expect(unused.map((a) => a.appName).toSet(), {'UnusedApp1', 'UnusedApp2'});

      final context = DeviceInventoryContext();
      context.updateApps([usedApp, unusedApp1, unusedApp2]);
      final queryResult = context.retrieveEvidence('Which apps have not been used today?');
      expect(queryResult.intent, QueryIntent.unusedAppsQuery);
      expect(queryResult.evidencePromptBlock, contains('TOTAL UNUSED APPS TODAY: 2'));
      expect(queryResult.evidencePromptBlock, contains('UnusedApp1'));
      expect(queryResult.evidencePromptBlock, contains('UnusedApp2'));
    });

    // 8. Guardian usage query end-to-end
    test('8. askGuardian answers usage query using deterministic local evidence', () async {
      final guardian = GuardianService();
      final yt = AppTelemetry(
        appName: 'YouTube',
        packageName: 'com.google.android.youtube',
        usageTodayMs: 5040000,
        usageDataState: 'AVAILABLE',
        usageAvailability: 'VALID',
      );
      guardian.updateTelemetryContext([yt]);

      final reply = await guardian.askGuardian('How much time did I use YouTube today?');
      expect(reply.isUser, isFalse);
      expect(reply.text, isNotEmpty);
      expect(reply.decision?.observedEvidence, isNotNull);
    });

    // 9. Generic greeting does not inject unrelated targetApp telemetry
    test('9. Saying "hi" or "hello" does NOT inject QualifiedNetworksService or any other targetApp', () async {
      final guardian = GuardianService();
      final qns = AppTelemetry(
        appName: 'QualifiedNetworksService',
        packageName: 'com.android.qns',
        usageTodayMs: 0,
        usageDataState: 'AVAILABLE',
      );
      final yt = AppTelemetry(
        appName: 'YouTube',
        packageName: 'com.google.android.youtube',
        usageTodayMs: 5040000,
        usageDataState: 'AVAILABLE',
      );

      // QualifiedNetworksService is the first app in the telemetry list
      guardian.updateTelemetryContext([qns, yt]);

      final replyHi = await guardian.askGuardian('hi');
      expect(replyHi.text.toLowerCase(), isNot(contains('qualifiednetworksservice')));
      expect(replyHi.decision?.userFacingExplanation.toLowerCase(), isNot(contains('qualifiednetworksservice')));
      expect(replyHi.text.toLowerCase(), contains('privacy sentinel'));

      final replyHello = await guardian.askGuardian('hello');
      expect(replyHello.text.toLowerCase(), isNot(contains('qualifiednetworksservice')));
      expect(replyHello.text.toLowerCase(), contains('privacy sentinel'));
    });

    // 10. Previous targetApp context is cleared for unrelated queries
    test('10. Preloaded targetApp context does not leak into general or greeting queries', () async {
      final guardian = GuardianService();
      final wa = AppTelemetry(
        appName: 'WhatsApp',
        packageName: 'com.whatsapp',
        usageTodayMs: 1200000,
        usageDataState: 'AVAILABLE',
      );
      guardian.updateTelemetryContext([wa]);

      // 1. Specific app query
      final replyWa = await guardian.askGuardian('How long was WhatsApp used today?');
      expect(replyWa.decision, isNotNull);

      // 2. Generic greeting immediately following app query
      final replyGreeting = await guardian.askGuardian('hi');
      expect(replyGreeting.text.toLowerCase(), isNot(contains('whatsapp')));
      expect(replyGreeting.decision?.userFacingExplanation.toLowerCase(), isNot(contains('whatsapp')));
    });

    // 11. Device reconnection clears old usage data
    test('11. resetDeviceContext clears cached telemetry and snapshot', () {
      final guardian = GuardianService();
      final app = AppTelemetry(
        appName: 'OldDeviceApp',
        packageName: 'com.old.app',
        usageTodayMs: 999999,
        usageDataState: 'AVAILABLE',
      );
      guardian.updateTelemetryContext([app]);
      expect(guardian.inventoryContext.appCount, 1);

      // Device disconnects
      guardian.resetDeviceContext();
      expect(guardian.inventoryContext.appCount, 0);
      expect(guardian.inventoryContext.currentSnapshot, isNull);
    });

    // 12. Local-first retrieval ensures compact verified evidence block before LLM
    test('12. Local-first retrieval builds compact evidence block without hallucinations', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final ig = AppTelemetry(
        appName: 'Instagram',
        packageName: 'com.instagram.android',
        usageTodayMs: 2700000, // 45m
        lastUsedTimestamp: nowMs - (15 * 60 * 1000), // 15m ago
        usageDataState: 'AVAILABLE',
        usageAvailability: 'VALID',
        grantedPermissions: ['android.permission.CAMERA', 'android.permission.READ_MEDIA_IMAGES'],
      );

      final context = DeviceInventoryContext();
      context.updateApps([ig]);

      final retrieval = context.retrieveEvidence('How long was Instagram used today?');
      expect(retrieval.intent, QueryIntent.appUsageQuery);
      expect(retrieval.evidencePromptBlock, contains('TARGET APP: Instagram'));
      expect(retrieval.evidencePromptBlock, contains('TODAY\'S FOREGROUND TIME: 45m (2700000 ms)'));
      expect(retrieval.evidencePromptBlock, contains('LAST USED: 15m ago'));
      expect(retrieval.evidencePromptBlock, contains('USAGE DATA STATE: AVAILABLE'));
    });

    // 13. When last used app query is asked, returns most recent app
    test('13. Answers last used app query with the highest lastUsedTimestamp', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final appA = AppTelemetry(
        appName: 'AppA',
        packageName: 'com.test.a',
        lastUsedTimestamp: now - 3600000, // 1h ago
        usageTodayMs: 1000,
        usageDataState: 'AVAILABLE',
      );
      final appB = AppTelemetry(
        appName: 'AppB',
        packageName: 'com.test.b',
        lastUsedTimestamp: now - 60000, // 1m ago
        usageTodayMs: 2000,
        usageDataState: 'AVAILABLE',
      );

      final context = DeviceInventoryContext();
      context.updateApps([appA, appB]);

      final retrieval = context.retrieveEvidence('Which app did I use last?');
      expect(retrieval.intent, QueryIntent.lastUsedQuery);
      expect(retrieval.targetApp?.appName, 'AppB');
      expect(retrieval.evidencePromptBlock, contains('MOST RECENTLY USED APP: AppB'));
    });
  });
}
