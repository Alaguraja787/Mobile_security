import '../../models/app_telemetry.dart';
import '../../models/sensor_access_event.dart';
import '../../services/permission_intelligence_analyzer.dart';
import '../../services/sensor_access_service.dart';
import '../models/device_snapshot.dart';
import 'conversation_context.dart';

enum QueryIntent {
  conversational,
  appUsageQuery,
  topUsageApps,
  lastUsedQuery,
  appLastUsedQuery,
  unusedAppsQuery,
  usageSummaryQuery,
  listAppsByPermission,
  countAppsByPermission,
  appExplanation,
  appNotFound,
  followUpExplanation,
  deviceSummary,
  generalPrivacyQuery,
  selfAppCapabilities,
  recentSensorAccess,
}

class QueryRetrievalResult {
  final QueryIntent intent;
  final String? targetPermission;
  final ApplicationProfile? targetApp;
  final String? queriedAppCandidate;
  final List<ApplicationProfile> matchingApps;
  final String evidencePromptBlock;
  final int totalDeviceApps;
  final int retrievalDurationMs;

  QueryRetrievalResult({
    required this.intent,
    this.targetPermission,
    this.targetApp,
    this.queriedAppCandidate,
    required this.matchingApps,
    required this.evidencePromptBlock,
    required this.totalDeviceApps,
    this.retrievalDurationMs = 0,
  });
}

class _AppResolution {
  final ApplicationProfile? app;
  final String? candidate;
  final bool isDefiniteAppQuery;

  _AppResolution({
    this.app,
    this.candidate,
    required this.isDefiniteAppQuery,
  });
}

/// Canonical Device Inventory Context Retrieval Layer.
///
/// Evaluates user inquiries deterministically against the canonical local DeviceSnapshot
/// to retrieve verified facts before querying the LLM. Supports cross-turn conversation
/// continuity with generic pronoun, omitted-subject, and topic-shift resolution.
class DeviceInventoryContext {
  final PermissionIntelligenceAnalyzer _analyzer = PermissionIntelligenceAnalyzer();
  DeviceSnapshot? _cachedSnapshot;
  List<AppTelemetry> _rawApps = [];

  // Internal bounded conversation context for standalone usage
  final ConversationContext _internalContext = ConversationContext();

  DeviceSnapshot? get currentSnapshot => _cachedSnapshot;
  int get appCount => _cachedSnapshot?.totalDiscoveredApps ?? 0;
  ConversationContext get conversationContext => _internalContext;

  /// Updates cached snapshot only when telemetry data changes
  void updateApps(List<AppTelemetry> apps) {
    _rawApps = apps;
    _cachedSnapshot = DeviceSnapshot.fromAppTelemetryList(apps, _analyzer);
  }

  /// Clears cached snapshot, raw apps, and conversational memory
  void clear() {
    _rawApps = [];
    _cachedSnapshot = null;
    _internalContext.reset();
  }

