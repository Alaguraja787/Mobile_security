import 'dart:async';
import 'dart:developer' as developer;
import '../guardian/context/conversation_context.dart';
import '../guardian/context/device_inventory_context.dart';
import '../guardian/decision/guardian_engine.dart';
import '../guardian/models/guardian_decision.dart';
import '../guardian/reasoning/llm_reasoner.dart';
import '../models/app_telemetry.dart';
import '../models/privacy_event.dart';
import 'cloud_ai_service.dart';
import 'llm/llm_gateway.dart';
import 'llm/llm_provider.dart';
import 'llm/model_router.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final GuardianDecision? decision;
  final String responseSource; // REAL_GEMINI, REAL_CLAUDE, REAL_OPENAI, LOCAL_DETERMINISTIC, RULE_BASED_FALLBACK, AI_UNAVAILABLE, ERROR
  final String? intent;
  final String? targetApp;
  final String? targetPermission;
  final int? latencyMs;
  final String? fallbackCause;
  final String? providerUsed;
  final String? modelUsed;
  final int fallbackDepth;
  final String? fallbackReason;
  final int? httpStatus;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.decision,
    this.responseSource = 'REAL_GEMINI',
    this.intent,
    this.targetApp,
    this.targetPermission,
    this.latencyMs,
    this.fallbackCause,
    this.providerUsed,
    this.modelUsed,
    this.fallbackDepth = 0,
    this.fallbackReason,
    this.httpStatus,
  });
}

/// Unified Service connecting Phase 3 Guardian Engine, LLM Reasoner, and Chat / Voice UI.
///
/// Maintains canonical cross-turn conversation context shared uniformly across text and voice,
/// with automatic ModelRouter failover and truthful response provenance.
class GuardianService {
  late final GuardianEngine engine;
  final CloudAiService cloudAi;
  final LlmProvider provider;
  final DeviceInventoryContext inventoryContext = DeviceInventoryContext();
  final ConversationContext conversationContext = ConversationContext();
  List<AppTelemetry> _latestApps = [];

  GuardianService({
    LlmProvider? provider,
    CloudAiService? cloudAiService,
  })  : provider = provider ?? LlmGateway.instance,
        cloudAi = cloudAiService ?? CloudAiService(provider: provider) {
    _initEngine();
  }

  void _initEngine() {
    final llmReasoner = LLMReasoner(
      provider: provider,
    );

    engine = GuardianEngine(
      reasoner: llmReasoner,
    );
  }

  /// Updates latest cached device telemetry snapshot for conversational inquiries
  void updateTelemetryContext(List<AppTelemetry> apps) {
    _latestApps = apps;
    inventoryContext.updateApps(apps);
  }

  /// Clears device context, cached telemetry, and conversation history on disconnect
  void resetDeviceContext() {
    _latestApps = [];
    inventoryContext.clear();
    conversationContext.reset();
  }

  /// Evaluates an individual application using Guardian engine
  Future<GuardianDecision> evaluateApp(AppTelemetry app) async {
    final event = PrivacyEvent.fromMap({
      'timestamp': DateTime.now().toIso8601String(),
      'apps': [app.toJson()],
    });

    return await engine.evaluate(
      app: app,
      event: event,
    );
  }

  /// Processes user message (text or voice) using live connected device telemetry evidence
  /// and bounded cross-turn conversation context.
  Future<ChatMessage> askGuardian(String userQuery, {bool isVoice = false}) async {
    final stopwatch = Stopwatch()..start();
    final String trimmed = userQuery.trim();

    // 1. Deterministic Local Device Inventory & Usage Query Retrieval with Conversation Context
    final retrieval = inventoryContext.retrieveEvidence(
      trimmed,
      conversationContext: conversationContext,
    );
    final int usageRetrievalMs = retrieval.retrievalDurationMs;
    final int contextRetrievalMs = stopwatch.elapsedMilliseconds;

    AppTelemetry? targetApp;

    // Only associate targetApp when retrieval explicitly identifies a specific target app
    if (retrieval.targetApp != null) {
      for (final app in _latestApps) {
        if (app.packageName == retrieval.targetApp!.packageName) {
          targetApp = app;
          break;
        }
      }
    }

    final dummyEvent = PrivacyEvent.fromMap({
      'timestamp': DateTime.now().toIso8601String(),
      'apps': _latestApps.map((a) => a.toJson()).toList(),
    });

    final lastTurn = conversationContext.lastTurn;

    final historyContext = {
      'query': trimmed,
      'isVoice': isVoice,
      'inventoryEvidence': retrieval.evidencePromptBlock,
      'intent': retrieval.intent.name,
      'targetPermission': retrieval.targetPermission,
      'matchingCount': retrieval.matchingApps.length,
      'totalApps': retrieval.totalDeviceApps,
      'usage_retrieval_ms': usageRetrievalMs,
      'context_retrieval_ms': contextRetrievalMs,
      'recentUserMessage': lastTurn?.userMessage,
      'recentAssistantResponse': lastTurn?.assistantResponse,
      'recentIntent': lastTurn?.intent.name,
      'recentAppName': lastTurn?.resolvedAppName,
      'recentPermission': lastTurn?.resolvedPermission,
    };

    final geminiTimer = Stopwatch()..start();
    final GuardianDecision decision = await engine.evaluate(
      app: targetApp,
      event: dummyEvent,
      historyContext: historyContext,
    );
    final int geminiRequestMs = geminiTimer.elapsedMilliseconds;
    final int totalResponseMs = stopwatch.elapsedMilliseconds;

    final String responseSource = decision.responseSource;

    // Log development-only audit diagnostics (NEVER log sensitive data or API keys)
    developer.log(
      'GUARDIAN_REQUEST_AUDIT: intent=${retrieval.intent.name} | targetApp=${retrieval.targetApp?.packageName} | targetPerm=${retrieval.targetPermission} | evidenceCount=${retrieval.matchingApps.length} | responseSource=$responseSource | provider=${decision.providerUsed} | model=${decision.modelUsed} | depth=${decision.fallbackDepth} | fallbackCause=${decision.fallbackCause} | usage_ms=$usageRetrievalMs | gemini_ms=$geminiRequestMs | total_ms=$totalResponseMs',
      name: 'GuardianService',
    );

    final String responseText = decision.userFacingExplanation.isNotEmpty
        ? decision.userFacingExplanation
        : decision.summary;

    final resolvedAppName = targetApp?.appName ?? retrieval.targetApp?.appName;
    final resolvedPackageName = targetApp?.packageName ?? retrieval.targetApp?.packageName;

    // 2. Record this completed turn into bounded conversation context
    conversationContext.recordTurn(
      userMessage: trimmed,
      assistantResponse: responseText,
      intent: retrieval.intent,
      resolvedAppName: resolvedAppName,
      resolvedPackageName: resolvedPackageName,
      resolvedPermission: retrieval.targetPermission,
      evidenceSummary: decision.summary,
    );

    return ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      text: responseText,
      isUser: false,
      timestamp: DateTime.now(),
      decision: decision,
      responseSource: responseSource,
      intent: retrieval.intent.name,
      targetApp: resolvedAppName,
      targetPermission: retrieval.targetPermission,
      latencyMs: geminiRequestMs,
      fallbackCause: decision.fallbackCause,
      providerUsed: decision.providerUsed,
      modelUsed: decision.modelUsed,
      fallbackDepth: decision.fallbackDepth,
      fallbackReason: decision.fallbackReason,
      httpStatus: decision.httpStatus,
    );
  }
}
