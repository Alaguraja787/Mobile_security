import '../evidence/evidence_interpreter.dart';
import '../models/evidence.dart';
import '../models/guardian_input.dart';

class ReasoningOutput {
  final String reasoningSummary;
  final String userFacingExplanation;
  final List<Inference> inferences;
  final String responseSource; // REAL_GEMINI, REAL_CLAUDE, REAL_OPENAI, LOCAL_DETERMINISTIC, RULE_BASED_FALLBACK, AI_UNAVAILABLE, ERROR
  final String? fallbackCause;
  final String? providerUsed;
  final String? modelUsed;
  final int fallbackDepth;
  final String? fallbackReason;
  final int? httpStatus;
  final int? latencyMs;

  ReasoningOutput({
    required this.reasoningSummary,
    required this.userFacingExplanation,
    required this.inferences,
    this.responseSource = 'RULE_BASED_FALLBACK',
    this.fallbackCause,
    this.providerUsed,
    this.modelUsed,
    this.fallbackDepth = 0,
    this.fallbackReason,
    this.httpStatus,
    this.latencyMs,
  });
}

/// Abstract interface for Guardian reasoners (Rule-based, Local, or LLM-backed).
abstract class GuardianReasoner {
  Future<ReasoningOutput> reason({
    required GuardianInput input,
    required InterpretationResult interpretation,
    required List<Inference> contextInferences,
  });
}