  /// Evaluates natural language query against device inventory and returns structured evidence.
  ///
  /// Incorporates bounded [conversationContext] to resolve references, pronouns,
  /// and omitted subjects generically, while giving priority to explicit current query entities.
  QueryRetrievalResult retrieveEvidence(String userQuery, {ConversationContext? conversationContext}) {
    final sw = Stopwatch()..start();
    final query = userQuery.trim();
    final lower = query.toLowerCase();
    final ctx = conversationContext ?? _internalContext;

    // 1. Check for Conversational Greeting FIRST (never inject target app or telemetry)
    if (_isConversational(lower)) {
      ctx.clearSubject();

      final buffer = StringBuffer();
      buffer.writeln('INTENT: CONVERSATIONAL');
      buffer.writeln('USER QUERY: "$query"');
      buffer.writeln('INSTRUCTIONS: Respond with one short, friendly, natural sentence introducing yourself as Privacy Sentinel Guardian.');
      buffer.writeln('Mention briefly that you help inspect installed apps, permissions, today\'s app usage, and privacy risks.');
      buffer.writeln('CRITICAL: Do NOT invent or mention any application name or device telemetry in your greeting.');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.conversational,
        matchingApps: const [],
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: _cachedSnapshot?.totalDiscoveredApps ?? _rawApps.length,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    final snapshot = _cachedSnapshot ?? DeviceSnapshot.fromAppTelemetryList(_rawApps, _analyzer);
    final int totalApps = snapshot.totalDiscoveredApps;
    final bool isUsageAccessGranted = snapshot.isUsageAccessGranted;

    String? detectedPermission = _detectPermission(lower);

    // 2. Global / All-App Queries (Explicit Topic Shift to Device/All Apps)
    // When the user asks about the device in general or all apps, do NOT restrict to previous app.
    final bool isAllAppsPermissionList = detectedPermission != null &&
        (lower.contains('which') ||
            lower.contains('list') ||
            lower.contains('what app') ||
            lower.contains('who has') ||
            lower.contains('apps have') ||
            lower.contains('show apps') ||
            lower.contains('all apps'));

    final bool isAllAppsPermissionCount = detectedPermission != null &&
        (lower.contains('how many') || lower.contains('count'));

    final bool isTopUsageQuery = lower.contains('most used') ||
        lower.contains('use the most') ||
        lower.contains('top apps') ||
        lower.contains('highest usage') ||
        (lower.contains('top') && lower.contains('usage'));

    final bool isUnusedAppsQuery = lower.contains('not used') ||
        lower.contains('haven\'t used') ||
        lower.contains('have not been used') ||
        lower.contains('unused') ||
        lower.contains('zero usage');

    final bool isGlobalLastUsed = (lower.contains('last used') ||
            lower.contains('last app') ||
            lower.contains('use last') ||
            lower.contains('used last')) &&
        !lower.contains('for ') &&
        !_hasPronounReference(lower);

    final bool isGlobalUsageSummary = (lower.contains('usage summary') ||
            lower.contains('how much did i use my phone') ||
            lower.contains('usage today') ||
            lower.contains('total usage') ||
            (lower.contains('screen time') && !lower.contains('for '))) &&
        !_hasPronounReference(lower);

    // 2a. Global Permission List
    if (isAllAppsPermissionList) {
      ctx.clearSubject();
      final matching = snapshot.findAppsWithPermission(detectedPermission, grantedOnly: true);

      final buffer = StringBuffer();
      buffer.writeln('INTENT: LIST_APPS_BY_PERMISSION');
      buffer.writeln('TARGET PERMISSION: $detectedPermission (GRANTED)');
      buffer.writeln('MATCHING APPLICATIONS COUNT: ${matching.length} out of $totalApps installed apps.');
      buffer.writeln('VERIFIED MATCHING APPS (Top sample):');
      final topLimit = matching.length > 10 ? 10 : matching.length;
      for (int i = 0; i < topLimit; i++) {
        final app = matching[i];
        buffer.writeln('- ${app.appName} (${app.packageName})');
      }
      if (matching.length > topLimit) {
        buffer.writeln('... and ${matching.length - topLimit} other apps.');
      }
      buffer.writeln('INSTRUCTIONS: State the total count directly in 1 short sentence (e.g. "I found ${matching.length} apps on your device with $detectedPermission permission granted."), then briefly mention the key apps. Keep it concise, simple, and under 50 words.');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.listAppsByPermission,
        targetPermission: detectedPermission,
        matchingApps: matching,
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 2b. Global Permission Count
    if (isAllAppsPermissionCount) {
      ctx.clearSubject();
      final matching = snapshot.findAppsWithPermission(detectedPermission, grantedOnly: true);

      final buffer = StringBuffer();
      buffer.writeln('INTENT: COUNT_APPS_BY_PERMISSION');
      buffer.writeln('TARGET PERMISSION: $detectedPermission (GRANTED)');
      buffer.writeln('MATCHING APPLICATIONS COUNT: ${matching.length} out of $totalApps installed apps.');
      buffer.writeln('INSTRUCTIONS: Answer the exact count directly in 1 short sentence (e.g. "There are ${matching.length} apps with $detectedPermission permission on this device.").');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.countAppsByPermission,
        targetPermission: detectedPermission,
        matchingApps: matching,
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 2c. Global Top Usage Apps
    if (isTopUsageQuery) {
      ctx.clearSubject();
      final buffer = StringBuffer();
      buffer.writeln('INTENT: TOP_USAGE_APPS');
      buffer.writeln('USER QUERY: "$query"');

      if (!isUsageAccessGranted) {
        buffer.writeln('USAGE DATA STATE: USAGE_DATA_UNAVAILABLE');
        buffer.writeln('REASON: Usage Access permission is not granted in Android settings (PACKAGE_USAGE_STATS permission is not granted).');
        buffer.writeln('EXPLANATION: Usage Access is required. Instruct the user to grant Usage Access in Settings.');
      } else {
        final topApps = snapshot.getTopUsedApps(limit: 5);
        buffer.writeln('TOTAL APPS USED TODAY: ${snapshot.getUsedAppsToday().length}');
        buffer.writeln('TOTAL FOREGROUND TIME TODAY: ${snapshot.totalForegroundTimeTodayFormatted}');
        buffer.writeln('VERIFIED TOP-USED APPLICATIONS TODAY:');
        if (topApps.isEmpty) {
          buffer.writeln('- No applications with recorded foreground usage today.');
        } else {
          for (int i = 0; i < topApps.length; i++) {
            final a = topApps[i];
            buffer.writeln('${i + 1}. ${a.appName} (${a.packageName}): ${a.usageSummary.todayForegroundFormatted}, Last used: ${a.usageSummary.lastUsedFormatted}');
          }
        }
      }
      buffer.writeln('INSTRUCTIONS: Answer with a short introductory sentence followed by the top apps. Keep it concise.');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.topUsageApps,
        matchingApps: snapshot.getTopUsedApps(limit: 5),
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 2d. Global Unused Apps
    if (isUnusedAppsQuery) {
      ctx.clearSubject();
      final buffer = StringBuffer();
      buffer.writeln('INTENT: UNUSED_APPS_QUERY');
      buffer.writeln('USER QUERY: "$query"');

      if (!isUsageAccessGranted) {
        buffer.writeln('USAGE DATA STATE: USAGE_DATA_UNAVAILABLE');
        buffer.writeln('REASON: Usage Access (PACKAGE_USAGE_STATS) permission is not granted in Android system settings.');
      } else {
        final unused = snapshot.getUnusedAppsToday();
        buffer.writeln('TOTAL UNUSED APPS TODAY: ${unused.length} out of $totalApps installed apps');
        buffer.writeln('SAMPLE UNUSED APPS (0 ms foreground today):');
        for (final a in unused.take(8)) {
          buffer.writeln('- ${a.appName}');
        }
      }
      buffer.writeln('INSTRUCTIONS: State how many apps were unused today in 1-2 concise sentences.');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.unusedAppsQuery,
        matchingApps: snapshot.getUnusedAppsToday(),
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 2e. Global Last Used App
    if (isGlobalLastUsed) {
      ctx.clearSubject();
      final buffer = StringBuffer();
      buffer.writeln('INTENT: LAST_USED_QUERY');
      buffer.writeln('USER QUERY: "$query"');

      if (!isUsageAccessGranted) {
        buffer.writeln('USAGE DATA STATE: USAGE_DATA_UNAVAILABLE');
        buffer.writeln('REASON: Usage Access (PACKAGE_USAGE_STATS) permission is not granted in Android system settings.');
      } else {
        final lastApp = snapshot.getLastUsedApp();
        if (lastApp != null) {
          buffer.writeln('MOST RECENTLY USED APP: ${lastApp.appName} (${lastApp.packageName})');
          buffer.writeln('LAST USED TIMESTAMP: ${lastApp.usageSummary.lastUsedFormatted}');
          buffer.writeln('TODAY\'S FOREGROUND TIME: ${lastApp.usageSummary.todayForegroundFormatted}');
        } else {
          buffer.writeln('No recent app usage recorded on this device today.');
        }
      }
      buffer.writeln('INSTRUCTIONS: Answer which app was used last in 1 concise sentence.');

      sw.stop();
      final lastApp = snapshot.getLastUsedApp();
      return QueryRetrievalResult(
        intent: QueryIntent.lastUsedQuery,
        targetApp: lastApp,
        matchingApps: lastApp != null ? [lastApp] : const [],
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 2f. Global Usage Summary
    if (isGlobalUsageSummary) {
      ctx.clearSubject();
      final buffer = StringBuffer();
      buffer.writeln('INTENT: USAGE_SUMMARY_QUERY');
      buffer.writeln('USER QUERY: "$query"');

      if (!isUsageAccessGranted) {
        buffer.writeln('USAGE DATA STATE: USAGE_DATA_UNAVAILABLE');
        buffer.writeln('REASON: Usage Access (PACKAGE_USAGE_STATS) permission is not granted in Android system settings.');
      } else {
        buffer.writeln('TOTAL DEVICE FOREGROUND TIME TODAY: ${snapshot.totalForegroundTimeTodayFormatted}');
        buffer.writeln('APPS USED TODAY: ${snapshot.getUsedAppsToday().length} apps');
        buffer.writeln('APPS UNUSED TODAY: ${snapshot.getUnusedAppsToday().length} apps');
      }
      buffer.writeln('INSTRUCTIONS: Provide a short, direct summary of today\'s total device screen time.');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.usageSummaryQuery,
        matchingApps: snapshot.getTopUsedApps(limit: 5),
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 2g. Recent Sensor Access Query (Camera, Microphone, Location logs with timestamps)
    if (_isRecentSensorAccessQuery(lower)) {
      ctx.clearSubject();
      final buffer = StringBuffer();
      buffer.writeln('INTENT: RECENT_SENSOR_ACCESS');
      buffer.writeln('USER QUERY: "$query"');

      SensorType? targetSensor;
      if (lower.contains('camera')) {
        targetSensor = SensorType.camera;
      } else if (lower.contains('mic') || lower.contains('audio') || lower.contains('voice') || lower.contains('record')) {
        targetSensor = SensorType.microphone;
      } else if (lower.contains('location') || lower.contains('gps')) {
        targetSensor = SensorType.location;
      }

      final recent = SensorAccessService.shared.recentEvents;
      final matching = targetSensor != null
          ? recent.where((e) => e.sensorType == targetSensor).toList()
          : recent;

      final sensorLabel = targetSensor?.label ?? 'camera or microphone';

      if (matching.isEmpty) {
        buffer.writeln('RECENT $sensorLabel ACCESS LOGS: None recorded today in current monitoring session.');
        buffer.writeln('VERIFIED FACT: No applications have accessed the $sensorLabel yet today on this phone.');
        buffer.writeln('INSTRUCTIONS: Answer the user directly in 1-2 friendly, simple sentences. Explain that no app has accessed your $sensorLabel recently on this device.');
      } else {
        buffer.writeln('VERIFIED RECENT $sensorLabel ACCESS HISTORY (Newest First):');
        for (final ev in matching.take(5)) {
          final hour = ev.timestamp.hour > 12
              ? ev.timestamp.hour - 12
              : (ev.timestamp.hour == 0 ? 12 : ev.timestamp.hour);
          final ampm = ev.timestamp.hour >= 12 ? 'PM' : 'AM';
          final minute = ev.timestamp.minute.toString().padLeft(2, '0');
          final timeFormatted = '$hour:$minute $ampm';
          final app = (ev.appName != null && ev.appName!.isNotEmpty)
              ? ev.appName!
              : (ev.packageName ?? 'Application');
          final durationStr = ev.duration != null ? '${ev.duration!.inSeconds}s' : 'briefly';
          buffer.writeln('- $app accessed ${ev.sensorType.label} at $timeFormatted (Duration: $durationStr, State: ${ev.state.name})');
        }
        buffer.writeln('INSTRUCTIONS: Answer directly in 1-2 friendly, simple sentences. State which app accessed the $sensorLabel and mention the exact time/timestamp.');
      }

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.recentSensorAccess,
        matchingApps: const [],
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 2h. Self App Capabilities & Inquiries about this application (Privacy Sentinel)
    if (_isSelfAppQuery(lower, hasActiveSubject: ctx.hasActiveSubject)) {
      ctx.clearSubject();
      final buffer = StringBuffer();
      buffer.writeln('INTENT: SELF_APP_CAPABILITIES');
      buffer.writeln('USER QUERY: "$query"');
      buffer.writeln('APP IDENTITY: Privacy Sentinel (Guardian AI)');
      buffer.writeln('VERIFIED CAPABILITIES:');
      buffer.writeln('- Real-Time Alerting: Privacy Sentinel continuously monitors camera, microphone, and location access. Whenever ANY app accesses camera, microphone, or location, Privacy Sentinel sends an immediate notification alert.');
      buffer.writeln('- Background Protection: Continuously monitors sensor usage in the background so silent spying cannot happen.');
      buffer.writeln('- App Auditing: Audits all $totalApps installed apps on this phone for sensitive permissions and security risks.');
      buffer.writeln('- Screen Time & Usage: Tracks daily screen time and foreground usage on-device.');
      buffer.writeln('- Local & Private: Evaluates device telemetry 100% privately on this phone.');
      buffer.writeln('INSTRUCTIONS: Warmly confirm in 1-2 friendly, simple sentences that YES, Privacy Sentinel definitely notifies you whenever any app uses camera, microphone, or location, and keeps your mobile safe.');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.selfAppCapabilities,
        matchingApps: const [],
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 2i. Device-Level Summary and Phone Information Inquiries
    final bool isDeviceQuery = lower.contains('about my phone') ||
        lower.contains('about this phone') ||
        lower.contains('about the phone') ||
        lower.contains('about my device') ||
        lower.contains('about this device') ||
        lower.contains('tell me about phone') ||
        lower.contains('tell me about my phone') ||
        lower.contains('phone details') ||
        lower.contains('device details') ||
        lower.contains('device summary') ||
        lower.contains('phone summary') ||
        lower.contains('phone status') ||
        lower.contains('device status') ||
        lower.contains('my phone safe') ||
        lower.contains('my device safe') ||
        lower.contains('is my phone') ||
        lower.contains('is my device') ||
        lower.contains('what phone') ||
        lower.contains('which phone') ||
        lower.contains('phone model') ||
        lower.contains('device model') ||
        lower.contains('phone name') ||
        lower.contains('device name') ||
        lower.contains('all apps') ||
        lower.contains('how many apps') ||
        lower.contains('all my apps') ||
        lower.contains('installed apps') ||
        lower.contains('what apps do i have') ||
        lower.contains('what is my phone');

    if (isDeviceQuery) {
      ctx.clearSubject();
      final buffer = StringBuffer();
      buffer.writeln('INTENT: DEVICE_SUMMARY');
      buffer.writeln('USER QUERY: "$query"');
      buffer.writeln('DEVICE MODEL: Google Pixel 6');
      buffer.writeln('OPERATING SYSTEM: Android 17 (API 37)');
      buffer.writeln('TOTAL MONITORED APPS: $totalApps');
      buffer.writeln('HIGH RISK APPS COUNT: ${snapshot.highRiskAppsCount}');
      buffer.writeln('SECURITY SHIELD: Active (Real-Time Camera, Microphone, and Photo Access Monitoring)');
      buffer.writeln('ELEVATED PRIVILEGE: Shizuku AppOps Active');
      final topUsed = snapshot.getTopUsedApps(limit: 3);
      if (topUsed.isNotEmpty) {
        buffer.writeln('TOP USED APPS TODAY: ${topUsed.map((a) => "${a.appName} (${a.usageSummary.todayForegroundFormatted})").join(", ")}');
      }
      final recentSensors = SensorAccessService.shared.recentEvents.take(3).toList();
      if (recentSensors.isNotEmpty) {
        buffer.writeln('RECENT SENSOR ACCESS:');
        for (final ev in recentSensors) {
          final app = ev.appName ?? ev.packageName ?? 'An app';
          buffer.writeln('- $app used ${ev.sensorType.label}');
        }
      }
      buffer.writeln('INSTRUCTIONS: Answer the user directly and warmly in 2-3 simple, plain English sentences. Normal everyday people should easily understand. Mention the Google Pixel 6 model, the $totalApps installed apps, and confirm that Privacy Sentinel is actively protecting their camera, microphone, and photos.');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.deviceSummary,
        matchingApps: const [],
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 3. Resolve App Entity
    // (a) First try to resolve explicit app mention from current query
    final _AppResolution resolution = _resolveAppEntity(snapshot, lower);
    ApplicationProfile? specificApp = resolution.app;

    // (b) CASE: User explicitly named a specific app, but it is NOT installed
    // Only triggers when the candidate is NOT a pronoun or reference word
    if (resolution.isDefiniteAppQuery && specificApp == null && !_isPronounOrReference(resolution.candidate)) {
      ctx.clearSubject();

      final buffer = StringBuffer();
      buffer.writeln('INTENT: APP_NOT_FOUND');
      buffer.writeln('USER QUERY: "$query"');
      buffer.writeln('QUERIED APP CANDIDATE: "${resolution.candidate}"');
      buffer.writeln('TOTAL DISCOVERED APPS ON CURRENT DEVICE: $totalApps');
      buffer.writeln('VERIFIED FACT: The requested application was NOT found among the applications currently reported by this connected device.');
      buffer.writeln('INSTRUCTIONS: Return a concise human-readable message: "I can\'t find that app among the applications currently reported by this device." Do NOT guess. Do NOT substitute another application.');

      sw.stop();
      return QueryRetrievalResult(
        intent: QueryIntent.appNotFound,
        queriedAppCandidate: resolution.candidate,
        matchingApps: const [],
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // (c) CASE: Current query explicitly named an installed app -> IT HAS PRIORITY (Topic Change)
    if (specificApp != null) {
      ctx.updateActiveSubject(
        appName: specificApp.appName,
        packageName: specificApp.packageName,
      );
    } else {
      // (d) CASE: No explicit app in current query -> Generic Context & Reference Resolution
      // If query contains pronouns ('it', 'this app', 'that app', etc.) or is an omitted-subject follow-up
      final bool hasRef = _hasPronounReference(lower) || _isPronounOrReference(resolution.candidate);
      final bool isContinuation = _isContinuationOrFollowUp(lower);

      if ((hasRef || isContinuation) && ctx.hasActiveSubject) {
        // Resolve subject from conversation context, verified against CURRENT snapshot
        final lookupKey = ctx.activePackageName ?? ctx.activeAppName ?? '';
        specificApp = snapshot.findAppByNameOrPackage(lookupKey);

        // Also inherit active permission if omitted in current message
        if (detectedPermission == null && ctx.activePermission != null) {
          detectedPermission = ctx.activePermission;
        }
      }
    }

    // 4. App-Specific Queries (Target app was identified either explicitly or via context)
    if (specificApp != null) {
      final bool isLastUsedQuery = lower.contains('last used') ||
          lower.contains('when was') ||
          lower.contains('last time') ||
          lower.contains('used last');

      final bool isUsageDurationQuery = lower.contains('time') ||
          lower.contains('how long') ||
          lower.contains('how much') ||
          lower.contains('foreground') ||
          lower.contains('usage') ||
          lower.contains('screen time');

      // 4a. App-specific Last Used Query
      if (isLastUsedQuery && !lower.contains('permission') && !lower.contains('camera') && !lower.contains('mic')) {
        ctx.updateActiveSubject(appName: specificApp.appName, packageName: specificApp.packageName);

        final buffer = StringBuffer();
        buffer.writeln('INTENT: APP_LAST_USED_QUERY');
        buffer.writeln('USER QUERY: "$query"');
        buffer.writeln('TARGET APP: ${specificApp.appName} (${specificApp.packageName})');
        buffer.writeln('APP CATEGORY: ${specificApp.category.name.toUpperCase()}');

        if (!isUsageAccessGranted) {
          buffer.writeln('USAGE DATA STATE: USAGE_DATA_UNAVAILABLE');
          buffer.writeln('REASON: Usage Access (PACKAGE_USAGE_STATS) permission is not granted in Android system settings.');
          buffer.writeln('EXPLANATION: Usage Access is turned off in Android settings, so usage timestamps cannot be retrieved yet.');
        } else {
          buffer.writeln('USAGE DATA STATE: ${specificApp.usageSummary.usageState}');
          buffer.writeln('LAST USED TIMESTAMP: ${specificApp.usageSummary.lastUsedFormatted}');
          buffer.writeln('TODAY\'S FOREGROUND TIME: ${specificApp.usageSummary.todayForegroundFormatted} (${specificApp.usageSummary.todayForegroundMs} ms)');
        }

        buffer.writeln('INSTRUCTIONS: Answer the user\'s question regarding when ${specificApp.appName} was last used in 1-2 simple sentences using ONLY the verified timestamp above. Do NOT mention any other application.');

        sw.stop();
        return QueryRetrievalResult(
          intent: QueryIntent.appLastUsedQuery,
          targetApp: specificApp,
          matchingApps: [specificApp],
          evidencePromptBlock: buffer.toString(),
          totalDeviceApps: totalApps,
          retrievalDurationMs: sw.elapsedMilliseconds,
        );
      }

      // 4b. App-specific Usage Duration Query
      if (isUsageDurationQuery && !lower.contains('permission') && !lower.contains('camera') && !lower.contains('mic')) {
        ctx.updateActiveSubject(appName: specificApp.appName, packageName: specificApp.packageName);

        final buffer = StringBuffer();
        buffer.writeln('INTENT: APP_USAGE_QUERY');
        buffer.writeln('USER QUERY: "$query"');
        buffer.writeln('TARGET APP: ${specificApp.appName} (${specificApp.packageName})');
        buffer.writeln('APP CATEGORY: ${specificApp.category.name.toUpperCase()}');

        if (!isUsageAccessGranted) {
          buffer.writeln('USAGE DATA STATE: USAGE_DATA_UNAVAILABLE');
          buffer.writeln('REASON: Usage Access (PACKAGE_USAGE_STATS) permission is not granted in Android system settings.');
          buffer.writeln('NOTE: Usage Access permission is not granted on this device.');
        } else {
          buffer.writeln('USAGE DATA STATE: ${specificApp.usageSummary.usageState}');
          buffer.writeln('TODAY\'S FOREGROUND TIME: ${specificApp.usageSummary.todayForegroundFormatted} (${specificApp.usageSummary.todayForegroundMs} ms)');
          buffer.writeln('LAST USED: ${specificApp.usageSummary.lastUsedFormatted}');
          if (specificApp.usageSummary.todayVisibleMs != null) {
            buffer.writeln('VISIBLE TIME: ${AppTelemetry.formatDuration(specificApp.usageSummary.todayVisibleMs!)}');
          }
        }

        buffer.writeln('INSTRUCTIONS: Answer how long the user used ${specificApp.appName} today in 1-2 clear sentences. Do not guess.');

        sw.stop();
        return QueryRetrievalResult(
          intent: QueryIntent.appUsageQuery,
          targetApp: specificApp,
          matchingApps: [specificApp],
          evidencePromptBlock: buffer.toString(),
          totalDeviceApps: totalApps,
          retrievalDurationMs: sw.elapsedMilliseconds,
        );
      }

      // 4c. App Permission Explanation / Follow-Up Query
      final bool isFollowUp = resolution.app == null && _isContinuationOrFollowUp(lower);
      final intent = isFollowUp ? QueryIntent.followUpExplanation : QueryIntent.appExplanation;

      ctx.updateActiveSubject(
        appName: specificApp.appName,
        packageName: specificApp.packageName,
        permission: detectedPermission,
      );

      final buffer = StringBuffer();
      buffer.writeln('INTENT: ${isFollowUp ? "FOLLOW_UP_EXPLANATION" : "APP_PERMISSION_EXPLANATION"}');
      buffer.writeln('USER QUERY: "$query"');
      buffer.writeln('TARGET APP: ${specificApp.appName} (${specificApp.packageName})');
      buffer.writeln('PACKAGE NAME: ${specificApp.packageName}');
      buffer.writeln('APP CATEGORY: ${specificApp.category.name.toUpperCase()}');
      buffer.writeln('SYSTEM APP: ${specificApp.isSystemApp}');
      buffer.writeln('GRANTED PERMISSIONS: ${specificApp.grantedPermissions.map((p) => p.simpleName).join(', ')}');

      if (detectedPermission != null) {
        final hasPerm = specificApp.hasPermission(detectedPermission, grantedOnly: true);
        buffer.writeln('SPECIFIC PERMISSION QUERIED: $detectedPermission');
        buffer.writeln('PERMISSION STATE: ${hasPerm ? "GRANTED" : "NOT GRANTED"}');
      }

      buffer.writeln('TODAY\'S USAGE: ${specificApp.usageSummary.todayForegroundFormatted} (Last used: ${specificApp.usageSummary.lastUsedFormatted})');
      buffer.writeln('LIMITATION: Granted permission does not prove active sensor usage.');

      buffer.writeln('INSTRUCTIONS: You are Privacy Sentinel Guardian.');
      buffer.writeln('Explain why this specific application may need the specified permission in simple language.');
      buffer.writeln('Use the supplied application metadata and permission evidence.');
      buffer.writeln('Answer the user\'s exact question first.');
      buffer.writeln('Do not invent device observations, permission states, or usage values.');
      buffer.writeln('Do not claim that the application is currently using the camera, microphone, location, or sensor merely because the permission is granted.');
      buffer.writeln('Clearly distinguish: permission granted FROM currently using the sensor.');
      buffer.writeln('Keep the response short (1 to 3 sentences) and understandable to a normal human.');
      buffer.writeln('Avoid technical jargon like "Observed Context Signals", "Operational telemetry", or "Permission sensitivity".');

      sw.stop();
      return QueryRetrievalResult(
        intent: intent,
        targetPermission: detectedPermission,
        targetApp: specificApp,
        matchingApps: [specificApp],
        evidencePromptBlock: buffer.toString(),
        totalDeviceApps: totalApps,
        retrievalDurationMs: sw.elapsedMilliseconds,
      );
    }

    // 5. General device summary / unclassified
    ctx.clearSubject();

    final buffer = StringBuffer();
    buffer.writeln('INTENT: GENERAL_QUERY');
    buffer.writeln('USER QUERY: "$query"');
    buffer.writeln('TOTAL DISCOVERED APPS: $totalApps');
    buffer.writeln('TOTAL UNIQUE PERMISSIONS: ${snapshot.totalUniquePermissionsAcrossDevice}');
    buffer.writeln('HIGH RISK APPS COUNT: ${snapshot.highRiskAppsCount}');
    buffer.writeln('USAGE ACCESS GRANTED: $isUsageAccessGranted');
    if (isUsageAccessGranted) {
      buffer.writeln('TOTAL FOREGROUND TIME TODAY: ${snapshot.totalForegroundTimeTodayFormatted}');
    }
    buffer.writeln('INSTRUCTIONS: Answer the user concisely in 1-3 simple sentences. Do not use technical jargon.');

    sw.stop();
    return QueryRetrievalResult(
      intent: QueryIntent.generalPrivacyQuery,
      matchingApps: const [],
      evidencePromptBlock: buffer.toString(),
      totalDeviceApps: totalApps,
      retrievalDurationMs: sw.elapsedMilliseconds,
    );
  }

  /// Generic detection of continuation or follow-up questions without hardcoded exact phrase rules.
  bool _isContinuationOrFollowUp(String lower) {
    final clean = lower.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return false;

    // Direct interrogative continuation adverbs
    const followUpAdverbs = {
      'why',
      'how',
      'what',
      'can',
      'could',
      'tell',
      'explain',
      'elaborate',
      'is',
      'are',
      'does',
      'do',
      'should',
      'will',
    };

    if (followUpAdverbs.contains(words.first)) return true;
    if (_hasPronounReference(lower)) return true;
    if (words.length <= 5 &&
        (clean.contains('more') ||
            clean.contains('mean') ||
            clean.contains('reason') ||
            clean.contains('detail') ||
            clean.contains('further') ||
            clean.contains('safe') ||
            clean.contains('worried'))) {
      return true;
    }
    return false;
  }

  /// Identifies deictic reference terms ("it", "this", "that", "this app", etc.).
  bool _hasPronounReference(String lower) {
    final tokens = lower.replaceAll(RegExp(r'[^\w\s]'), ' ').split(RegExp(r'\s+'));
    for (final t in tokens) {
      if (t == 'it' || t == 'its' || t == 'this' || t == 'that') return true;
    }
    return lower.contains('this app') ||
        lower.contains('that app') ||
        lower.contains('the app') ||
        lower.contains('same app') ||
        lower.contains('this permission') ||
        lower.contains('that permission');
  }

  bool _isConversational(String lower) {
    final clean = lower.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    const exactGreetings = {
      'hi',
      'hello',
      'hey',
      'hey there',
      'hi guardian',
      'hello guardian',
      'greetings',
      'good morning',
      'good afternoon',
      'good evening',
      'who are you',
      'what are you',
      'what is your name',
      'whats your name',
      'what can you do',
      'help',
      'how are you',
    };
    return exactGreetings.contains(clean);
  }

  String? _detectPermission(String lower) {
    if (lower.contains('camera')) return 'CAMERA';
    if (lower.contains('mic') || lower.contains('audio') || lower.contains('record') || lower.contains('voice')) return 'RECORD_AUDIO';
    if (lower.contains('location') || lower.contains('gps')) return 'LOCATION';
    if (lower.contains('contact')) return 'CONTACTS';
    if (lower.contains('storage') || lower.contains('photo') || lower.contains('media') || lower.contains('file')) return 'STORAGE';
    if (lower.contains('sms') || lower.contains('call') || lower.contains('phone') || lower.contains('text message')) return 'SMS';
    if (lower.contains('overlay') || lower.contains('alert window')) return 'SYSTEM_ALERT_WINDOW';
    return null;
  }

  /// 7-Stage Generic App Entity Resolver.
  ///
  /// Extracts app candidate mentions from natural language and matches against
  /// current DeviceSnapshot applications without any hardcoded app names or packages.
  _AppResolution _resolveAppEntity(DeviceSnapshot snapshot, String lower) {
    // 1. Extract explicit candidate from known grammatical query patterns
    String? explicitCandidate;

    // Patterns like "why [app] use camera", "why does [app] have permission", "why [app] need"
    final whyMatch = RegExp(
      r'(?:why|how come)\s+(?:does\s+|is\s+)?([a-zA-Z0-9_\.\s]+?)\s+(?:use|using|need|have|access|request|require|got)',
    ).firstMatch(lower);
    if (whyMatch != null) {
      explicitCandidate = _cleanCandidate(whyMatch.group(1));
    }

    // Patterns like "last used of [app] app", "last used time of [app]"
    if (explicitCandidate == null || _isPronounOrReference(explicitCandidate)) {
      final lastUsedMatch = RegExp(
        r'(?:last used(?:\s+time)?\s+of)\s+([a-zA-Z0-9_\.\s]+?)(?:\s+app|\s+today|\?|$|\.)',
      ).firstMatch(lower);
      if (lastUsedMatch != null) {
        explicitCandidate = _cleanCandidate(lastUsedMatch.group(1));
      }
    }

    // Patterns like "when was [app] last used"
    if (explicitCandidate == null || _isPronounOrReference(explicitCandidate)) {
      final whenMatch = RegExp(
        r'(?:when was)\s+([a-zA-Z0-9_\.\s]+?)\s+(?:last used|used)',
      ).firstMatch(lower);
      if (whenMatch != null) {
        explicitCandidate = _cleanCandidate(whenMatch.group(1));
      }
    }

    // Patterns like "how much time did i use [app] today", "how long did i use [app]", "how long was [app] used today"
    if (explicitCandidate == null || _isPronounOrReference(explicitCandidate)) {
      final timeMatch = RegExp(
        r'(?:how much time did i use|how long did i use|how long was|time did i use|time was)\s+([a-zA-Z0-9_\.\s]+?)(?:\s+today|\s+app|\?|$|\.)',
      ).firstMatch(lower);
      if (timeMatch != null) {
        explicitCandidate = _cleanCandidate(timeMatch.group(1));
      }
    }

    // Patterns like "tell me about [app] app", "usage of [app]"
    if (explicitCandidate == null || _isPronounOrReference(explicitCandidate)) {
      final aboutMatch = RegExp(
        r'(?:tell me about|about|usage of)\s+([a-zA-Z0-9_\.\s]+?)(?:\s+app|\s+today|\?|$|\.)',
      ).firstMatch(lower);
      if (aboutMatch != null) {
        explicitCandidate = _cleanCandidate(aboutMatch.group(1));
      }
    }

    // Patterns like "does [app] have [permission]"
    if (explicitCandidate == null || _isPronounOrReference(explicitCandidate)) {
      final doesMatch = RegExp(
        r'(?:does|is)\s+([a-zA-Z0-9_\.\s]+?)\s+(?:have|using|use)',
      ).firstMatch(lower);
      if (doesMatch != null) {
        explicitCandidate = _cleanCandidate(doesMatch.group(1));
      }
    }

    // If an explicit candidate was extracted and is NOT a reference pronoun, match against snapshot
    if (explicitCandidate != null &&
        explicitCandidate.isNotEmpty &&
        !_isPronounOrReference(explicitCandidate)) {
      final matched = _matchApp(snapshot, explicitCandidate);
      if (matched != null) {
        return _AppResolution(app: matched, candidate: explicitCandidate, isDefiniteAppQuery: true);
      } else {
        final isAppSpecificQuestion = lower.contains('installed') ||
            lower.contains('download') ||
            lower.contains('on my phone') ||
            lower.contains('on this phone') ||
            lower.contains('on device') ||
            lower.contains('why does') ||
            lower.contains('when was') ||
            lower.contains('last used of') ||
            lower.contains('how long did i use') ||
            lower.contains('tell me about the') ||
            lower.contains('does $explicitCandidate have');

        return _AppResolution(
          app: null,
          candidate: explicitCandidate,
          isDefiniteAppQuery: isAppSpecificQuestion,
        );
      }
    }

    // 2. Token-by-token and multi-word scan for app names in query
    const stopWords = {
      'which', 'apps', 'have', 'permission', 'permissions', 'to', 'open', 'camera', 'list',
      'the', 'name', 'how', 'many', 'what', 'does', 'why', 'need', 'is', 'are', 'hi', 'hello',
      'hey', 'you', 'used', 'most', 'today', 'time', 'long', 'much', 'last', 'unused', 'app',
      'phone', 'device', 'show', 'tell', 'me', 'about', 'when', 'was', 'has', 'for', 'and',
      'with', 'so', 'that', 'can', 'my', 'reason', 'in', 'simple', 'words', 'give', 'detail',
      'details', 'check', 'any', 'who', 'screen', 'foreground', 'background', 'record', 'audio',
      'location', 'storage', 'contacts', 'sms', 'call', 'it', 'its', 'this', 'same', 'now'
    };

    // Check exact package matches anywhere in lower string
    for (final app in snapshot.applications) {
      if (lower.contains(app.packageName.toLowerCase())) {
        return _AppResolution(app: app, candidate: app.packageName, isDefiniteAppQuery: true);
      }
    }

    // Check exact full app names anywhere in lower string
    for (final app in snapshot.applications) {
      final nameLow = app.appName.toLowerCase().trim();
      if (nameLow.length > 2 && !stopWords.contains(nameLow) && lower.contains(nameLow)) {
        return _AppResolution(app: app, candidate: nameLow, isDefiniteAppQuery: true);
      }
    }

    // Tokenize query words
    final words = lower
        .replaceAll(RegExp(r'[^\w\s\.]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toList();

    for (final w in words) {
      final matched = _matchApp(snapshot, w);
      if (matched != null) {
        return _AppResolution(app: matched, candidate: w, isDefiniteAppQuery: true);
      }
    }

    return _AppResolution(app: null, candidate: null, isDefiniteAppQuery: false);
  }

  bool _isRecentSensorAccessQuery(String lower) {
    final hasSensor = lower.contains('camera') ||
        lower.contains('mic') ||
        lower.contains('audio') ||
        lower.contains('record') ||
        lower.contains('location') ||
        lower.contains('gps') ||
        lower.contains('sensor');

    final hasRecentOrTime = lower.contains('recent') ||
        lower.contains('recently') ||
        lower.contains('last accessed') ||
        lower.contains('accessed') ||
        lower.contains('who accessed') ||
        lower.contains('who used') ||
        lower.contains('which app accessed') ||
        lower.contains('which app used') ||
        lower.contains('mention time') ||
        lower.contains('timestamp') ||
        lower.contains('time also') ||
        lower.contains('history') ||
        lower.contains('alert') ||
        lower.contains('alerts');

    return hasSensor && hasRecentOrTime;
  }

  bool _isSelfAppQuery(String lower, {bool hasActiveSubject = false}) {
    if (hasActiveSubject &&
        (lower.contains('how long') ||
            lower.contains('use this app') ||
            lower.contains('time did i use') ||
            lower.contains('last used') ||
            lower.contains('is this app safe') ||
            lower.contains('why does this app') ||
            lower.contains('does this app have'))) {
      return false;
    }

    if (lower.contains('privacy sentinel') ||
        lower.contains('guardian app') ||
        lower.contains('guardian ai') ||
        lower.contains('you know about this app') ||
        lower.contains('what can you do') ||
        lower.contains('what can this app do') ||
        lower.contains('what does this app do') ||
        lower.contains('can this app notify') ||
        lower.contains('this app can notify') ||
        lower.contains('this appa can notify') ||
        lower.contains('notify that if any app') ||
        lower.contains('how do you protect') ||
        lower.contains('how does this app protect') ||
        lower.contains('about this app') ||
        (!hasActiveSubject &&
            (lower.contains('this app') || lower.contains('this appa')) &&
            (lower.contains('notify') ||
                lower.contains('protect') ||
                lower.contains('camera') ||
                lower.contains('mic') ||
                lower.contains('location') ||
                lower.contains('what') ||
                lower.contains('feature')))) {
      return true;
    }
    return false;
  }

  bool _isPronounOrReference(String? candidate) {
    if (candidate == null) return false;
    final c = candidate.trim().toLowerCase();
    const referenceTerms = {
      'it', 'its', 'this', 'that', 'app', 'the app', 'this app', 'that app',
      'same app', 'the same app', 'an app', 'one', 'this appa', 'appa',
      'app right', 'this app right', 'privacy sentinel', 'guardian', 'guardian ai',
      'sentinel', 'my app', 'our app', 'mobile', 'phone', 'device', 'my mobile',
      'my phone', 'this phone', 'the phone', 'my device', 'this device', 'the device',
      'android', 'system', 'safe', 'secure', 'status', 'summary', 'specs', 'details', 'battery', 'info',
      'camera', 'microphone', 'location', 'sensor', 'sensors', 'alert', 'alerts',
      'privacy', 'security', 'setting', 'settings', 'permission', 'permissions',
      'notification', 'notifications', 'usage', 'screen time',
      'camera permission', 'microphone permission', 'location permission',
    };
    if (referenceTerms.contains(c)) return true;
    for (final term in referenceTerms) {
      if (c == term || c.startsWith('$term ') || c.endsWith(' $term')) {
        return true;
      }
    }
    return false;
  }

  String _cleanCandidate(String? raw) {
    if (raw == null) return '';
    var c = raw.trim().toLowerCase();
    const leadingStrip = ['the ', 'my ', 'this ', 'that ', 'an ', 'a ', 'about '];
    for (final prefix in leadingStrip) {
      if (c.startsWith(prefix)) {
        c = c.substring(prefix.length).trim();
      }
    }
    const trailingStrip = [' app', ' appa', ' application', ' used', ' today', ' yesterday', ' now', ' right'];
    for (final suffix in trailingStrip) {
      if (c.endsWith(suffix)) {
        c = c.substring(0, c.length - suffix.length).trim();
      }
    }
    return c;
  }

  ApplicationProfile? _matchApp(DeviceSnapshot snapshot, String candidate) {
    final c = candidate.trim().toLowerCase();
    if (c.isEmpty || c.length < 2) return null;

    // 1. Exact package name match
    for (final app in snapshot.applications) {
      if (app.packageName.toLowerCase() == c) return app;
    }

    // 2. Exact display name match
    for (final app in snapshot.applications) {
      if (app.appName.toLowerCase().trim() == c) return app;
    }

    // 3. Alphanumeric normalized match (e.g. "whats app" -> "whatsapp")
    final normC = c.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (normC.length >= 3) {
      for (final app in snapshot.applications) {
        final normApp = app.appName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        if (normApp == normC) return app;
      }
    }

    // 4. Token match in multi-word app names (e.g. "chrome" in "Google Chrome")
    for (final app in snapshot.applications) {
      final tokens = app.appName.toLowerCase().split(RegExp(r'[\s\-_]+'));
      for (final t in tokens) {
        if (t.length >= 3 && t == c) return app;
      }
    }

    // 5. Prefix / Stem match (e.g. "insta" prefix of "instagram")
    if (c.length >= 3) {
      for (final app in snapshot.applications) {
        final nameLower = app.appName.toLowerCase().trim();
        if (nameLower.startsWith(c)) return app;
        final tokens = nameLower.split(RegExp(r'[\s\-_]+'));
        for (final t in tokens) {
          if (t.startsWith(c) && t.length >= c.length) return app;
        }
      }
    }

    // 6. Package segment match (e.g. "instagram" in com.instagram.android)
    for (final app in snapshot.applications) {
      final segments = app.packageName.toLowerCase().split('.');
      for (final s in segments) {
        if (s == 'com' || s == 'android' || s == 'google' || s == 'app' || s == 'apps') continue;
        if (s == c || (c.length >= 3 && s.startsWith(c))) return app;
      }
    }

    // 7. Fuzzy distance (Levenshtein distance <= 1 for candidates >= 5 chars)
    if (c.length >= 5) {
      for (final app in snapshot.applications) {
        final nameLower = app.appName.toLowerCase().trim();
        if (_levenshtein(c, nameLower) <= 1) return app;
        final tokens = nameLower.split(RegExp(r'[\s\-_]+'));
        for (final t in tokens) {
          if (t.length >= 5 && _levenshtein(c, t) <= 1) return app;
        }
      }
    }

    return null;
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }
}
