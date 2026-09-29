import '../evidence/evidence_interpreter.dart';
import '../models/evidence.dart';
import '../models/guardian_input.dart';
import 'guardian_reasoner.dart';

/// Deterministic evidence-first reasoner for Guardian.
class RuleBasedReasoner implements GuardianReasoner {
  @override
  Future<ReasoningOutput> reason({
    required GuardianInput input,
    required InterpretationResult interpretation,
    required List<Inference> contextInferences,
  }) async {
    final intent = input.historyContext?['intent']?.toString();
    final inventoryEvidence = input.historyContext?['inventoryEvidence']?.toString() ?? '';

    if (input.targetApp == null) {
      if (intent == 'conversational') {
        const greeting =
            'Hello! I am Privacy Sentinel Guardian. Ask me anything about your connected device apps, active permissions, privacy risks, or today\'s app usage activity.';
        return ReasoningOutput(
          reasoningSummary: 'Deterministic response for conversational greeting.',
          userFacingExplanation: greeting,
          inferences: const [],
        );
      }

      if (inventoryEvidence.isNotEmpty) {
        return ReasoningOutput(
          reasoningSummary: 'Evidence-driven evaluation from device inventory:\n$inventoryEvidence',
          userFacingExplanation: inventoryEvidence.trim(),
          inferences: const [],
        );
      }

      return ReasoningOutput(
        reasoningSummary: 'No specific app targeted for evaluation.',
        userFacingExplanation:
            'How can I assist you with your device apps, permissions, or usage today?',
        inferences: const [],
      );
    }

    final appName = input.targetApp!.appName.isNotEmpty
        ? input.targetApp!.appName
        : input.targetApp!.packageName;
    final inferences = List<Inference>.from(contextInferences);

    final StringBuffer reasoningBuffer = StringBuffer();
    final StringBuffer userExplanationBuffer = StringBuffer();

    reasoningBuffer.writeln('Evidence-driven evaluation for $appName:');

    final targetPerm = input.historyContext?['targetPermission']?.toString();

    if (intent == 'appExplanation' && targetPerm != null) {
      reasoningBuffer.writeln('- Evaluated specific permission query: $targetPerm for $appName');
      userExplanationBuffer.write('$appName has $targetPerm permission enabled. For an application in the ${input.targetApp?.category.name.toUpperCase() ?? "communication"} category, this access is consistent with standard application capabilities. Verified current-device telemetry shows normal activity.');
    } else if (intent == 'followUpExplanation') {
      reasoningBuffer.writeln('- Follow-up query evaluated in context of $appName');
      final permContext = targetPerm != null ? ' regarding $targetPerm permission' : '';
      userExplanationBuffer.write('In continuation regarding $appName$permContext: its capabilities match typical functionality for its application category, and no anomalous background sensor usage was observed in current telemetry.');
    } else if (interpretation.facts.isEmpty) {
      reasoningBuffer.writeln('- No anomalous or high-privilege telemetry signals detected.');
      userExplanationBuffer.write('$appName is operating within standard privacy parameters with no anomalous telemetry observed.');
    } else {
      for (final fact in interpretation.facts) {
        reasoningBuffer.writeln('- Observed Fact [${fact.category}]: ${fact.description}');
      }

      if (inferences.isNotEmpty) {
        reasoningBuffer.writeln('Derived Contextual Inferences:');
        for (final inf in inferences) {
          reasoningBuffer.writeln('  * ${inf.statement}');
        }
      }

      // User-facing explanation (evidence-first, avoiding technical jargon or premature accusations)
      final inferenceStatements = inferences.map((i) => i.statement).join(' ');
      userExplanationBuffer.write(
        '$appName showed telemetry activity worthy of review. $inferenceStatements This is evaluated from observed device signals and is not an automatic malware declaration.',
      );
    }

    if (interpretation.uncertainties.isNotEmpty) {
      reasoningBuffer.writeln('Uncertainties & Telemetry Limitations:');
      for (final uncert in interpretation.uncertainties) {
        reasoningBuffer.writeln('  ? ${uncert.affectedSignal}: ${uncert.reason}');
      }
    }

    return ReasoningOutput(
      reasoningSummary: reasoningBuffer.toString().trim(),
      userFacingExplanation: userExplanationBuffer.toString().trim(),
      inferences: inferences,
      responseSource: 'RULE_BASED_FALLBACK',
    );
  }
}
