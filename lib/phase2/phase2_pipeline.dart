import '../models/app_telemetry.dart';
import '../models/privacy_event.dart';
import 'behaviour/behaviour_analyzer.dart';
import 'behaviour/behaviour_indicator.dart';
import 'config/phase2_config.dart';
import 'feature_engineering/feature_extractor.dart';
import 'model/local_model.dart';
import 'model/model_status.dart';
import 'onnx/onnx_model_runner.dart';
import 'preprocessing/feature_preprocessor.dart';
import 'result/phase2_result.dart';
import 'schemas/feature_schema.dart';

/// Main Coordinator for Phase 2 — Local Intelligence.
/// 
/// Consumes Phase 1 PrivacyEvent and AppTelemetry, executes feature extraction,
/// preprocessing, local model inference, and behaviour analysis to produce Phase2Result.
/// 
/// Invariant:
/// Strictly reports MODEL_NOT_READY and PREPROCESSOR_NOT_READY when model is uncalibrated.
/// Never outputs synthetic or fake placeholder scores.
class Phase2Pipeline {
  final Phase2Config config;
  final FeatureSchema featureSchema;
  final FeatureExtractor featureExtractor;
  final FeaturePreprocessor preprocessor;
  final LocalModel model;
  final BehaviourAnalyzer behaviourAnalyzer;

  Phase2Pipeline({
    Phase2Config? config,
    FeatureSchema? featureSchema,
    FeatureExtractor? featureExtractor,
    FeaturePreprocessor? preprocessor,
    LocalModel? model,
    BehaviourAnalyzer? behaviourAnalyzer,
  })  : config = config ?? const Phase2Config(),
        featureSchema = featureSchema ?? FeatureSchema.v1,
        featureExtractor = featureExtractor ?? FeatureExtractor(schema: featureSchema ?? FeatureSchema.v1),
        preprocessor = preprocessor ?? FeaturePreprocessor(schema: featureSchema ?? FeatureSchema.v1),
        model = model ?? OnnxModelRunner(modelAssetPath: config?.modelAssetPath),
        behaviourAnalyzer = behaviourAnalyzer ?? const BehaviourAnalyzer();

  /// Initializes local models and preprocessors.
  Future<void> initialize() async {
    if (config.enableOnnxRuntime) {
      await model.load();
    }
  }

  /// Processes an AppTelemetry snapshot within a PrivacyEvent.
  Future<Phase2Result> analyzeApp({
    required AppTelemetry app,
    required PrivacyEvent event,
  }) async {
    // 1. Feature Extraction (Deterministic 32 features, honest missing data handling)
    final featureVector = featureExtractor.extract(app, event);

    // 2. Preprocessing & Normalization
    final prepResult = preprocessor.process(featureVector);

    // 3. Model Inference (Enforcing enableOnnxRuntime configuration)
    ModelInferenceResult inferenceResult;
    if (!config.enableOnnxRuntime) {
      inferenceResult = ModelInferenceResult.notReady(
        'MODEL_NOT_READY: ONNX runtime disabled by configuration.',
      );
    } else if (prepResult.isReady && prepResult.tensor != null && model.isReady) {
      inferenceResult = await model.predict(prepResult.tensor!);
    } else {
      // Model or preprocessor not ready -> honest unready state
      inferenceResult = ModelInferenceResult.notReady(
        !model.isReady
            ? 'MODEL_NOT_READY: Real trained model binary has not been loaded.'
            : 'PREPROCESSOR_NOT_READY: Feature preprocessor parameters not fitted from real telemetry.',
      );
    }

    // 4. Behaviour Analysis (Enforcing enableObservationAnalysis configuration)
    final List<BehaviourIndicator> indicators = config.enableObservationAnalysis
        ? behaviourAnalyzer.analyzeObservations(featureVector)
        : const [];

    // 5. Build Unified Phase2Result
    return Phase2Result(
      packageName: app.packageName,
      timestamp: event.timestamp,
      modelStatus: !config.enableOnnxRuntime ? ModelStatus.notReady : model.status,
      preprocessorStatus: preprocessor.status,
      featureSchemaVersion: featureSchema.schemaVersion,
      anomalyScore: inferenceResult.anomalyScore,
      confidence: inferenceResult.confidence,
      behaviourIndicators: indicators,
      evidence: featureVector.toEvidenceMap(),
      modelMetadata: model.metadata,
      message: inferenceResult.message,
    );
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await model.dispose();
  }
}
