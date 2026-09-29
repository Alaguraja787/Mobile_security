/// Configuration for the Phase 2 Local Intelligence runtime pipeline.
class Phase2Config {
  final String featureSchemaVersion;
  final String? modelAssetPath;
  final bool enableOnnxRuntime;
  final bool enableObservationAnalysis;
  final int maxDatasetCollectorBuffer;

  const Phase2Config({
    this.featureSchemaVersion = '1.0.0',
    this.modelAssetPath,
    this.enableOnnxRuntime = true,
    this.enableObservationAnalysis = true,
    this.maxDatasetCollectorBuffer = 1000,
  });

  Map<String, dynamic> toJson() {
    return {
      'featureSchemaVersion': featureSchemaVersion,
      'modelAssetPath': modelAssetPath,
      'enableOnnxRuntime': enableOnnxRuntime,
      'enableObservationAnalysis': enableObservationAnalysis,
      'maxDatasetCollectorBuffer': maxDatasetCollectorBuffer,
    };
  }
}
