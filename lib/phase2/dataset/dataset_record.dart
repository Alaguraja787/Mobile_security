import '../feature_engineering/feature_vector.dart';
import '../schemas/feature_schema.dart';

/// Single telemetry dataset record containing real device snapshot and extracted features.
class DatasetRecord {
  final String recordId;
  final String? sessionId;
  final String deviceIdHash;
  final String androidVersion;
  final int sdkInt;
  final String timestamp;
  final String packageName;
  final String collectorHealthStatus;
  final Map<String, dynamic> rawTelemetry;
  final FeatureVector featureVector;
  final String? label; // Optional ground truth annotation for training / evaluation

  const DatasetRecord({
    required this.recordId,
    this.sessionId,
    required this.deviceIdHash,
    required this.androidVersion,
    required this.sdkInt,
    required this.timestamp,
    required this.packageName,
    required this.collectorHealthStatus,
    required this.rawTelemetry,
    required this.featureVector,
    this.label,
  });

  factory DatasetRecord.fromJson(
    Map<String, dynamic> json, {
    FeatureSchema? schema,
  }) {
    final recordId = json['recordId']?.toString() ?? '';
    final sessionId = json['sessionId']?.toString();
    final deviceIdHash = json['deviceIdHash']?.toString() ?? '';
    final androidVersion = json['androidVersion']?.toString() ?? '';
    final sdkInt = (json['sdkInt'] as num?)?.toInt() ?? 0;
    final timestamp = json['timestamp']?.toString() ?? '';
    final packageName = json['packageName']?.toString() ?? '';
    final collectorHealthStatus =
        json['collectorHealthStatus']?.toString() ?? 'UNKNOWN';
    final rawTelemetry =
        Map<String, dynamic>.from((json['rawTelemetry'] as Map?) ?? {});
    final featureVector = FeatureVector.fromJson(
      Map<String, dynamic>.from((json['featureVector'] as Map?) ?? {}),
      schema: schema,
    );
    final label = json['label']?.toString();

    return DatasetRecord(
      recordId: recordId,
      sessionId: sessionId,
      deviceIdHash: deviceIdHash,
      androidVersion: androidVersion,
      sdkInt: sdkInt,
      timestamp: timestamp,
      packageName: packageName,
      collectorHealthStatus: collectorHealthStatus,
      rawTelemetry: rawTelemetry,
      featureVector: featureVector,
      label: label,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'recordId': recordId,
      if (sessionId != null) 'sessionId': sessionId,
      'deviceIdHash': deviceIdHash,
      'androidVersion': androidVersion,
      'sdkInt': sdkInt,
      'timestamp': timestamp,
      'packageName': packageName,
      'collectorHealthStatus': collectorHealthStatus,
      'rawTelemetry': rawTelemetry,
      'featureVector': featureVector.toJson(),
      'label': label,
    };
  }
}
