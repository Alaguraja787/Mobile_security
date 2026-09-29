/// Phase 2 - Feature Definition & Types
/// 
/// Strictly defines metadata, data types, value ranges, missing value handling strategies,
/// and normalization requirements for every feature in the local intelligence layer.
library;

/// Data type of a feature in the vector
enum FeatureDataType {
  numeric,
  boolean,
  categorical,
  count,
}

/// Normalization type required for the feature during preprocessing
enum NormalizationType {
  standard, // (x - mean) / std
  minMax,   // (x - min) / (max - min)
  robust,   // (x - median) / IQR
  logScale, // log1p(x)
  none,     // raw value (e.g. binary 0/1 flags)
}

/// Exact availability status preserving Phase 1 telemetry semantics
enum FeatureAvailabilityStatus {
  valid,
  zeroReported,
  denied,
  restricted,
  unavailable,
  error,
  unknown;

  static FeatureAvailabilityStatus fromString(String status) {
    switch (status.toUpperCase()) {
      case 'VALID':
        return FeatureAvailabilityStatus.valid;
      case 'ZERO_REPORTED':
        return FeatureAvailabilityStatus.zeroReported;
      case 'DENIED':
        return FeatureAvailabilityStatus.denied;
      case 'RESTRICTED':
        return FeatureAvailabilityStatus.restricted;
      case 'UNAVAILABLE':
        return FeatureAvailabilityStatus.unavailable;
      case 'ERROR':
        return FeatureAvailabilityStatus.error;
      default:
        return FeatureAvailabilityStatus.unknown;
    }
  }

  String toFormattedString() {
    switch (this) {
      case FeatureAvailabilityStatus.valid:
        return 'VALID';
      case FeatureAvailabilityStatus.zeroReported:
        return 'ZERO_REPORTED';
      case FeatureAvailabilityStatus.denied:
        return 'DENIED';
      case FeatureAvailabilityStatus.restricted:
        return 'RESTRICTED';
      case FeatureAvailabilityStatus.unavailable:
        return 'UNAVAILABLE';
      case FeatureAvailabilityStatus.error:
        return 'ERROR';
      case FeatureAvailabilityStatus.unknown:
        return 'UNKNOWN';
    }
  }

  bool get isPresent => this == FeatureAvailabilityStatus.valid || this == FeatureAvailabilityStatus.zeroReported;
  bool get isMissing => !isPresent;
}

/// Definition of an individual feature in the versioned schema
class FeatureDefinition {
  final String name;
  final int index;
  final FeatureDataType dataType;
  final double? minExpected;
  final double? maxExpected;
  final String missingStrategyDescription;
  final NormalizationType normalizationType;
  final String schemaVersion;
  final String category;
  final String description;

  const FeatureDefinition({
    required this.name,
    required this.index,
    required this.dataType,
    this.minExpected,
    this.maxExpected,
    required this.missingStrategyDescription,
    required this.normalizationType,
    required this.schemaVersion,
    required this.category,
    required this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'index': index,
      'dataType': dataType.name,
      'minExpected': minExpected,
      'maxExpected': maxExpected,
      'missingStrategyDescription': missingStrategyDescription,
      'normalizationType': normalizationType.name,
      'schemaVersion': schemaVersion,
      'category': category,
      'description': description,
    };
  }
}
