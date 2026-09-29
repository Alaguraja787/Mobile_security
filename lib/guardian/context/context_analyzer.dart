import '../evidence/evidence_interpreter.dart';
import '../models/evidence.dart';
import '../models/guardian_input.dart';

/// Evaluates facts against device context and app behavior to generate structured inferences.
class ContextAnalyzer {
  List<Inference> analyzeContext(GuardianInput input, InterpretationResult interpretation) {
    final List<Inference> inferences = [];
    final facts = interpretation.facts;
    final factIds = facts.map((f) => f.id).toSet();

    final isScreenLocked = factIds.contains('fact_screen_locked') &&
        facts.firstWhere((f) => f.id == 'fact_screen_locked').rawValue == true;

    final hasHeavyUpload = factIds.contains('fact_heavy_upload');
    final hasOverlay = factIds.contains('fact_overlay_permission');
    final hasAccessibility = factIds.contains('fact_accessibility_enabled');
    final hasCamera = factIds.contains('fact_camera_in_use');
    final hasMic = factIds.contains('fact_mic_in_use');

    // Rule 1: High upload while screen locked
    if (isScreenLocked && hasHeavyUpload) {
      inferences.add(Inference(
        id: 'inf_locked_heavy_upload',
        statement: 'Application performed significant data upload while screen was locked and device inactive.',
        supportingFactIds: ['fact_screen_locked', 'fact_heavy_upload'],
        reasoningCategory: 'NETWORK_PRIVACY',
      ));
    }

    // Rule 2: Overlay permission granted with active sensor or heavy data
    if (hasOverlay && (hasHeavyUpload || hasCamera || hasMic)) {
      inferences.add(Inference(
        id: 'inf_overlay_sensor_risk',
        statement: 'System overlay permission is enabled alongside sensitive resource or network activity.',
        supportingFactIds: [
          'fact_overlay_permission',
          if (hasHeavyUpload) 'fact_heavy_upload',
          if (hasCamera) 'fact_camera_in_use',
          if (hasMic) 'fact_mic_in_use',
        ],
        reasoningCategory: 'PERMISSION_EXPLOIT',
      ));
    }

    // Rule 3: Accessibility enabled with network transmission
    if (hasAccessibility && hasHeavyUpload) {
      inferences.add(Inference(
        id: 'inf_accessibility_exfiltration',
        statement: 'System accessibility service is enabled while outbound network activity is detected.',
        supportingFactIds: ['fact_accessibility_enabled', 'fact_heavy_upload'],
        reasoningCategory: 'ACCESSIBILITY_MONITORING',
      ));
    }

    // Rule 4: Overlay permission combined with Accessibility service
    if (hasOverlay && hasAccessibility) {
      inferences.add(Inference(
        id: 'inf_overlay_accessibility_combo',
        statement: 'Application holds both system overlay and accessibility service privileges.',
        supportingFactIds: ['fact_overlay_permission', 'fact_accessibility_enabled'],
        reasoningCategory: 'PERMISSION_COMBO_RISK',
      ));
    }

    // Default context inference if facts exist but no high-risk combinations triggered
    if (inferences.isEmpty && facts.isNotEmpty) {
      inferences.add(Inference(
        id: 'inf_baseline_activity',
        statement: 'Observed telemetry signals represent standard application activity context.',
        supportingFactIds: facts.map((f) => f.id).toList(),
        reasoningCategory: 'STANDARD_BEHAVIOR',
      ));
    }

    return inferences;
  }
}
