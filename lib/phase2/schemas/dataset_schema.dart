/// Dataset schema contract for real Android telemetry training datasets.
/// 
/// Strictly defines the format for persistent storage, export, and offline ML training
/// ensuring compatibility between real Android physical device telemetry and ML training pipelines.
class DatasetSchema {
  static const String version = '1.0.0';

  final String schemaVersion;
  final String featureSchemaVersion;
  final List<String> requiredMetadataFields;
  final List<String> requiredFeatureFields;

  const DatasetSchema({
    this.schemaVersion = version,
    this.featureSchemaVersion = '1.0.0',
    this.requiredMetadataFields = const [
      'record_id',
      'device_id_hash',
      'android_version',
      'sdk_int',
      'timestamp',
      'package_name',
      'collector_health_status',
    ],
    this.requiredFeatureFields = const [
      'features',
      'missing_mask',
      'availability_statuses',
    ],
  });

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'featureSchemaVersion': featureSchemaVersion,
      'requiredMetadataFields': requiredMetadataFields,
      'requiredFeatureFields': requiredFeatureFields,
    };
  }
}
