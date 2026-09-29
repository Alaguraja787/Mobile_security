import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';
import 'package:mobile_privacy_security_project/services/llm/model_cooldown_tracker.dart';
import 'package:mobile_privacy_security_project/services/llm/model_descriptor.dart';
import 'package:mobile_privacy_security_project/services/llm/model_failure.dart';
import 'package:mobile_privacy_security_project/services/llm/model_router.dart';

void main() {
  group('ModelRouter & Automatic LLM Failover Tests', () {
    late ModelCooldownTracker cooldownTracker;

    final testCandidates = [
      const ModelDescriptor(
        modelId: 'gemini-3.8-flash',
        provider: 'Google',
        displayName: 'Gemini 3.8 Flash',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 1,
      ),
      const ModelDescriptor(
        modelId: 'gemini-3.7-flash',
        provider: 'Google',
        displayName: 'Gemini 3.7 Flash',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 2,
      ),
      const ModelDescriptor(
        modelId: 'gemini-3.1-flash-lite',
        provider: 'Google',
        displayName: 'Gemini 3.1 Flash Lite',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 3,
      ),
      const ModelDescriptor(
        modelId: 'claude-3-7-sonnet',
        provider: 'Anthropic',
        displayName: 'Claude 3.7 Sonnet',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 4,
      ),
      const ModelDescriptor(
        modelId: 'gemini-live-audio',
        provider: 'Google',
        displayName: 'Gemini Live Audio',
        capabilities: {ModelCapability.voice, ModelCapability.streaming, ModelCapability.toolCalling},
        priority: 5,
      ),
    ];

    setUp(() {
      cooldownTracker = ModelCooldownTracker();
    });

    // -------------------------------------------------------------------------
    // TEST 1: Primary model succeeds -> primary model returned
    // -------------------------------------------------------------------------
    test('TEST 1: Primary model succeeds -> primary model returned with depth 0', () async {
      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            return 'Gemini 3.8 Flash analysis: Access is standard.';
          }
          throw Exception('Secondary called unexpectedly');
        },
      );

      final result = await router.route(prompt: 'Why does app need camera?');

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('gemini-3.8-flash'));
      expect(result.providerUsed, equals('Google'));
      expect(result.responseSource, equals('REAL_GEMINI'));
      expect(result.fallbackDepth, equals(0));
      expect(result.fallbackReason, isNull);
      expect(result.text, contains('Gemini 3.8 Flash analysis'));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Primary returns 429 quota -> next compatible model attempted
    // -------------------------------------------------------------------------
    test('TEST 2: Primary returns 429 quota exceeded -> automatically fails over to next configured model', () async {
      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'RESOURCE_EXHAUSTED: rate limit exceeded',
            );
          }
          if (model.modelId == 'gemini-3.7-flash') {
            return 'Gemini 3.7 Flash analysis: Camera is for video recording.';
          }
          throw Exception('Unexpected candidate');
        },
      );

      final result = await router.route(prompt: 'Why does app need camera?');

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('gemini-3.7-flash'));
      expect(result.fallbackDepth, equals(1));
      expect(result.fallbackReason, equals('QUOTA_EXCEEDED'));
      expect(result.text, contains('Gemini 3.7 Flash analysis'));
    });

    // -------------------------------------------------------------------------
    // TEST 3: Primary returns temporary 503 -> next compatible model attempted
    // -------------------------------------------------------------------------
    test('TEST 3: Primary returns 503 capacity overload -> automatically fails over to next candidate', () async {
      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.serviceUnavailable,
              httpStatus: 503,
              message: 'Gemini service temporarily overloaded',
            );
          }
          if (model.modelId == 'gemini-3.7-flash') {
            return 'Gemini 3.7 Flash response after 503 failover.';
          }
          throw Exception('Unexpected candidate');
        },
      );

      final result = await router.route(prompt: 'Why does app need mic?');

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('gemini-3.7-flash'));
      expect(result.fallbackDepth, equals(1));
      expect(result.fallbackReason, equals('SERVICE_UNAVAILABLE'));
      expect(result.text, contains('Gemini 3.7 Flash response after 503 failover'));
    });

    // -------------------------------------------------------------------------
    // TEST 4: Primary authentication failure -> do NOT blindly rotate
    // -------------------------------------------------------------------------
    test('TEST 4: Authentication failure stops failover chain immediately and reports configuration error', () async {
      int attemptCount = 0;

      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          attemptCount++;
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.authFailure,
              httpStatus: 401,
              message: 'API key not valid. Please pass a valid API key.',
            );
          }
          return 'Should not be called!';
        },
      );

      final result = await router.route(prompt: 'Check permissions');

      expect(attemptCount, equals(1)); // Only attempted primary; did not rotate blindly
      expect(result.isSuccess, isFalse);
      expect(result.responseSource, equals('ERROR'));
      expect(result.fallbackReason, equals('AUTH_FAILURE'));
      expect(result.text.toLowerCase(), contains('authentication'));
    });

    // -------------------------------------------------------------------------
    // TEST 5: Primary and second model fail -> next compatible model attempted
    // -------------------------------------------------------------------------
    test('TEST 5: Primary and secondary fail -> third configured candidate succeeds with depth 2', () async {
      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'Quota exhausted',
            );
          }
          if (model.modelId == 'gemini-3.7-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.serviceUnavailable,
              httpStatus: 503,
              message: 'Capacity unavailable',
            );
          }
          if (model.modelId == 'gemini-3.1-flash-lite') {
            return 'Gemini 3.1 Flash Lite response: Validated.';
          }
          throw Exception('Unexpected candidate');
        },
      );

      final result = await router.route(prompt: 'Explain storage permission');

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('gemini-3.1-flash-lite'));
      expect(result.fallbackDepth, equals(2));
      expect(result.fallbackReason, equals('SERVICE_UNAVAILABLE'));
      expect(result.text, contains('Gemini 3.1 Flash Lite response'));
    });

    // -------------------------------------------------------------------------
    // TEST 6: All models fail -> honest AI unavailable result
    // -------------------------------------------------------------------------
    test('TEST 6: All models fail -> returns honest AI unavailable result without fake fallback text', () async {
      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          throw ModelFailureException(
            modelId: model.modelId,
            provider: model.provider,
            failureType: FailureType.serviceUnavailable,
            httpStatus: 503,
            message: 'All endpoints down',
          );
        },
      );

      final result = await router.route(prompt: 'Analyze risk');

      expect(result.isSuccess, isFalse);
      expect(result.responseSource, equals('AI_UNAVAILABLE'));
      expect(result.text, equals('AI is temporarily unavailable right now. Please try again shortly.'));
      expect(result.modelUsed, equals('None'));
    });

    // -------------------------------------------------------------------------
    // TEST 7: Final response identifies the MODEL ACTUALLY USED
    // -------------------------------------------------------------------------
    test('TEST 7: Never claims primary model when fallback model generated the answer', () async {
      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'Rate limit',
            );
          }
          if (model.modelId == 'gemini-3.7-flash') {
            return 'Answer from 3.7 Flash';
          }
          throw Exception('Unexpected');
        },
      );

      final service = GuardianService(provider: router);

      final duolingo = AppTelemetry(
        appName: 'Duolingo',
        packageName: 'com.duolingo',
        appCategory: 3, // EDUCATION
        grantedPermissions: ['android.permission.RECORD_AUDIO'],
      );
      service.updateTelemetryContext([duolingo]);

      final reply = await service.askGuardian('Why does Duolingo need microphone permission?');

      expect(reply.modelUsed, equals('gemini-3.7-flash'));
      expect(reply.modelUsed, isNot(equals('gemini-3.8-flash')));
      expect(reply.fallbackDepth, equals(1));
      expect(reply.fallbackReason, equals('QUOTA_EXCEEDED'));
      expect(reply.responseSource, equals('REAL_GEMINI'));
    });

    // -------------------------------------------------------------------------
    // TEST 8: Same Guardian evidence is preserved across fallback models
    // -------------------------------------------------------------------------
    test('TEST 8: Verified device evidence prompt is preserved identically across fallbacks', () async {
      final List<String> receivedPrompts = [];

      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          receivedPrompts.add(prompt);
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'Exhausted',
            );
          }
          return 'Analysis complete.';
        },
      );

      final service = GuardianService(provider: router);
      final soundCloud = AppTelemetry(
        appName: 'SoundCloud',
        packageName: 'com.soundcloud.android',
        appCategory: 1,
        grantedPermissions: ['android.permission.RECORD_AUDIO', 'android.permission.STORAGE'],
        usageTodayMs: 3600000,
      );
      service.updateTelemetryContext([soundCloud]);

      await service.askGuardian('Why does SoundCloud need storage?');

      // Second model received the exact same verified device prompt
      expect(receivedPrompts.length, equals(2));
      expect(receivedPrompts[0], contains('SoundCloud'));
      expect(receivedPrompts[0], contains('com.soundcloud.android'));
      expect(receivedPrompts[1], equals(receivedPrompts[0]));
    });

    // -------------------------------------------------------------------------
    // TEST 9: Unmentioned app (Not in original examples)
    // -------------------------------------------------------------------------
    test('TEST 9: Generic model routing functions identically for unmentioned app (Strava)', () async {
      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.temporaryOverload,
              httpStatus: 503,
              message: 'Capacity',
            );
          }
          return 'Strava uses location for GPS route tracking.';
        },
      );

      final service = GuardianService(provider: router);
      final strava = AppTelemetry(
        appName: 'Strava',
        packageName: 'com.strava',
        appCategory: 6, // MAPS / FITNESS
        grantedPermissions: ['android.permission.ACCESS_FINE_LOCATION'],
      );
      service.updateTelemetryContext([strava]);

      final reply = await service.askGuardian('Why does Strava need location?');

      expect(reply.targetApp, equals('Strava'));
      expect(reply.modelUsed, equals('gemini-3.7-flash'));
      expect(reply.fallbackDepth, equals(1));
      expect(reply.text, contains('GPS route tracking'));
    });

    // -------------------------------------------------------------------------
    // TEST 10: Capability filtering (Voice vs Text models)
    // -------------------------------------------------------------------------
    test('TEST 10: Voice requests filter out text-only models and only attempt voice-capable candidates', () async {
      final attemptedModels = <String>[];

      final router = ModelRouter(
        models: testCandidates,
        cooldownTracker: cooldownTracker,
        customRunner: (model, prompt) async {
          attemptedModels.add(model.modelId);
          return 'Live audio model active';
        },
      );

      // Route with voice + streaming + toolCalling capabilities required
      final result = await router.route(
        prompt: 'User spoken utterance',
        requiredCapabilities: {
          ModelCapability.voice,
          ModelCapability.streaming,
          ModelCapability.toolCalling,
        },
      );

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('gemini-live-audio'));
      // Text-only models (3.8-flash, 3.7-flash, 3.1-flash-lite, claude) must NOT have been attempted!
      expect(attemptedModels, equals(['gemini-live-audio']));
    });
  });
}
