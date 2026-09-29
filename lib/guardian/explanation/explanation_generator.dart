import '../evidence/evidence_interpreter.dart';
import '../models/guardian_input.dart';
import '../models/severity_confidence.dart';
import '../reasoning/guardian_reasoner.dart';

/// Generates clear, human-understandable user explanations explaining WHAT happened, WHY it matters, and WHAT uncertainty exists.
class ExplanationGenerator {
  String generateExplanation({
    required GuardianInput input,
    required InterpretationResult interpretation,
    required ReasoningOutput reasoningOutput,
    required GuardianSeverity severity,
    required GuardianConfidence confidence,
  }) {
    return reasoningOutput.userFacingExplanation.trim();
  }
}
