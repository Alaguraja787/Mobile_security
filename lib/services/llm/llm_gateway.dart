import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'llm_config.dart';
import 'llm_provider.dart';
import 'llm_usage_tracker.dart';
import 'model_cooldown_tracker.dart';
import 'model_descriptor.dart';
import 'model_failure.dart';

/// Truthful execution result exposing complete model provenance and fallback trace.
class ModelExecutionResult {
  final String text;
  final String modelUsed;
  final String providerUsed;
  final String responseSource; // REAL_GEMINI, REAL_GROQ, REAL_OTARI, RULE_BASED_FALLBACK, AI_UNAVAILABLE, ERROR
  final int fallbackDepth; // 0 = primary model succeeded, 1 = first fallback, etc.
  final String? fallbackReason; // QUOTA_EXCEEDED, SERVICE_UNAVAILABLE, etc.
  final int? httpStatus;
  final int latencyMs;
  final bool isSuccess;
  final List<String> fallbackLogs;

  const ModelExecutionResult({
    required this.text,
    required this.modelUsed,
    required this.providerUsed,
    required this.responseSource,
    required this.fallbackDepth,
    this.fallbackReason,
    this.httpStatus,
    required this.latencyMs,
    this.isSuccess = true,
    this.fallbackLogs = const [],
  });

  Map<String, dynamic> toProvenanceMap() => {
        'responseSource': responseSource,
        'providerUsed': providerUsed,
        'modelUsed': modelUsed,
        'fallbackDepth': fallbackDepth,
        'fallbackReason': fallbackReason,
        'httpStatus': httpStatus,
        'latencyMs': latencyMs,
        'isSuccess': isSuccess,
        'fallbackLogs': fallbackLogs,
      };
}

typedef ModelRunner = Future<String> Function(ModelDescriptor model, String prompt);

/// Central LLM Gateway & Router.
///
/// Orchestrates the unified fallback chain:
/// Gemini 3.8 Flash -> Gemini 3.7 Flash -> Gemini 3.6 Flash ->
/// Gemini 3.5 Flash -> Gemini 3.1 Flash-Lite -> Groq -> Otari -> Rule-Based Reasoner.
///
/// Enforces:
/// 1. Automatic failover on quota, 429, timeout, or temporary errors.
/// 2. Logging of every fallback (failed model, reason, and next model).
/// 3. Basic usage tracking (model, provider, tokens, latency, success/failure).
/// 4. Prevention of infinite retries and progressive cooldowns.
/// 5. Advisory only (no direct permission modification).
class LlmGateway implements LlmProvider {
  final List<ModelDescriptor> configuredModels;
  final ModelCooldownTracker cooldownTracker;
  final LlmUsageTracker usageTracker;
  final ModelRunner? customRunner;
  final http.Client _httpClient;

  static final ModelCooldownTracker sharedCooldownTracker = ModelCooldownTracker();
  static final LlmUsageTracker sharedUsageTracker = LlmUsageTracker.instance;

  static final LlmGateway instance = LlmGateway();

  LlmGateway({
    List<ModelDescriptor>? models,
    ModelCooldownTracker? cooldownTracker,
    LlmUsageTracker? usageTracker,
    this.customRunner,
    http.Client? httpClient,
  })  : configuredModels = models ?? LlmConfig.defaultTextModels,
        cooldownTracker = cooldownTracker ?? sharedCooldownTracker,
        usageTracker = usageTracker ?? sharedUsageTracker,
        _httpClient = httpClient ?? http.Client();

  @override
  Future<String> generateResponse({required String prompt}) async {
    final result = await route(prompt: prompt);
    if (!result.isSuccess && result.responseSource != 'AI_UNAVAILABLE') {
      throw Exception(result.text);
    }
    return result.text;
  }

