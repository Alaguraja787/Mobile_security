import '../evidence/evidence_interpreter.dart';
import '../models/evidence.dart';
import '../models/guardian_input.dart';
import '../models/severity_confidence.dart';

/// Generates actionable, non-destructive user recommendations.
class RecommendationEngine {
  List<GuardianRecommendation> generateRecommendations({
    required GuardianInput input,
    required InterpretationResult interpretation,
    required List<Inference> inferences,
    required GuardianSeverity severity,
  }) {
    final List<GuardianRecommendation> recommendations = [];
    final appName = input.targetApp?.appName ?? input.targetApp?.packageName ?? 'Application';
    final factIds = interpretation.facts.map((f) => f.id).toSet();

    if (factIds.contains('fact_heavy_upload') && factIds.contains('fact_screen_locked')) {
      recommendations.add(GuardianRecommendation(
        id: 'rec_background_data',
        title: 'Review Background Data Usage',
        description: 'Check $appName\'s background data allowance in Android Settings.',
        priority: 'MEDIUM',
        suggestedSettingsPath: 'Settings -> Apps -> $appName -> Mobile data & Wi-Fi',
      ));
    }

    if (factIds.contains('fact_overlay_permission')) {
      recommendations.add(GuardianRecommendation(
        id: 'rec_overlay_permission',
        title: 'Review Display Over Other Apps Permission',
        description: 'Verify if $appName requires permission to draw over other apps.',
        priority: 'MEDIUM',
        suggestedSettingsPath: 'Settings -> Apps -> Special app access -> Display over other apps',
      ));
    }

    if (factIds.contains('fact_accessibility_enabled')) {
      recommendations.add(GuardianRecommendation(
        id: 'rec_accessibility_review',
        title: 'Inspect Accessibility Service Access',
        description: 'Ensure $appName is an authorized accessibility provider.',
        priority: 'HIGH',
        suggestedSettingsPath: 'Settings -> Accessibility',
      ));
    }

    if (recommendations.isEmpty) {
      recommendations.add(GuardianRecommendation(
        id: 'rec_continue_monitoring',
        title: 'Continue Regular Monitoring',
        description: 'No immediate user action required for $appName.',
        priority: 'LOW',
      ));
    }

    return recommendations;
  }
}
