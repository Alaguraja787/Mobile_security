/// Formal training configuration schema for future offline ML model training.
/// 
/// Supported candidate architectures: 'random_forest', 'isolation_forest', 'autoencoder', 'one_class_svm'.
/// Final architecture selection remains UNDECIDED until real physical Android telemetry is collected,
/// ingested, and distribution-analyzed.
class TrainingConfig {
  final String candidateModelType; // Candidate architecture under evaluation
  final String featureSchemaVersion;
  final double testSplitRatio;
  final int randomState;
  final int nEstimators;
  final int maxDepth;
  final double contamination; // For anomaly detection
  final String targetColumn;

  const TrainingConfig({
    this.candidateModelType = 'candidate_undecided',
    this.featureSchemaVersion = '1.0.0',
    this.testSplitRatio = 0.2,
    this.randomState = 42,
    this.nEstimators = 100,
    this.maxDepth = 15,
    this.contamination = 0.05,
    this.targetColumn = 'label',
  });

  Map<String, dynamic> toJson() {
    return {
      'candidateModelType': candidateModelType,
      'featureSchemaVersion': featureSchemaVersion,
      'testSplitRatio': testSplitRatio,
      'randomState': randomState,
      'nEstimators': nEstimators,
      'maxDepth': maxDepth,
      'contamination': contamination,
      'targetColumn': targetColumn,
    };
  }
}