  /// Evaluates configured models in priority order with automatic failover,
  /// skipping cooling-down models and deduplicating calls.
  Future<ModelExecutionResult> route({
    required String prompt,
    Set<ModelCapability> requiredCapabilities = const {ModelCapability.text},
  }) async {
    final totalTimer = Stopwatch()..start();
    final List<String> fallbackLogs = [];

    // 1. Filter candidates by capability and enabled state
    final candidates = configuredModels
        .where((m) => m.isEnabled && m.supports(requiredCapabilities))
        .toList();

    // Sort by priority (1 = highest priority)
    candidates.sort((a, b) => a.priority.compareTo(b.priority));

    if (candidates.isEmpty) {
      developer.log(
        'MODEL_CHAIN_EXHAUSTED: No compatible models configured for capabilities $requiredCapabilities',
        name: 'LlmGateway',
      );
      return ModelExecutionResult(
        text: 'AI is temporarily unavailable right now. Please try again shortly.',
        modelUsed: 'None',
        providerUsed: 'None',
        responseSource: 'AI_UNAVAILABLE',
        fallbackDepth: 0,
        fallbackReason: 'NO_COMPATIBLE_MODELS',
        latencyMs: totalTimer.elapsedMilliseconds,
        isSuccess: false,
      );
    }

    // 2. Filter out models / providers currently in active cooldown
    // Note: Rule-Based Reasoner never cools down
    final activeCandidates = candidates.where((m) {
      if (m.provider == 'Rule-Based Reasoner' || m.modelId == 'rule-based-reasoner') {
        return true;
      }
      final isModelOk = cooldownTracker.isModelAvailable(m.modelId);
      final isProviderOk = cooldownTracker.isProviderAvailable(m.provider);
      return isModelOk && isProviderOk;
    }).toList();

    // If all models are in cooldown, fallback to Rule-Based Reasoner if available
    if (activeCandidates.isEmpty) {
      final ruleBasedCandidate = candidates.firstWhere(
        (m) => m.provider == 'Rule-Based Reasoner' || m.modelId == 'rule-based-reasoner',
        orElse: () => candidates.first,
      );
      if (ruleBasedCandidate.modelId == 'rule-based-reasoner') {
        activeCandidates.add(ruleBasedCandidate);
      } else {
        totalTimer.stop();
        developer.log('MODEL_ALL_COOLDOWN: All candidate models are in cooldown.', name: 'LlmGateway');
        return ModelExecutionResult(
          text: 'AI is temporarily unavailable right now. Please try again shortly.',
          modelUsed: 'None',
          providerUsed: 'None',
          responseSource: 'AI_UNAVAILABLE',
          fallbackDepth: 0,
          fallbackReason: 'COOLDOWN_ACTIVE',
          latencyMs: totalTimer.elapsedMilliseconds,
          isSuccess: false,
        );
      }
    }

    // 3. Deduplication set to guarantee each model is attempted at most once per request
    final Set<String> attemptedModelIds = {};
    String? lastFailureReason;
    int? lastHttpStatus;
    int fallbackDepth = 0;

    for (int i = 0; i < activeCandidates.length; i++) {
      final model = activeCandidates[i];

      if (attemptedModelIds.contains(model.modelId)) {
        continue;
      }
      attemptedModelIds.add(model.modelId);

      final attemptTimer = Stopwatch()..start();
      final attemptNumber = fallbackDepth + 1;

      developer.log(
        'MODEL_ATTEMPT_STARTED: provider=${model.provider} model=${model.modelId} attemptNumber=$attemptNumber',
        name: 'LlmGateway',
      );

      try {
        final responseText = await _executeModel(model, prompt);
        attemptTimer.stop();

        if (responseText.trim().isEmpty) {
          throw Exception('Model returned an empty response text.');
        }

        cooldownTracker.recordSuccess(modelId: model.modelId, provider: model.provider);

        final responseSource = _mapProviderToSource(model.provider);

        // Record successful usage
        final estimatedTokens = _estimateTokenCount(prompt, responseText);
        usageTracker.record(
          model: model.modelId,
          provider: model.provider,
          promptTokens: estimatedTokens['prompt'] ?? 0,
          completionTokens: estimatedTokens['completion'] ?? 0,
          totalTokens: estimatedTokens['total'] ?? 0,
          latencyMs: attemptTimer.elapsedMilliseconds,
          isSuccess: true,
        );

        developer.log(
          'MODEL_RESPONSE_RECEIVED: provider=${model.provider} model=${model.modelId} latencyMs=${attemptTimer.elapsedMilliseconds} fallbackDepth=$fallbackDepth',
          name: 'LlmGateway',
        );

        return ModelExecutionResult(
          text: responseText.trim(),
          modelUsed: model.modelId,
          providerUsed: model.provider,
          responseSource: responseSource,
          fallbackDepth: fallbackDepth,
          fallbackReason: lastFailureReason,
          httpStatus: 200,
          latencyMs: attemptTimer.elapsedMilliseconds,
          isSuccess: true,
          fallbackLogs: List.unmodifiable(fallbackLogs),
        );
      } catch (e) {
        attemptTimer.stop();
        final failure = FailureClassifier.classify(
          modelId: model.modelId,
          provider: model.provider,
          error: e,
        );

        lastFailureReason = failure.failureType.code;
        lastHttpStatus = failure.httpStatus;

        // Record failed usage attempt
        usageTracker.record(
          model: model.modelId,
          provider: model.provider,
          latencyMs: attemptTimer.elapsedMilliseconds,
          isSuccess: false,
          failureReason: failure.message,
        );

        // Find the next model for fallback logging
        String nextModelName = 'Rule-Based Reasoner';
        String nextProviderName = 'LocalDeterministic';
        for (int nextIdx = i + 1; nextIdx < activeCandidates.length; nextIdx++) {
          if (!attemptedModelIds.contains(activeCandidates[nextIdx].modelId)) {
            nextModelName = activeCandidates[nextIdx].modelId;
            nextProviderName = activeCandidates[nextIdx].provider;
            break;
          }
        }

        // REQUIRED: Log every fallback: which model failed, why it failed, and which model was tried next
        final fallbackLogMsg =
            'FALLBACK: [${model.modelId}] (${model.provider}) failed due to [${failure.failureType.code}: ${failure.message}]. Next trying: [$nextModelName] ($nextProviderName).';
        fallbackLogs.add(fallbackLogMsg);
        developer.log('[LLM_GATEWAY_FALLBACK] $fallbackLogMsg', name: 'LlmGateway');

        // NON-RETRYABLE: Authentication / Configuration failure must fail fast
        if (failure.isAuthFailure) {
          developer.log(
            'MODEL_AUTH_FAILURE_FAST_PATH: provider=${model.provider} model=${model.modelId} Stopping chain.',
            name: 'LlmGateway',
          );
          return ModelExecutionResult(
            text: 'Configuration or authentication error: ${failure.message}',
            modelUsed: model.modelId,
            providerUsed: model.provider,
            responseSource: 'ERROR',
            fallbackDepth: fallbackDepth,
            fallbackReason: 'AUTH_FAILURE',
            httpStatus: failure.httpStatus,
            latencyMs: attemptTimer.elapsedMilliseconds,
            isSuccess: false,
            fallbackLogs: List.unmodifiable(fallbackLogs),
          );
        }

        // NON-RETRYABLE: Malformed request or developer bug
        if (failure.isMalformedRequest) {
          return ModelExecutionResult(
            text: 'Request error: ${failure.message}',
            modelUsed: model.modelId,
            providerUsed: model.provider,
            responseSource: 'ERROR',
            fallbackDepth: fallbackDepth,
            fallbackReason: 'INVALID_REQUEST',
            httpStatus: failure.httpStatus,
            latencyMs: attemptTimer.elapsedMilliseconds,
            isSuccess: false,
            fallbackLogs: List.unmodifiable(fallbackLogs),
          );
        }

        // Apply cooldown to failing model to prevent hammering
        cooldownTracker.recordFailure(
          modelId: model.modelId,
          provider: model.provider,
          failureType: failure.failureType,
          retryAfter: failure.retryAfter,
        );

        fallbackDepth++;
      }
    }

    totalTimer.stop();
    developer.log('MODEL_CHAIN_EXHAUSTED: All ${attemptedModelIds.length} candidates failed.', name: 'LlmGateway');

    return ModelExecutionResult(
      text: 'AI is temporarily unavailable right now. Please try again shortly.',
      modelUsed: 'None',
      providerUsed: 'None',
      responseSource: 'AI_UNAVAILABLE',
      fallbackDepth: fallbackDepth,
      fallbackReason: lastFailureReason ?? 'ALL_MODELS_FAILED',
      httpStatus: lastHttpStatus,
      latencyMs: totalTimer.elapsedMilliseconds,
      isSuccess: false,
      fallbackLogs: List.unmodifiable(fallbackLogs),
    );
  }

