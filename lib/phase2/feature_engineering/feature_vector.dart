import '../schemas/feature_schema.dart';
import 'feature_value.dart';

/// Immutable, deterministically ordered feature vector representing an application snapshot
/// extracted according to a specific versioned FeatureSchema.
class FeatureVector {
  final String schemaVersion;
  final String packageName;
  final String timestamp;
  final List<FeatureValue> values;
  final Map<String, FeatureValue> _valuesByName;

  FeatureVector({
    required this.schemaVersion,
    required this.packageName,
    required this.timestamp,
    required this.values,
    FeatureSchema? schema,
  }) : _valuesByName = {} {
    final effectiveSchema = schema ?? FeatureSchema.v1;
    if (schemaVersion != effectiveSchema.schemaVersion) {
      throw ArgumentError(
        'Schema version mismatch: vector has "$schemaVersion", expected "${effectiveSchema.schemaVersion}"',
      );
    }
    if (values.length != effectiveSchema.featureCount) {
      throw ArgumentError(
        'FeatureVector length mismatch: expected ${effectiveSchema.featureCount} features, received ${values.length}',
      );
    }

    final seenNames = <String>{};
    final seenIndices = <int>{};

    for (int i = 0; i < values.length; i++) {
      final val = values[i];
      final expectedDef = effectiveSchema.getFeatureByIndex(i);

      if (val.featureIndex != i) {
        throw ArgumentError(
          'Feature ordering error at index $i: expected index $i, found ${val.featureIndex}',
        );
      }
      if (seenIndices.contains(val.featureIndex)) {
        throw ArgumentError('Duplicate feature index: ${val.featureIndex}');
      }
      seenIndices.add(val.featureIndex);

      if (val.featureName != expectedDef.name) {
        throw ArgumentError(
          'Feature name mismatch at index $i: expected "${expectedDef.name}", found "${val.featureName}"',
        );
      }
      if (seenNames.contains(val.featureName)) {
        throw ArgumentError('Duplicate feature name: "${val.featureName}"');
      }
      seenNames.add(val.featureName);

      _valuesByName[val.featureName] = val;
    }
  }

  int get length => values.length;

  FeatureValue getValueByName(String name) {
    final val = _valuesByName[name];
    if (val == null) {
      throw ArgumentError('Feature "$name" not found in FeatureVector');
    }
    return val;
  }

  FeatureValue getValueByIndex(int index) {
    if (index < 0 || index >= values.length) {
      throw RangeError.range(index, 0, values.length - 1, 'Feature index out of range');
    }
    return values[index];
  }

  /// Returns list of nullable numeric values strictly adhering to feature ordering
  List<double?> toNullableNumericList() {
    return values.map((v) => v.numericValue).toList();
  }

  /// Returns binary missingness mask (0.0 = present, 1.0 = missing)
  List<double> toMissingMask() {
    return values.map((v) => v.isMissing ? 1.0 : 0.0).toList();
  }

  /// Evidence map for explainability in downstream layers (Phase 2 analysis & Phase 3 reasoning)
  Map<String, dynamic> toEvidenceMap() {
    return {
      for (var v in values)
        v.featureName: {
          'index': v.featureIndex,
          'rawValue': v.rawValue,
          'numericValue': v.numericValue,
          'status': v.status.toFormattedString(),
          'isPresent': v.isPresent,
        }
    };
  }

  factory FeatureVector.fromJson(
    Map<String, dynamic> json, {
    FeatureSchema? schema,
  }) {
    final schemaVersion =
        json['schemaVersion']?.toString() ?? FeatureSchema.v1.schemaVersion;
    final packageName = json['packageName']?.toString() ?? '';
    final timestamp = json['timestamp']?.toString() ?? '';
    final rawValues = (json['values'] as List<dynamic>?) ?? [];
    final values = rawValues
        .map((v) => FeatureValue.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();

    return FeatureVector(
      schemaVersion: schemaVersion,
      packageName: packageName,
      timestamp: timestamp,
      values: values,
      schema: schema,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'packageName': packageName,
      'timestamp': timestamp,
      'values': values.map((v) => v.toJson()).toList(),
    };
  }
}
