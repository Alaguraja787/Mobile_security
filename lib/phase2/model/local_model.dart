import '../preprocessing/preprocessed_tensor.dart';
import 'model_metadata.dart';
import 'model_status.dart';

/// Result emitted by local model inference.
/// 
/// Strictly guarantees that anomalyScore and confidence are null when model is not ready.
class ModelInferenceResult {
  final ModelStatus status;
  final double? anomalyScore;
  final double? confidence;
  final List<double>? rawOutputs;
  final String message;

  const ModelInferenceResult({
    required this.status,
    this.anomalyScore,
    this.confidence,
    this.rawOutputs,
    required this.message,
  });

  factory ModelInferenceResult.notReady([String? message]) {
    return ModelInferenceResult(
      status: ModelStatus.notReady,
      anomalyScore: null,
      confidence: null,
      rawOutputs: null,
      message: message ?? 'MODEL_NOT_READY: Local ML model has not been trained yet. Telemetry must be collected first.',
    );
  }

  factory ModelInferenceResult.ready({
    required double anomalyScore,
    required double confidence,
    List<double>? rawOutputs,
    String? message,
  }) {
    return ModelInferenceResult(
      status: ModelStatus.ready,
      anomalyScore: anomalyScore,
      confidence: confidence,
      rawOutputs: rawOutputs,
      message: message ?? 'MODEL_READY: Inference completed.',
    );
  }

  factory ModelInferenceResult.error(String errorMessage) {
    return ModelInferenceResult(
      status: ModelStatus.error,
      anomalyScore: null,
      confidence: null,
      rawOutputs: null,
      message: 'MODEL_ERROR: $errorMessage',
    );
  }

  bool get isReady => status == ModelStatus.ready;

  Map<String, dynamic> toJson() {
    return {
      'status': status.toFormattedString(),
      'anomalyScore': anomalyScore,
      'confidence': confidence,
      'rawOutputs': rawOutputs,
      'message': message,
    };
  }
}

/// Abstract contract for local ML inference models.
abstract class LocalModel {
  ModelStatus get status;

  bool get isReady => status == ModelStatus.ready;

  Future<void> load();

  Future<ModelInferenceResult> predict(PreprocessedTensor input);

  ModelMetadata? get metadata;

  Future<void> dispose();
}
