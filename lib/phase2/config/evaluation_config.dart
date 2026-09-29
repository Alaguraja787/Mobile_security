/// Formal evaluation configuration schema defining target benchmarks for validating models
/// trained on real telemetry.
/// 
/// IMPORTANT:
/// These metrics represent TARGET BENCHMARKS and design goals. No claim of model validity or
/// acceptability should be asserted until evaluation is executed against a held-out real dataset.
class EvaluationConfig {
  final List<String> requiredTargetMetrics;
  final double targetAccuracy;
  final double targetF1Score;
  final double targetMaximumFalsePositiveRate;
  final int targetMaximumInferenceLatencyMs;

  const EvaluationConfig({
    this.requiredTargetMetrics = const [
      'accuracy',
      'precision',
      'recall',
      'f1_score',
      'roc_auc',
      'confusion_matrix',
    ],
    this.targetAccuracy = 0.90,
    this.targetF1Score = 0.85,
    this.targetMaximumFalsePositiveRate = 0.05,
    this.targetMaximumInferenceLatencyMs = 50,
  });

  Map<String, dynamic> toJson() {
    return {
      'requiredTargetMetrics': requiredTargetMetrics,
      'targetAccuracy': targetAccuracy,
      'targetF1Score': targetF1Score,
      'targetMaximumFalsePositiveRate': targetMaximumFalsePositiveRate,
      'targetMaximumInferenceLatencyMs': targetMaximumInferenceLatencyMs,
    };
  }
}
