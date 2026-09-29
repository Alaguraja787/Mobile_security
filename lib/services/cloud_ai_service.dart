import '../guardian/decision/guardian_engine.dart';
import '../guardian/models/guardian_decision.dart';
import '../guardian/reasoning/llm_reasoner.dart';
import '../models/app_telemetry.dart';
import '../models/privacy_event.dart';
import 'llm/llm_gateway.dart';
import 'llm/llm_provider.dart';

/// Cloud/Local AI Service interface for Guardian Intelligence.
///
/// Uses the central LlmGateway for all evaluations and queries with automatic failover.
class CloudAiService {
  final GuardianEngine engine;
  final LlmProvider provider;

  CloudAiService({
    LlmProvider? provider,
    GuardianEngine? engine,
  })  : provider = provider ?? LlmGateway.instance,
        engine = engine ??
            GuardianEngine(
              reasoner: LLMReasoner(
                provider: provider ?? LlmGateway.instance,
              ),
            );

  Future<GuardianDecision> evaluateEvent({
    AppTelemetry? app,
    required PrivacyEvent event,
  }) async {
    return engine.evaluate(app: app, event: event);
  }

  /// Direct LLM response generator using central LLM Gateway
  Future<String> query(String prompt) async {
    return await provider.generateResponse(prompt: prompt);
  }
}
