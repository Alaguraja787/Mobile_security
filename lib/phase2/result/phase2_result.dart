import '../behaviour/behaviour_indicator.dart';
import '../model/model_metadata.dart';
import '../model/model_status.dart';
import '../preprocessing/preprocessor_status.dart';

/// Unified Phase 2 Local Intelligence Result contract.
/// 
/// Emitted by the Phase 2 pipeline for consumption by Phase 3 (Reasoning / Guardian layer).
/// Invariants:
/// - Values that cannot exist before real model training remain strictly NULL.
/// - Does not use 0, false, "SAFE", or "LOW_RISK" as fake placeholders.
class Phase2Result {
  final String packageName;
  final String timestamp;
  final ModelStatus modelStatus;
  final PreprocessorStatus preprocessorStatus;
  final String featureSchemaVersion;
  final double? anomalyScore;
  final double? confidence;
  final List<BehaviourIndicator> behaviourIndicators;
  final Map<String, dynamic> evidence;
  final ModelMetadata? modelMetadata;
  final String message;

  const Phase2Result({
    required this.packageName,
    required this.timestamp,
    required this.modelStatus,
    required this.preprocessorStatus,
    required this.featureSchemaVersion,
    this.anomalyScore,
    this.confidence,
    required this.behaviourIndicators,
    required this.evidence,
    this.modelMetadata,
    required this.message,
  });

  bool get isModelInferenceAvailable =>
      modelStatus == ModelStatus.ready && anomalyScore != null;

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'timestamp': timestamp,
      'modelStatus': modelStatus.toFormattedString(),
      'preprocessorStatus': preprocessorStatus.toFormattedString(),
      'featureSchemaVersion': featureSchemaVersion,
      'anomalyScore': anomalyScore,
      'confidence': confidence,
      'isModelInferenceAvailable': isModelInferenceAvailable,
      'behaviourIndicators': behaviourIndicators.map((i) => i.toJson()).toList(),
      'evidence': evidence,
      'modelMetadata': modelMetadata?.toJson(),
      'message': message,
    };
  }
}
