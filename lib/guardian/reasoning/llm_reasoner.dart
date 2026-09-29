import 'dart:developer' as developer;
import '../../services/llm/llm_config.dart';
import '../../services/llm/llm_gateway.dart';
import '../../services/llm/llm_provider.dart';
import '../evidence/evidence_interpreter.dart';
import '../models/evidence.dart';
import '../models/guardian_input.dart';
import 'guardian_reasoner.dart';
import 'rule_based_reasoner.dart';

/// Evidence-First LLM Reasoner for Privacy Sentinel AI Guardian.
///
/// Routes verified current-device telemetry through central LlmGateway with automatic failover,
/// preserving truth provenance and graceful deterministic fallback.
class LLMReasoner implements GuardianReasoner {
  final LlmProvider provider;
  final GuardianReasoner fallbackReasoner;
  final Future<String?> Function(String prompt)? legacyLlmClient;

  LlmStatus lastStatus = LlmStatus.unavailable;

  LLMReasoner({
    LlmProvider? provider,
    GuardianReasoner? fallback,
    this.legacyLlmClient,
  })  : provider = provider ?? LlmGateway.instance,
        fallbackReasoner = fallback ?? RuleBasedReasoner();

  @override
  Future<ReasoningOutput> reason({
    required GuardianInput input,
    required InterpretationResult interpretation,
    required List<Inference> contextInferences,
  }) async {
    final intent = input.historyContext?['intent']?.toString();

    // 1. App Not Found is verified and resolved deterministically
    if (intent == 'appNotFound') {
      const notFoundMsg = "I can't find that app among the applications currently reported by this device.";
      return ReasoningOutput(
        reasoningSummary: 'Verified deterministic check: queried application not discovered in current device snapshot.',
        userFacingExplanation: notFoundMsg,
        inferences: const [],
        responseSource: 'LOCAL_DETERMINISTIC',
      );
    }

    // 2. If legacy client is explicitly set and provider wasn't passed, use legacy client
    if (legacyLlmClient != null) {
      try {
        final prompt = _buildStructuredPrompt(input, interpretation, contextInferences);
        developer.log('LLM_REQUEST_STARTED: legacy client', name: 'LLMReasoner');
        final response = await legacyLlmClient!(prompt);
        if (response != null && response.trim().isNotEmpty) {
          lastStatus = LlmStatus.active;
          developer.log('LLM_RESPONSE_RECEIVED: legacy client', name: 'LLMReasoner');
          return ReasoningOutput(
            reasoningSummary: 'LLM Reasoning Over Structured Evidence (Legacy Client):\n$response',
            userFacingExplanation: response.trim(),
            inferences: contextInferences,
            responseSource: 'REAL_GEMINI',
            providerUsed: 'Google',
            modelUsed: LlmConfig.model,
          );
        }
      } catch (e) {
        developer.log('LLM_REQUEST_FAILED: $e', name: 'LLMReasoner');
        developer.log('RULE_BASED_FALLBACK: reason=$e', name: 'LLMReasoner');
      }
    }

    // 3. Delegate to central LlmGateway with Automatic Failover
    if (provider is LlmGateway) {
      final prompt = _buildStructuredPrompt(input, interpretation, contextInferences);
      developer.log('LLM_ROUTER_REQUEST_STARTED: prompt_length=${prompt.length}', name: 'LLMReasoner');

      final ModelExecutionResult result = await (provider as LlmGateway).route(prompt: prompt);

      if (result.isSuccess) {
        lastStatus = LlmStatus.active;
        return ReasoningOutput(
          reasoningSummary: '${result.providerUsed} (${result.modelUsed}) Reasoning:\n${result.text}',
          userFacingExplanation: result.text,
          inferences: contextInferences,
          responseSource: result.responseSource,
          providerUsed: result.providerUsed,
          modelUsed: result.modelUsed,
          fallbackDepth: result.fallbackDepth,
          fallbackReason: result.fallbackReason,
          httpStatus: result.httpStatus,
          latencyMs: result.latencyMs,
        );
      }

      final isChatQuery = input.historyContext?['query'] != null;

      // Telemetry risk evaluations (non-chat) fall back to deterministic RuleBasedReasoner
      if (!isChatQuery && input.targetApp != null) {
        lastStatus = LlmStatus.fallback;
        developer.log('RULE_BASED_FALLBACK: reason=${result.fallbackReason ?? "AI_UNAVAILABLE"}', name: 'LLMReasoner');
        final fallbackOutput = await fallbackReasoner.reason(
          input: input,
          interpretation: interpretation,
          contextInferences: contextInferences,
        );
        return ReasoningOutput(
          reasoningSummary: '${fallbackOutput.reasoningSummary}\n[AI Model Unavailable: ${result.fallbackReason ?? "EXHAUSTED"}]',
          userFacingExplanation: fallbackOutput.userFacingExplanation,
          inferences: fallbackOutput.inferences,
          responseSource: 'RULE_BASED_FALLBACK',
          fallbackCause: result.fallbackReason ?? 'AI_UNAVAILABLE',
          providerUsed: result.providerUsed,
          modelUsed: result.modelUsed,
          fallbackDepth: result.fallbackDepth,
          fallbackReason: result.fallbackReason,
          httpStatus: result.httpStatus,
          latencyMs: result.latencyMs,
        );
      }

      // Conversational greetings (e.g. "hi", "hello") fall back to deterministic introduction
      if (intent == 'conversational') {
        const greeting = 'Hello! I am Privacy Sentinel Guardian. Ask me anything about your connected device apps, active permissions, privacy risks, or today\'s app usage activity.';
        return ReasoningOutput(
          reasoningSummary: 'Deterministic response for conversational greeting (AI offline: ${result.fallbackReason}).',
          userFacingExplanation: greeting,
          inferences: const [],
          responseSource: 'LOCAL_DETERMINISTIC',
          fallbackCause: result.fallbackReason ?? 'AI_UNAVAILABLE',
          providerUsed: result.providerUsed,
          modelUsed: result.modelUsed,
          fallbackDepth: result.fallbackDepth,
          fallbackReason: result.fallbackReason,
          httpStatus: result.httpStatus,
          latencyMs: result.latencyMs,
        );
      }

      // Non-retryable auth/config failure: report error immediately without fake fallback
      if (result.fallbackReason == 'AUTH_FAILURE') {
        lastStatus = LlmStatus.unavailable;
        return ReasoningOutput(
          reasoningSummary: 'Authentication/Configuration failure: ${result.text}',
          userFacingExplanation: result.text,
          inferences: const [],
          responseSource: 'ERROR',
          fallbackCause: 'AUTH_FAILURE',
          providerUsed: result.providerUsed,
          modelUsed: result.modelUsed,
          fallbackDepth: result.fallbackDepth,
          fallbackReason: result.fallbackReason,
          httpStatus: result.httpStatus,
          latencyMs: result.latencyMs,
        );
      }

      // All models failed: return honest AI unavailable state (NEVER pretend it was REAL_GEMINI)
      lastStatus = LlmStatus.unavailable;
      return ReasoningOutput(
        reasoningSummary: 'Model fallback chain exhausted. AI is temporarily unavailable.',
        userFacingExplanation: result.text,
        inferences: const [],
        responseSource: result.responseSource, // 'AI_UNAVAILABLE'
        fallbackCause: result.fallbackReason ?? 'ALL_MODELS_FAILED',
        providerUsed: result.providerUsed,
        modelUsed: result.modelUsed,
        fallbackDepth: result.fallbackDepth,
        fallbackReason: result.fallbackReason,
        httpStatus: result.httpStatus,
        latencyMs: result.latencyMs,
      );
    }

    // 4. Standalone LlmProvider (e.g. FakeLlmProvider for isolated tests)
    if (!LlmConfig.hasApiKey) {
      lastStatus = LlmStatus.fallback;
      developer.log('RULE_BASED_FALLBACK: reason=GEMINI_API_KEY missing', name: 'LLMReasoner');
      final fallbackOutput = await fallbackReasoner.reason(
        input: input,
        interpretation: interpretation,
        contextInferences: contextInferences,
      );
      return ReasoningOutput(
        reasoningSummary: '${fallbackOutput.reasoningSummary}\n[LLM Status: Fallback (GEMINI_API_KEY missing)]',
        userFacingExplanation: fallbackOutput.userFacingExplanation,
        inferences: fallbackOutput.inferences,
        responseSource: 'RULE_BASED_FALLBACK',
        fallbackCause: 'GEMINI_API_KEY missing',
      );
    }

    try {
      final prompt = _buildStructuredPrompt(input, interpretation, contextInferences);
      developer.log(
        'LLM_REQUEST_STARTED: model=${LlmConfig.model} prompt_length=${prompt.length}',
        name: 'LLMReasoner',
      );

      final sw = Stopwatch()..start();
      final String responseText = await provider.generateResponse(prompt: prompt);
      sw.stop();

      if (responseText.trim().isEmpty) {
        throw Exception('Model returned an empty response text.');
      }

      lastStatus = LlmStatus.active;
      developer.log(
        'LLM_RESPONSE_RECEIVED: model=${LlmConfig.model} response_length=${responseText.length} status=200',
        name: 'LLMReasoner',
      );

      return ReasoningOutput(
        reasoningSummary: 'Gemini LLM (${LlmConfig.model}) Reasoning:\n$responseText',
        userFacingExplanation: responseText.trim(),
        inferences: contextInferences,
        responseSource: 'REAL_GEMINI',
        providerUsed: 'Google',
        modelUsed: LlmConfig.model,
        fallbackDepth: 0,
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      lastStatus = LlmStatus.fallback;
      developer.log('LLM_REQUEST_FAILED: $e', name: 'LLMReasoner');
      developer.log('RULE_BASED_FALLBACK: reason=$e', name: 'LLMReasoner');

      if (intent == 'conversational') {
        const greeting = 'Hello! I am Privacy Sentinel Guardian. Ask me anything about your connected device apps, active permissions, privacy risks, or today\'s app usage activity.';
        return ReasoningOutput(
          reasoningSummary: 'Fallback greeting response (Gemini API offline: $e)',
          userFacingExplanation: greeting,
          inferences: const [],
          responseSource: 'RULE_BASED_FALLBACK',
          fallbackCause: e.toString(),
        );
      }

      final fallbackOutput = await fallbackReasoner.reason(
        input: input,
        interpretation: interpretation,
        contextInferences: contextInferences,
      );

      return ReasoningOutput(
        reasoningSummary: '${fallbackOutput.reasoningSummary}\n[Gemini Fallback Note: $e]',
        userFacingExplanation: fallbackOutput.userFacingExplanation,
        inferences: fallbackOutput.inferences,
        responseSource: 'RULE_BASED_FALLBACK',
        fallbackCause: e.toString(),
      );
    }
  }

  /// Builds a concise, evidence-driven prompt strictly containing telemetry facts and human-language instructions.
  String _buildStructuredPrompt(
    GuardianInput input,
    InterpretationResult interpretation,
    List<Inference> inferences,
  ) {
    final appName = input.targetApp?.appName.isNotEmpty == true
        ? input.targetApp!.appName
        : (input.targetApp?.packageName ?? '');

    final userQuery = input.historyContext?['query']?.toString() ??
        (appName.isNotEmpty
            ? 'Explain privacy risk and permissions for $appName.'
            : 'Explain privacy risk and permissions for this application.');
    final inventoryEvidence = input.historyContext?['inventoryEvidence']?.toString();
    final recentUserMsg = input.historyContext?['recentUserMessage']?.toString();
    final recentAssistantResp = input.historyContext?['recentAssistantResponse']?.toString();

    final buffer = StringBuffer();
    buffer.writeln('SYSTEM ROLE:');
    buffer.writeln('You are Privacy Sentinel Guardian, an intelligent, helpful Android privacy assistant.');
    buffer.writeln('Explain Android privacy information clearly, accurately, and in simple language that any person can easily understand.');
    buffer.writeln();

    if (recentUserMsg != null && recentUserMsg.isNotEmpty && recentAssistantResp != null && recentAssistantResp.isNotEmpty) {
      buffer.writeln('RECENT CONVERSATION CONTEXT:');
      buffer.writeln('User: "$recentUserMsg"');
      buffer.writeln('Guardian: "$recentAssistantResp"');
      buffer.writeln();
    }

    if (input.targetApp != null) {
      final app = input.targetApp!;
      buffer.writeln('TARGET APP TELEMETRY:');
      buffer.writeln('App Name: ${app.appName.isNotEmpty ? app.appName : app.packageName}');
      buffer.writeln('Package: ${app.packageName}');
      buffer.writeln('Category: ${app.category.name}');
      if (app.permissions.isNotEmpty) {
        buffer.writeln('Granted Permissions: ${app.permissions.join(", ")}');
      }
      if (app.hasOverlayOp) {
        buffer.writeln('Special Access: Display over other apps enabled');
      }
      final upload = app.uploadBytes;
      if (upload != null && upload > 0) {
        buffer.writeln('Observed Upload Traffic: ${(upload / (1024 * 1024)).toStringAsFixed(1)} MB');
      }
      buffer.writeln();
    }

    if (inventoryEvidence != null && inventoryEvidence.trim().isNotEmpty) {
      buffer.writeln('VERIFIED CURRENT DEVICE EVIDENCE:');
      buffer.writeln(inventoryEvidence.trim());
      buffer.writeln();
    }

    buffer.writeln('USER QUESTION:');
    buffer.writeln('"$userQuery"');
    buffer.writeln();

    final bool isVoice = input.historyContext?['isVoice'] == true;

    buffer.writeln('RESPONSE CONTRACT & CONCISE GUIDELINES:');
    if (isVoice) {
      buffer.writeln('VOICE ASSISTANT MODE (ChatGPT-like Speech):');
      buffer.writeln('- This response will be read aloud immediately via text-to-speech.');
      buffer.writeln('- Keep your reply strictly to 1 or 2 short conversational sentences (maximum 30 words).');
      buffer.writeln('- Do NOT use bullet points, asterisks, bolding, markdown symbols, or headers.');
      buffer.writeln('- Speak with a warm, natural, friendly conversational tone.');
      buffer.writeln();
    }
    buffer.writeln('1. LENGTH: Keep normal responses concise: 1 to 3 short sentences. Maximum 4 short sentences. Never write essays or long paragraphs.');
    buffer.writeln('2. ANSWER DIRECTLY: Answer the user\'s exact question directly in the very first sentence.');
    buffer.writeln('3. SIMPLE HUMAN LANGUAGE: Always write in simple, everyday language that normal people can easily understand. Absolutely do NOT use technical jargon like "Observed Context Signals", "Operational telemetry", "Functional relevance", or "Permission sensitivity".');
    buffer.writeln('4. PHONE / DEVICE QUESTIONS: When asked about the user\'s phone or security status, answer directly using the verified evidence: Google Pixel 6 running Android 17, monitored apps, and active camera/mic protection.');
    buffer.writeln('5. GENERAL QUESTIONS: For any general privacy or technical question (e.g. what is malware, how permissions work, how to stay secure), explain simply, clearly, and helpfully in 1-2 short sentences.');
    buffer.writeln('6. ACCURACY: Use ONLY the verified facts supplied in the evidence block. Never invent timestamps, app names, or permissions.');
    buffer.writeln('7. PERMISSION VS SENSOR USE: Having a permission granted DOES NOT mean the app is currently using the camera or microphone. Always distinguish granted permission from active usage.');
    buffer.writeln('8. FOR LIST QUESTIONS: Give a brief 1-sentence intro followed by the list.');
    buffer.writeln('9. FOR GREETINGS: Respond with one short, warm, friendly sentence introducing yourself as Privacy Sentinel Guardian.');

    return buffer.toString();
  }
}
