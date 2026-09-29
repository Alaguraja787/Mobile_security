import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';
import 'package:mobile_privacy_security_project/services/llm/llm_provider.dart';

class _MockLlmProvider implements LlmProvider {
  @override
  Future<String> generateResponse({required String prompt}) async {
    return 'LLM reasoning over verified evidence:\n$prompt';
  }
}

void main() {
  group('Guardian Generic Conversation Continuity Tests', () {
    late GuardianService service;

    final yt = AppTelemetry(
      appName: 'YouTube',
      packageName: 'com.google.android.youtube',
      appCategory: 2, // VIDEO
      grantedPermissions: ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO'],
      usageTodayMs: 5040000, // 1h 24m
      lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch - 15 * 60 * 1000,
      usageDataState: 'AVAILABLE',
      usageAvailability: 'VALID',
    );

    final spotify = AppTelemetry(
      appName: 'Spotify',
      packageName: 'com.spotify.music',
      appCategory: 1, // AUDIO
      grantedPermissions: ['android.permission.ACCESS_FINE_LOCATION', 'android.permission.RECORD_AUDIO'],
      usageTodayMs: 3600000, // 1h
      lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch - 5 * 60 * 1000,
      usageDataState: 'AVAILABLE',
      usageAvailability: 'VALID',
    );

    final telegram = AppTelemetry(
      appName: 'Telegram',
      packageName: 'org.telegram.messenger',
      appCategory: 4, // SOCIAL / CHAT
      grantedPermissions: ['android.permission.CAMERA', 'android.permission.READ_CONTACTS'],
      usageTodayMs: 1800000, // 30m
      usageDataState: 'AVAILABLE',
      usageAvailability: 'VALID',
    );

    final signal = AppTelemetry(
      appName: 'Signal',
      packageName: 'org.thoughtcrime.securesms',
      appCategory: 4, // CHAT
      grantedPermissions: ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO'],
      usageTodayMs: 900000, // 15m
      usageDataState: 'AVAILABLE',
      usageAvailability: 'VALID',
    );

    final slack = AppTelemetry(
      appName: 'Slack',
      packageName: 'com.Slack',
      appCategory: 5, // PRODUCTIVITY
      grantedPermissions: ['android.permission.RECORD_AUDIO', 'android.permission.READ_EXTERNAL_STORAGE'],
      usageTodayMs: 2700000, // 45m
      lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch - 60 * 60 * 1000,
      usageDataState: 'AVAILABLE',
      usageAvailability: 'VALID',
    );

    setUp(() {
      service = GuardianService(provider: _MockLlmProvider());
      service.updateTelemetryContext([yt, spotify, telegram, signal, slack]);
    });

    // -------------------------------------------------------------------------
    // A. Original Example App (YouTube) Multi-turn
    // -------------------------------------------------------------------------
    test('A. Original named app (YouTube) retains context across continuation and usage inquiry', () async {
      // Turn 1: Explicit question about YouTube camera
      final r1 = await service.askGuardian('Why does YouTube need camera permission?');
      expect(r1.targetApp, equals('YouTube'));
      expect(r1.targetPermission, equals('CAMERA'));
      expect(r1.intent, equals('appExplanation'));

      // Turn 2: Follow-up continuation ("Why?") without naming app or permission
      final r2 = await service.askGuardian('Why?');
      expect(r2.targetApp, equals('YouTube'));
      expect(r2.targetPermission, equals('CAMERA'));
      expect(r2.intent, equals('followUpExplanation'));

      // Turn 3: Pronoun usage inquiry ("How long did I use it today?")
      final r3 = await service.askGuardian('How long did I use it today?');
      expect(r3.targetApp, equals('YouTube'));
      expect(r3.intent, equals('appUsageQuery'));
      expect(r3.decision?.summary, contains('YouTube'));
    });

    // -------------------------------------------------------------------------
    // B & C. Completely Different Installed App (Spotify) + Different Permission (LOCATION)
    // -------------------------------------------------------------------------
    test('B & C. Unmentioned app (Spotify) with different permission (LOCATION) resolves generically', () async {
      // Turn 1: Query about Spotify location permission
      final r1 = await service.askGuardian('Why does Spotify need location permission?');
      expect(r1.targetApp, equals('Spotify'));
      expect(r1.targetPermission, equals('LOCATION'));

      // Turn 2: Omitted subject and permission continuation ("Is it using it now?")
      final r2 = await service.askGuardian('Is it using it now?');
      expect(r2.targetApp, equals('Spotify'));
      expect(r2.targetPermission, equals('LOCATION'));
      expect(r2.intent, equals('followUpExplanation'));

      // Turn 3: Pronoun last used inquiry ("When was it last used?")
      final r3 = await service.askGuardian('When was it last used?');
      expect(r3.targetApp, equals('Spotify'));
      expect(r3.intent, equals('appLastUsedQuery'));
    });

    // -------------------------------------------------------------------------
    // D. Multi-Turn Conversation (4 turns on Slack)
    // -------------------------------------------------------------------------
    test('D. Multi-turn conversation retains active entity through varied question types', () async {
      // Turn 1: General about app
      final r1 = await service.askGuardian('Tell me about Slack');
      expect(r1.targetApp, equals('Slack'));

      // Turn 2: Permission inquiry on active entity
      final r2 = await service.askGuardian('Does it have microphone permission?');
      expect(r2.targetApp, equals('Slack'));
      expect(r2.targetPermission, equals('RECORD_AUDIO'));

      // Turn 3: Follow-up question
      final r3 = await service.askGuardian('Why does it need that?');
      expect(r3.targetApp, equals('Slack'));
      expect(r3.targetPermission, equals('RECORD_AUDIO'));
      expect(r3.intent, equals('followUpExplanation'));

      // Turn 4: Usage question using pronoun
      final r4 = await service.askGuardian('How much time did I spend on it today?');
      expect(r4.targetApp, equals('Slack'));
      expect(r4.intent, equals('appUsageQuery'));
    });

    // -------------------------------------------------------------------------
    // E. Topic Change & Current Query Priority
    // -------------------------------------------------------------------------
    test('E. Explicit query entity overrides previous context immediately, and global queries reset specific focus', () async {
      // Turn 1: Discuss Telegram
      final r1 = await service.askGuardian('Why does Telegram need contacts permission?');
      expect(r1.targetApp, equals('Telegram'));
      expect(r1.targetPermission, equals('CONTACTS'));

      // Turn 2: Explicitly switch to Signal -> MUST override Telegram immediately
      final r2 = await service.askGuardian('Why does Signal need camera permission?');
      expect(r2.targetApp, equals('Signal'));
      expect(r2.targetPermission, equals('CAMERA'));
      expect(service.conversationContext.activeAppName, equals('Signal'));

      // Turn 3: Global All-App Query -> Must evaluate across all apps, not just Signal
      final r3 = await service.askGuardian('Which apps have camera permission?');
      expect(r3.intent, equals('listAppsByPermission'));
      expect(r3.targetPermission, equals('CAMERA'));
      // In a global query, matchingApps contains all camera apps (YouTube, Telegram, Signal)
      expect(r3.decision?.summary.toLowerCase(), isNot(equals('signal')));
      expect(service.conversationContext.activeAppName, isNull);
    });

    // -------------------------------------------------------------------------
    // F. Generic Pronoun and Deictic Reference Variations
    // -------------------------------------------------------------------------
    test('F. Varied reference expressions resolve to active entity without hardcoded phrases', () async {
      await service.askGuardian('Why does YouTube need camera permission?');

      final phrases = [
        'How long was it used today?',
        'Can you explain why that app needs it?',
        'What does that mean?',
        'Is the app safe?',
        'How long did I use this app?',
      ];

      for (final phrase in phrases) {
        // Reset to YouTube context for each phrase test
        service.conversationContext.updateActiveSubject(
          appName: 'YouTube',
          packageName: 'com.google.android.youtube',
          permission: 'CAMERA',
        );

        final reply = await service.askGuardian(phrase);
        expect(reply.targetApp, equals('YouTube'), reason: 'Failed resolving for phrase: "$phrase"');
        expect(reply.intent, isNot(equals('appNotFound')), reason: 'Must not trigger appNotFound for: "$phrase"');
      }
    });

    // -------------------------------------------------------------------------
    // G. Voice and Text Parity
    // -------------------------------------------------------------------------
    test('G. Text inquiry followed by spoken voice inquiry share identical conversation context', () async {
      // User types question in text chat
      final chatReply = await service.askGuardian('Why does Telegram need camera permission?');
      expect(chatReply.targetApp, equals('Telegram'));

      // Next, user speaks a voice continuation through the same GuardianService
      const voiceTranscript = 'Why?';
      final voiceReply = await service.askGuardian(voiceTranscript);

      expect(voiceReply.targetApp, equals('Telegram'));
      expect(voiceReply.targetPermission, equals('CAMERA'));
      expect(voiceReply.intent, equals('followUpExplanation'));
    });

    // -------------------------------------------------------------------------
    // H. Verified DeviceSnapshot as Truth (Never Hallucinate Stale State)
    // -------------------------------------------------------------------------
    test('H. Answers use fresh DeviceSnapshot facts rather than stale conversational memory', () async {
      // Initial state: Spotify has 1h (3600000 ms) usage
      final r1 = await service.askGuardian('How long did I use Spotify today?');
      expect(r1.decision?.summary, contains('1h'));

      // Telemetry update occurs: Spotify usage increases to 3h (10800000 ms)
      final updatedSpotify = AppTelemetry(
        appName: 'Spotify',
        packageName: 'com.spotify.music',
        appCategory: 1,
        grantedPermissions: ['android.permission.ACCESS_FINE_LOCATION', 'android.permission.RECORD_AUDIO'],
        usageTodayMs: 10800000, // 3h
        usageDataState: 'AVAILABLE',
        usageAvailability: 'VALID',
      );
      service.updateTelemetryContext([updatedSpotify]);

      // Turn 2: Follow-up question using pronoun
      final r2 = await service.askGuardian('How much time did I use it today?');
      expect(r2.targetApp, equals('Spotify'));
      // Verified facts must reflect the updated 3h, NOT the old 1h
      expect(r2.decision?.summary, contains('3h'));
    });
  });
}
