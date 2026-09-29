import '../schemas/feature_definition.dart';

/// Strongly-typed container for a single extracted feature value.
/// 
/// Preserves exact availability status from Phase 1 telemetry:
/// VALID, ZERO_REPORTED, DENIED, RESTRICTED, UNAVAILABLE, ERROR, UNKNOWN.
/// 
/// Missing values are NEVER blindly converted to 0.0 or false.
class FeatureValue {
  final String featureName;
  final int featureIndex;
  final FeatureDataType dataType;
  final dynamic rawValue;
  final double? numericValue;
  final FeatureAvailabilityStatus status;

  const FeatureValue({
    required this.featureName,
    required this.featureIndex,
    required this.dataType,
    required this.rawValue,
    required this.numericValue,
    required this.status,
  });

  /// Factory for a valid numeric value
  factory FeatureValue.validNumeric({
    required String name,
    required int index,
    required num value,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: FeatureDataType.numeric,
      rawValue: value,
      numericValue: value.toDouble(),
      status: FeatureAvailabilityStatus.valid,
    );
  }

  /// Factory for a valid integer count value
  factory FeatureValue.validCount({
    required String name,
    required int index,
    required int count,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: FeatureDataType.count,
      rawValue: count,
      numericValue: count.toDouble(),
      status: FeatureAvailabilityStatus.valid,
    );
  }

  /// Factory for a valid boolean flag (encoded numerically as 1.0 or 0.0)
  factory FeatureValue.validBoolean({
    required String name,
    required int index,
    required bool flag,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: FeatureDataType.boolean,
      rawValue: flag,
      numericValue: flag ? 1.0 : 0.0,
      status: FeatureAvailabilityStatus.valid,
    );
  }

  /// Factory for genuine zero traffic or duration reported by OS
  factory FeatureValue.zeroReported({
    required String name,
    required int index,
    required FeatureDataType dataType,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: dataType,
      rawValue: 0,
      numericValue: 0.0,
      status: FeatureAvailabilityStatus.zeroReported,
    );
  }

  /// Factory for missing value due to permission restriction / denied AppOps
  factory FeatureValue.restricted({
    required String name,
    required int index,
    required FeatureDataType dataType,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: dataType,
      rawValue: null,
      numericValue: null,
      status: FeatureAvailabilityStatus.restricted,
    );
  }

  /// Factory for missing value due to runtime permission denial
  factory FeatureValue.denied({
    required String name,
    required int index,
    required FeatureDataType dataType,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: dataType,
      rawValue: null,
      numericValue: null,
      status: FeatureAvailabilityStatus.denied,
    );
  }

  /// Factory for missing value due to platform service unavailability or unsupported API
  factory FeatureValue.unavailable({
    required String name,
    required int index,
    required FeatureDataType dataType,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: dataType,
      rawValue: null,
      numericValue: null,
      status: FeatureAvailabilityStatus.unavailable,
    );
  }

  /// Factory for missing value due to query exception or IPC binder error
  factory FeatureValue.error({
    required String name,
    required int index,
    required FeatureDataType dataType,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: dataType,
      rawValue: null,
      numericValue: null,
      status: FeatureAvailabilityStatus.error,
    );
  }

  /// Factory for unknown or uncollected status
  factory FeatureValue.unknown({
    required String name,
    required int index,
    required FeatureDataType dataType,
  }) {
    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: dataType,
      rawValue: null,
      numericValue: null,
      status: FeatureAvailabilityStatus.unknown,
    );
  }

  bool get isPresent => status.isPresent;
  bool get isMissing => status.isMissing;

  factory FeatureValue.fromJson(Map<String, dynamic> json) {
    final name = json['featureName']?.toString() ?? '';
    final index = (json['featureIndex'] as num?)?.toInt() ?? 0;
    final typeName = json['dataType']?.toString() ?? 'numeric';
    final dataType = FeatureDataType.values.firstWhere(
      (d) => d.name == typeName,
      orElse: () => FeatureDataType.numeric,
    );
    final rawValue = json['rawValue'];
    final numericValue = (json['numericValue'] as num?)?.toDouble();
    final statusStr = json['status']?.toString() ?? 'UNKNOWN';
    final status = FeatureAvailabilityStatus.fromString(statusStr);

    return FeatureValue(
      featureName: name,
      featureIndex: index,
      dataType: dataType,
      rawValue: rawValue,
      numericValue: numericValue,
      status: status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'featureName': featureName,
      'featureIndex': featureIndex,
      'dataType': dataType.name,
      'rawValue': rawValue,
      'numericValue': numericValue,
      'status': status.toFormattedString(),
      'isPresent': isPresent,
    };
  }

  @override
  String toString() {
    return 'FeatureValue($featureName[$featureIndex]: raw=$rawValue, num=$numericValue, status=${status.toFormattedString()})';
  }
}