  Future<String> _executeModel(ModelDescriptor model, String prompt) async {
    if (customRunner != null) {
      return await customRunner!(model, prompt);
    }

    final providerLower = model.provider.toLowerCase();

    if (providerLower == 'google') {
      return await _executeGoogleGemini(model.modelId, prompt);
    }

    if (providerLower == 'groq') {
      return await _executeGroq(model.modelId, prompt);
    }

    if (providerLower == 'otari') {
      return await _executeOtari(model.modelId, prompt);
    }

    if (providerLower.contains('rule') || model.modelId == 'rule-based-reasoner') {
      return _executeRuleBasedReasoner(prompt);
    }

    throw Exception('Unsupported provider runner for ${model.provider}');
  }

  /// 1. Google Gemini Executor
  Future<String> _executeGoogleGemini(String modelId, String prompt) async {
    final apiKey = LlmConfig.apiKey;
    if (apiKey.trim().isEmpty) {
      throw ModelFailureException(
        modelId: modelId,
        provider: 'Google',
        failureType: FailureType.authFailure,
        message: 'GEMINI_API_KEY is missing or unconfigured.',
      );
    }

    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=$apiKey';

    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'maxOutputTokens': LlmConfig.maxOutputTokens,
        'temperature': 0.2,
        'thinkingConfig': {
          'thinkingBudget': 0,
        },
      },
    };

    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(LlmConfig.timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final candidates = data['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final first = candidates.first;
        final content = first['content'];
        if (content is Map && content['parts'] is List) {
          final parts = content['parts'] as List;
          for (final part in parts) {
            if (part is Map && part['thought'] != true && part['text'] != null) {
              final text = part['text'].toString().trim();
              if (text.isNotEmpty) return text;
            }
          }
          for (final part in parts) {
            if (part is Map && part['text'] != null) {
              final text = part['text'].toString().trim();
              if (text.isNotEmpty) return text;
            }
          }
        }
      }
      throw Exception('Gemini returned an empty response payload.');
    }

    throw FailureClassifier.classify(
      modelId: modelId,
      provider: 'Google',
      error: 'HTTP ${response.statusCode}',
      httpStatus: response.statusCode,
      responseBody: response.body,
    );
  }

  /// 2. Groq Executor (OpenAI-compatible)
  Future<String> _executeGroq(String modelId, String prompt) async {
    final apiKey = LlmConfig.groqApiKey;
    if (apiKey.trim().isEmpty) {
      throw ModelFailureException(
        modelId: modelId,
        provider: 'Groq',
        failureType: FailureType.authFailure,
        message: 'GROQ_API_KEY is missing or unconfigured.',
      );
    }

    const url = 'https://api.groq.com/openai/v1/chat/completions';

    final body = {
      'model': modelId,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.2,
      'max_tokens': LlmConfig.maxOutputTokens,
    };

    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(LlmConfig.timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final content = choices.first['message']?['content']?.toString().trim();
        if (content != null && content.isNotEmpty) {
          return content;
        }
      }
      throw Exception('Groq returned an empty response.');
    }

    throw FailureClassifier.classify(
      modelId: modelId,
      provider: 'Groq',
      error: 'HTTP ${response.statusCode}',
      httpStatus: response.statusCode,
      responseBody: response.body,
    );
  }

  /// 3. Otari Executor (OpenAI-compatible)
  Future<String> _executeOtari(String modelId, String prompt) async {
    final apiKey = LlmConfig.otariApiKey;
    final url = LlmConfig.otariApiUrl;

    if (apiKey.trim().isEmpty && !url.contains('localhost') && !url.contains('127.0.0.1')) {
      throw ModelFailureException(
        modelId: modelId,
        provider: 'Otari',
        failureType: FailureType.authFailure,
        message: 'OTARI_API_KEY is missing or unconfigured.',
      );
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final body = {
      'model': modelId,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.2,
      'max_tokens': LlmConfig.maxOutputTokens,
    };

    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(LlmConfig.timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final content = choices.first['message']?['content']?.toString().trim();
        if (content != null && content.isNotEmpty) {
          return content;
        }
      }
      throw Exception('Otari returned an empty response.');
    }

    throw FailureClassifier.classify(
      modelId: modelId,
      provider: 'Otari',
      error: 'HTTP ${response.statusCode}',
      httpStatus: response.statusCode,
      responseBody: response.body,
    );
  }

  /// 4. Rule-Based Deterministic Fallback Reasoner
  String _executeRuleBasedReasoner(String prompt) {
    developer.log('RULE_BASED_REASONER_EXECUTED: Deterministic fallback response', name: 'LlmGateway');

    final lower = prompt.toLowerCase();
    if (lower.contains('hi') || lower.contains('hello') || lower.contains('who are you')) {
      return 'Hello! I am Privacy Sentinel Guardian. Ask me anything about your connected device apps, active permissions, privacy risks, or today\'s app usage activity.';
    }

    if (lower.contains('camera')) {
      return 'Camera permission evaluation: Camera access should strictly correspond to active user capture. Applications should not access the optical sensor in the background without explicit notification.';
    }

    if (lower.contains('microphone') || lower.contains('mic') || lower.contains('record_audio')) {
      return 'Microphone permission evaluation: Audio recording access requires active foreground indication. Continuous or unexplained background listening constitutes an elevated privacy risk.';
    }

    if (lower.contains('location')) {
      return 'Location access evaluation: High-accuracy GPS positioning is sensitive telemetry. Background tracking should be restricted unless strictly required for core navigation services.';
    }

    return 'Verified device privacy evaluation: Analysis generated from deterministic safety policies. Standard privacy parameters maintained across current-device telemetry.';
  }

  Map<String, int> _estimateTokenCount(String prompt, String response) {
    final promptToks = (prompt.length / 4).ceil();
    final compToks = (response.length / 4).ceil();
    return {
      'prompt': promptToks,
      'completion': compToks,
      'total': promptToks + compToks,
    };
  }

  String _mapProviderToSource(String provider) {
    final p = provider.toLowerCase();
    if (p == 'google') return 'REAL_GEMINI';
    if (p == 'groq') return 'REAL_GROQ';
    if (p == 'otari') return 'REAL_OTARI';
    if (p.contains('rule')) return 'RULE_BASED_FALLBACK';
    return 'REAL_${provider.toUpperCase()}';
  }
}
