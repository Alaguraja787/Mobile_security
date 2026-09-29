import '../schemas/dataset_schema.dart';
import '../schemas/feature_schema.dart';
import 'dataset_record.dart';

/// Validation report for dataset integrity verification.
class DatasetValidationReport {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final int recordCount;

  const DatasetValidationReport({
    required this.isValid,
    required this.errors,
    required this.warnings,
    required this.recordCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'isValid': isValid,
      'errors': errors,
      'warnings': warnings,
      'recordCount': recordCount,
    };
  }
}

/// Validates telemetry records against FeatureSchema and DatasetSchema.
class DatasetValidator {
  final FeatureSchema featureSchema;
  final DatasetSchema datasetSchema;

  DatasetValidator({
    FeatureSchema? featureSchema,
    DatasetSchema? datasetSchema,
  })  : featureSchema = featureSchema ?? FeatureSchema.v1,
        datasetSchema = datasetSchema ?? const DatasetSchema();

  /// Validates a single DatasetRecord
  List<String> validateRecord(DatasetRecord record) {
    final errors = <String>[];

    if (record.recordId.trim().isEmpty) {
      errors.add('recordId cannot be empty');
    }
    if (record.deviceIdHash.trim().isEmpty) {
      errors.add('deviceIdHash cannot be empty');
    }
    if (record.androidVersion.trim().isEmpty) {
      errors.add('androidVersion cannot be empty');
    }
    if (record.timestamp.trim().isEmpty || DateTime.tryParse(record.timestamp) == null) {
      errors.add('Invalid or unparseable timestamp: "${record.timestamp}"');
    }
    if (record.packageName.trim().isEmpty) {
      errors.add('packageName cannot be empty');
    }
    if (record.collectorHealthStatus.trim().isEmpty) {
      errors.add('collectorHealthStatus cannot be empty');
    }
    if (record.sdkInt <= 0) {
      errors.add('Invalid sdkInt: ${record.sdkInt}');
    }

    final vec = record.featureVector;
    if (vec.schemaVersion != featureSchema.schemaVersion) {
      errors.add('Feature vector schema version "${vec.schemaVersion}" does not match expected "${featureSchema.schemaVersion}"');
    }

    if (vec.length != featureSchema.featureCount) {
      errors.add('Feature vector length ${vec.length} does not match expected ${featureSchema.featureCount}');
    }

    final seenNames = <String>{};
    for (int i = 0; i < featureSchema.featureCount; i++) {
      final def = featureSchema.getFeatureByIndex(i);
      final val = vec.getValueByIndex(i);

      if (val.featureIndex != i) {
        errors.add('Feature index mismatch at position $i: expected $i, found ${val.featureIndex}');
      }
      if (val.featureName != def.name) {
        errors.add('Feature ordering error at index $i: expected "${def.name}", found "${val.featureName}"');
      }
      if (seenNames.contains(val.featureName)) {
        errors.add('Duplicate feature name in record: "${val.featureName}"');
      }
      seenNames.add(val.featureName);

      if (val.isPresent) {
        if (val.numericValue == null) {
          errors.add('Feature "${def.name}" marked present but has null numericValue');
        } else {
          final numVal = val.numericValue!;
          if (numVal.isNaN) {
            errors.add('Feature "${def.name}" has invalid NaN numericValue');
          } else if (numVal.isInfinite) {
            errors.add('Feature "${def.name}" has infinite numericValue');
          } else {
            if (def.minExpected != null && numVal < def.minExpected!) {
              errors.add('Feature "${def.name}" value $numVal is below expected min ${def.minExpected}');
            }
            if (def.maxExpected != null && numVal > def.maxExpected!) {
              errors.add('Feature "${def.name}" value $numVal is above expected max ${def.maxExpected}');
            }
          }
        }
      }
    }

    final mask = vec.toMissingMask();
    if (mask.length != featureSchema.featureCount) {
      errors.add('Missingness mask length ${mask.length} does not match ${featureSchema.featureCount}');
    }
    for (int i = 0; i < mask.length; i++) {
      if (mask[i] != 0.0 && mask[i] != 1.0) {
        errors.add('Invalid missingness indicator at index $i: ${mask[i]} (must be 0.0 or 1.0)');
      }
    }

    return errors;
  }

  /// Validates a collection of DatasetRecords
  DatasetValidationReport validateDataset(List<DatasetRecord> records) {
    final allErrors = <String>[];
    final allWarnings = <String>[];

    if (records.isEmpty) {
      allWarnings.add('Dataset contains 0 records.');
    }

    for (int i = 0; i < records.length; i++) {
      final recordErrors = validateRecord(records[i]);
      for (final err in recordErrors) {
        allErrors.add('Record #$i (${records[i].packageName}): $err');
      }
    }

    return DatasetValidationReport(
      isValid: allErrors.isEmpty,
      errors: allErrors,
      warnings: allWarnings,
      recordCount: records.length,
    );
  }
}
