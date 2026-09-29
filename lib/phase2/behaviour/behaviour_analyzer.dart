import '../feature_engineering/feature_vector.dart';
import 'behaviour_indicator.dart';

/// Interprets local model inference and extracts factual telemetry observations.
/// 
/// Invariant:
/// - Does not make final security verdicts or alert/block actions (delegated to Phase 3).
/// - When model is unready, preserves null anomaly score and confidence.
class BehaviourAnalyzer {
  const BehaviourAnalyzer();

  List<BehaviourIndicator> analyzeObservations(FeatureVector vector) {
    final indicators = <BehaviourIndicator>[];

    // Screen locked + heavy upload observation
    final screenLocked = vector.getValueByName('device_screen_locked');
    final uploadBytes = vector.getValueByName('app_upload_bytes_24h');
    if (screenLocked.rawValue == true &&
        uploadBytes.numericValue != null &&
        uploadBytes.numericValue! > 5 * 1024 * 1024) {
      indicators.add(BehaviourIndicator(
        code: 'SCREEN_LOCKED_HEAVY_UPLOAD',
        category: 'network',
        message: 'High network upload (> 5MB) observed while device screen locked.',
        context: {'uploadBytes': uploadBytes.numericValue},
      ));
    }

    // Overlay Op observation
    final overlayOp = vector.getValueByName('app_has_overlay_op');
    if (overlayOp.rawValue == true) {
      indicators.add(const BehaviourIndicator(
        code: 'OVERLAY_CAPABILITY_ENABLED',
        category: 'app_ops',
        message: 'Application possesses System Alert Window / Overlay capability.',
      ));
    }

    // Usage Access Op observation
    final usageOp = vector.getValueByName('app_has_usage_access_op');
    if (usageOp.rawValue == true) {
      indicators.add(const BehaviourIndicator(
        code: 'USAGE_ACCESS_CAPABILITY_ENABLED',
        category: 'app_ops',
        message: 'Application possesses package usage statistics query capability.',
      ));
    }

    // Sensitive sensor permissions observation
    final camPerm = vector.getValueByName('app_perm_camera_granted');
    final micPerm = vector.getValueByName('app_perm_record_audio_granted');
    if (camPerm.rawValue == true && micPerm.rawValue == true) {
      indicators.add(const BehaviourIndicator(
        code: 'CAMERA_AND_MIC_GRANTED',
        category: 'permissions',
        message: 'Both camera and microphone permissions are granted.',
      ));
    }

    // Dangerous permissions count observation
    final dangerousCount = vector.getValueByName('app_dangerous_granted_count');
    if (dangerousCount.numericValue != null && dangerousCount.numericValue! >= 5) {
      indicators.add(BehaviourIndicator(
        code: 'HIGH_DANGEROUS_PERMISSIONS_COUNT',
        category: 'permissions',
        message: 'Application holds 5 or more dangerous runtime permissions.',
        context: {'dangerousCount': dangerousCount.numericValue},
      ));
    }

    // Root observation
    final rootDetected = vector.getValueByName('device_root_heuristic_detected');
    if (rootDetected.rawValue == true) {
      indicators.add(const BehaviourIndicator(
        code: 'ROOT_HEURISTIC_PRESENT',
        category: 'device_security',
        message: 'Heuristic root artifacts or binaries detected in device environment.',
      ));
    }

    // Accessibility service observation
    final accessibility = vector.getValueByName('device_accessibility_enabled');
    if (accessibility.rawValue == true) {
      indicators.add(const BehaviourIndicator(
        code: 'ACCESSIBILITY_ACTIVE',
        category: 'device_security',
        message: 'Device accessibility services are enabled.',
      ));
    }

    return indicators;
  }
}
