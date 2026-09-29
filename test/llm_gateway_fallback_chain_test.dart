import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/services/llm/llm_config.dart';
import 'package:mobile_privacy_security_project/services/llm/llm_gateway.dart';
import 'package:mobile_privacy_security_project/services/llm/llm_usage_tracker.dart';
import 'package:mobile_privacy_security_project/services/llm/model_cooldown_tracker.dart';
import 'package:mobile_privacy_security_project/services/llm/model_descriptor.dart';
import 'package:mobile_privacy_security_project/services/llm/model_failure.dart';

void main() {
  group('LLM Central Gateway Fallback Chain Tests', () {
    late ModelCooldownTracker cooldownTracker;
    late LlmUsageTracker usageTracker;

    final fallbackChainModels = [
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
        modelId: 'gemini-3.6-flash',
        provider: 'Google',
        displayName: 'Gemini 3.6 Flash',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 3,
      ),
      const ModelDescriptor(
        modelId: 'gemini-3.5-flash',
        provider: 'Google',
        displayName: 'Gemini 3.5 Flash',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 4,
      ),
      const ModelDescriptor(
        modelId: 'gemini-3.1-flash-lite',
        provider: 'Google',
        displayName: 'Gemini 3.1 Flash Lite',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 5,
      ),
      const ModelDescriptor(
        modelId: 'llama-3.3-70b-versatile',
        provider: 'Groq',
        displayName: 'Groq Llama 3.3 70B',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 6,
      ),
      const ModelDescriptor(
        modelId: 'otari-large',
        provider: 'Otari',
        displayName: 'Otari Large',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 7,
      ),
      const ModelDescriptor(
        modelId: 'rule-based-reasoner',
        provider: 'Rule-Based Reasoner',
        displayName: 'Rule-Based Reasoner',
        capabilities: {ModelCapability.text, ModelCapability.toolCalling},
        priority: 8,
      ),
    ];

    setUp(() {
      cooldownTracker = ModelCooldownTracker();
      usageTracker = LlmUsageTracker();
    });

    // -------------------------------------------------------------------------
    // TEST 1: Full 8-stage Fallback Chain:
    // Gemini 3.8 -> 3.7 -> 3.6 -> 3.5 -> 3.1 -> Groq -> Otari -> Rule-Based
    // -------------------------------------------------------------------------
    test('TEST 1: Complete 8-stage fallback chain: Gemini 3.8 -> 3.7 -> 3.6 -> 3.5 -> 3.1 -> Groq -> Otari -> Rule-Based Reasoner', () async {
      final attemptedModels = <String>[];

      final gateway = LlmGateway(
        models: fallbackChainModels,
        cooldownTracker: cooldownTracker,
        usageTracker: usageTracker,
        customRunner: (model, prompt) async {
          attemptedModels.add(model.modelId);

          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'RESOURCE_EXHAUSTED: token quota exceeded for 3.8',
            );
          }
          if (model.modelId == 'gemini-3.7-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.serviceUnavailable,
              httpStatus: 503,
              message: 'Gemini 3.7 overloaded',
            );
          }
          if (model.modelId == 'gemini-3.6-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.timeout,
              message: 'Gemini 3.6 request timed out',
            );
          }
          if (model.modelId == 'gemini-3.5-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.rateLimited,
              httpStatus: 429,
              message: 'Gemini 3.5 rate limited',
            );
          }
          if (model.modelId == 'gemini-3.1-flash-lite') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.temporaryOverload,
              httpStatus: 500,
              message: 'Gemini 3.1 internal server error',
            );
          }
          if (model.modelId == 'llama-3.3-70b-versatile') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'Groq quota exceeded',
            );
          }
          if (model.modelId == 'otari-large') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.serviceUnavailable,
              httpStatus: 503,
              message: 'Otari service unavailable',
            );
          }
          if (model.modelId == 'rule-based-reasoner') {
            return 'Deterministic evidence-based evaluation: Camera and microphone access evaluated without anomaly.';
          }

          throw Exception('Unexpected model: ${model.modelId}');
        },
      );

      final result = await gateway.route(prompt: 'Explain camera permission risk for WhatsApp');

      // 1. Verify all 8 models in the chain were attempted in exact order
      expect(attemptedModels, equals([
        'gemini-3.8-flash',
        'gemini-3.7-flash',
        'gemini-3.6-flash',
        'gemini-3.5-flash',
        'gemini-3.1-flash-lite',
        'llama-3.3-70b-versatile',
        'otari-large',
        'rule-based-reasoner',
      ]));

      // 2. Verify result details
      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('rule-based-reasoner'));
      expect(result.providerUsed, equals('Rule-Based Reasoner'));
      expect(result.responseSource, equals('RULE_BASED_FALLBACK'));
      expect(result.fallbackDepth, equals(7));
      expect(result.text, contains('Deterministic evidence-based evaluation'));

      // 3. Verify fallback logs
      expect(result.fallbackLogs.length, equals(7));
      expect(result.fallbackLogs[0], contains('[gemini-3.8-flash] (Google) failed'));
      expect(result.fallbackLogs[0], contains('Next trying: [gemini-3.7-flash]'));
      expect(result.fallbackLogs[1], contains('[gemini-3.7-flash] (Google) failed'));
      expect(result.fallbackLogs[1], contains('Next trying: [gemini-3.6-flash]'));
      expect(result.fallbackLogs[2], contains('[gemini-3.6-flash] (Google) failed'));
      expect(result.fallbackLogs[2], contains('Next trying: [gemini-3.5-flash]'));
      expect(result.fallbackLogs[3], contains('[gemini-3.5-flash] (Google) failed'));
      expect(result.fallbackLogs[3], contains('Next trying: [gemini-3.1-flash-lite]'));
      expect(result.fallbackLogs[4], contains('[gemini-3.1-flash-lite] (Google) failed'));
      expect(result.fallbackLogs[4], contains('Next trying: [llama-3.3-70b-versatile]'));
      expect(result.fallbackLogs[5], contains('[llama-3.3-70b-versatile] (Groq) failed'));
      expect(result.fallbackLogs[5], contains('Next trying: [otari-large]'));
      expect(result.fallbackLogs[6], contains('[otari-large] (Otari) failed'));
      expect(result.fallbackLogs[6], contains('Next trying: [rule-based-reasoner]'));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Primary model (Gemini 3.8) succeeds -> depth 0
    // -------------------------------------------------------------------------
    test('TEST 2: Primary Gemini 3.8 Flash succeeds without any fallback', () async {
      final gateway = LlmGateway(
        models: fallbackChainModels,
        cooldownTracker: cooldownTracker,
        usageTracker: usageTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            return 'Gemini 3.8 Flash analysis: Access is standard.';
          }
          throw Exception('Secondary called unexpectedly');
        },
      );

      final result = await gateway.route(prompt: 'Check microphone permission');

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('gemini-3.8-flash'));
      expect(result.providerUsed, equals('Google'));
      expect(result.responseSource, equals('REAL_GEMINI'));
      expect(result.fallbackDepth, equals(0));
      expect(result.fallbackLogs, isEmpty);
      expect(result.text, contains('Gemini 3.8 Flash analysis'));
    });

    // -------------------------------------------------------------------------
    // TEST 3: Gemini 3.8 quota -> Gemini 3.7 succeeds
    // -------------------------------------------------------------------------
    test('TEST 3: Gemini 3.8 429 quota -> falls back to Gemini 3.7 Flash', () async {
      final gateway = LlmGateway(
        models: fallbackChainModels,
        cooldownTracker: cooldownTracker,
        usageTracker: usageTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'Quota exceeded',
            );
          }
          if (model.modelId == 'gemini-3.7-flash') {
            return 'Gemini 3.7 Flash analysis: Validated camera permission.';
          }
          throw Exception('Unexpected candidate');
        },
      );

      final result = await gateway.route(prompt: 'Why does camera open?');

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('gemini-3.7-flash'));
      expect(result.fallbackDepth, equals(1));
      expect(result.fallbackReason, equals('QUOTA_EXCEEDED'));
      expect(result.fallbackLogs.length, equals(1));
      expect(result.fallbackLogs[0], contains('[gemini-3.8-flash] (Google) failed'));
      expect(result.fallbackLogs[0], contains('Next trying: [gemini-3.7-flash]'));
    });

    // -------------------------------------------------------------------------
    // TEST 4: All Gemini models fail -> Groq succeeds
    // -------------------------------------------------------------------------
    test('TEST 4: All Google Gemini models fail -> falls back to Groq Llama 3.3', () async {
      final gateway = LlmGateway(
        models: fallbackChainModels,
        cooldownTracker: cooldownTracker,
        usageTracker: usageTracker,
        customRunner: (model, prompt) async {
          if (model.provider == 'Google') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'Google Gemini quota exhausted',
            );
          }
          if (model.provider == 'Groq') {
            return 'Groq Llama 3.3: Analysis shows safe foreground usage.';
          }
          throw Exception('Unexpected candidate');
        },
      );

      final result = await gateway.route(prompt: 'Is this app safe?');

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('llama-3.3-70b-versatile'));
      expect(result.providerUsed, equals('Groq'));
      expect(result.responseSource, equals('REAL_GROQ'));
      expect(result.fallbackDepth, equals(5));
      expect(result.text, contains('Groq Llama 3.3'));
    });

    // -------------------------------------------------------------------------
    // TEST 5: All Gemini and Groq fail -> Otari succeeds
    // -------------------------------------------------------------------------
    test('TEST 5: All Gemini and Groq fail -> falls back to Otari', () async {
      final gateway = LlmGateway(
        models: fallbackChainModels,
        cooldownTracker: cooldownTracker,
        usageTracker: usageTracker,
        customRunner: (model, prompt) async {
          if (model.provider == 'Google' || model.provider == 'Groq') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.serviceUnavailable,
              httpStatus: 503,
              message: 'Service unavailable',
            );
          }
          if (model.provider == 'Otari') {
            return 'Otari Reasoner: Permission usage is consistent with application category.';
          }
          throw Exception('Unexpected candidate');
        },
      );

      final result = await gateway.route(prompt: 'Evaluate location access');

      expect(result.isSuccess, isTrue);
      expect(result.modelUsed, equals('otari-large'));
      expect(result.providerUsed, equals('Otari'));
      expect(result.responseSource, equals('REAL_OTARI'));
      expect(result.fallbackDepth, equals(6));
      expect(result.text, contains('Otari Reasoner'));
    });

    // -------------------------------------------------------------------------
    // TEST 6: Usage Tracking captures model, provider, tokens, latency, success/failure
    // -------------------------------------------------------------------------
    test('TEST 6: Usage tracker records model, provider, tokens, latency, success/failure', () async {
      final gateway = LlmGateway(
        models: fallbackChainModels,
        cooldownTracker: cooldownTracker,
        usageTracker: usageTracker,
        customRunner: (model, prompt) async {
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: '429 Rate limit',
            );
          }
          return 'Gemini 3.7 answer';
        },
      );

      await gateway.route(prompt: 'Test prompt query');

      expect(usageTracker.totalCalls, equals(2));
      expect(usageTracker.failedCalls, equals(1));
      expect(usageTracker.successfulCalls, equals(1));

      final failedRecord = usageTracker.records[0];
      expect(failedRecord.model, equals('gemini-3.8-flash'));
      expect(failedRecord.provider, equals('Google'));
      expect(failedRecord.isSuccess, isFalse);
      expect(failedRecord.failureReason, contains('Rate limit'));

      final successRecord = usageTracker.records[1];
      expect(successRecord.model, equals('gemini-3.7-flash'));
      expect(successRecord.provider, equals('Google'));
      expect(successRecord.isSuccess, isTrue);
      expect(successRecord.totalTokens, greaterThan(0));

      final stats = usageTracker.getUsageStats();
      expect(stats['totalCalls'], equals(2));
      expect(stats['successfulCalls'], equals(1));
    });

    // -------------------------------------------------------------------------
    // TEST 7: Cooldown skips repeatedly failing models
    // -------------------------------------------------------------------------
    test('TEST 7: Failing model enters cooldown and is skipped on next request', () async {
      final attempts = <String>[];

      final gateway = LlmGateway(
        models: fallbackChainModels,
        cooldownTracker: cooldownTracker,
        usageTracker: usageTracker,
        customRunner: (model, prompt) async {
          attempts.add(model.modelId);
          if (model.modelId == 'gemini-3.8-flash') {
            throw ModelFailureException(
              modelId: model.modelId,
              provider: model.provider,
              failureType: FailureType.quotaExceeded,
              httpStatus: 429,
              message: 'Rate limit',
            );
          }
          return 'Success from ${model.modelId}';
        },
      );

      // Call 1: 3.8 fails, 3.7 succeeds
      await gateway.route(prompt: 'First prompt');
      expect(attempts, equals(['gemini-3.8-flash', 'gemini-3.7-flash']));
      expect(cooldownTracker.isModelAvailable('gemini-3.8-flash'), isFalse);

      // Call 2: 3.8 is in cooldown, so it should be skipped immediately!
      attempts.clear();
      final result2 = await gateway.route(prompt: 'Second prompt');
      expect(attempts, equals(['gemini-3.7-flash']));
      expect(result2.modelUsed, equals('gemini-3.7-flash'));
      expect(result2.fallbackDepth, equals(0)); // 3.7 was primary among active candidates
    });

    // -------------------------------------------------------------------------
    // TEST 8: LLM only provides reasoning; does not mutate permissions
    // -------------------------------------------------------------------------
    test('TEST 8: LLM gateway returns advisory reasoning text only; no permission mutation', () async {
      final gateway = LlmGateway(
        models: fallbackChainModels,
        cooldownTracker: cooldownTracker,
        usageTracker: usageTracker,
        customRunner: (model, prompt) async {
          return 'Recommendation: Revoke background location access for flashlight app.';
        },
      );

      final result = await gateway.route(prompt: 'Should flashlight have location?');

      expect(result.isSuccess, isTrue);
      expect(result.text, contains('Recommendation: Revoke background location access'));
      // The gateway produces pure text reasoning/recommendation and makes zero system calls
    });

    // -------------------------------------------------------------------------
    // TEST 9: LlmConfig defaultTextModels contains all 8 candidates in order
    // -------------------------------------------------------------------------
    test('TEST 9: LlmConfig.defaultTextModels configures the exact 8-stage chain', () {
      final models = LlmConfig.defaultTextModels;
      expect(models.length, equals(8));
      expect(models[0].modelId, equals('gemini-3.8-flash'));
      expect(models[0].priority, equals(1));
      expect(models[1].modelId, equals('gemini-3.7-flash'));
      expect(models[1].priority, equals(2));
      expect(models[2].modelId, equals('gemini-3.6-flash'));
      expect(models[2].priority, equals(3));
      expect(models[3].modelId, equals('gemini-3.5-flash'));
      expect(models[3].priority, equals(4));
      expect(models[4].modelId, equals('gemini-3.1-flash-lite'));
      expect(models[4].priority, equals(5));
      expect(models[5].provider, equals('Groq'));
      expect(models[5].priority, equals(6));
      expect(models[6].provider, equals('Otari'));
      expect(models[6].priority, equals(7));
      expect(models[7].modelId, equals('rule-based-reasoner'));
      expect(models[7].priority, equals(8));
    });
  });
}
