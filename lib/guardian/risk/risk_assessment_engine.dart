import '../evidence/evidence_interpreter.dart';
import '../models/evidence.dart';
import '../models/guardian_input.dart';
import '../models/severity_confidence.dart';

class AssessmentResult {
  final GuardianSeverity severity;
  final GuardianConfidence confidence;

  AssessmentResult({
    required this.severity,
    required this.confidence,
  });
}

/// Evaluates severity and confidence separately based on observed evidence and availability states.
class RiskAssessmentEngine {
  AssessmentResult assess(GuardianInput input, InterpretationResult interpretation, List<Inference> inferences) {
    // 1. Calculate Severity from Evidence & Inferences
    GuardianSeverity severity = GuardianSeverity.LOW;

    final infIds = inferences.map((i) => i.id).toSet();

    if (infIds.contains('inf_accessibility_exfiltration') ||
        infIds.contains('inf_overlay_sensor_risk') ||
        infIds.contains('inf_overlay_accessibility_combo')) {
      severity = GuardianSeverity.HIGH;
    } else if (infIds.contains('inf_locked_heavy_upload')) {
      severity = GuardianSeverity.MEDIUM;
    } else if (interpretation.facts.isNotEmpty) {
      severity = GuardianSeverity.LOW;
    }

    // 2. Calculate Confidence score (0.0 to 1.0) based on telemetry availability
    double confidenceScore = 1.0;
    final List<String> availabilityImpacts = [];

    // Impact of missing/restricted telemetry
    for (final uncertainty in interpretation.uncertainties) {
      confidenceScore -= 0.15;
      availabilityImpacts.add('${uncertainty.affectedSignal}: ${uncertainty.reason}');
    }

    // Impact of mock Phase 2 baseline
    if (input.intelligenceSnapshot.isMock) {
      confidenceScore -= 0.10;
      availabilityImpacts.add('Phase 2 Local Intelligence ML baseline is uninitialized (using mock provider).');
    }

    // Clamp confidence score between 0.10 and 1.0
    confidenceScore = confidenceScore.clamp(0.10, 1.0);

    String justification;
    if (confidenceScore >= 0.85) {
      justification = 'High confidence based on complete telemetry availability.';
    } else if (confidenceScore >= 0.60) {
      justification = 'Moderate confidence due to partial telemetry restrictions or uninitialized ML baseline.';
    } else {
      justification = 'Low confidence due to significant telemetry unavailability or missing system permissions.';
    }

    return AssessmentResult(
      severity: severity,
      confidence: GuardianConfidence(
        score: confidenceScore,
        justification: justification,
        availabilityImpacts: availabilityImpacts,
      ),
    );
  }
}
