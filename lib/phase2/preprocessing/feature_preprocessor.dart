import 'dart:math' as math;
import 'dart:typed_data';

import '../feature_engineering/feature_vector.dart';
import '../schemas/feature_definition.dart';
import '../schemas/feature_schema.dart';
import 'normalization_parameters.dart';
import 'preprocessed_tensor.dart';
import 'preprocessor_status.dart';

/// Preprocessor result encapsulating status, tensor, and diagnostic messages.
class PreprocessorResult {
  final PreprocessorStatus status;
  final PreprocessedTensor? tensor;
  final String message;

  const PreprocessorResult({
    required this.status,
    this.tensor,
    required this.message,
  });

  factory PreprocessorResult.notReady([String? message]) {
    return PreprocessorResult(
      status: PreprocessorStatus.notReady,
      tensor: null,
      message: message ?? 'PREPROCESSOR_NOT_READY: Scaler parameters not yet calibrated from real Android telemetry.',
    );
  }

  factory PreprocessorResult.ready(PreprocessedTensor tensor) {
    return PreprocessorResult(
      status: PreprocessorStatus.ready,
      tensor: tensor,
      message: 'PREPROCESSOR_READY: Tensor preprocessed successfully.',
    );
  }

  factory PreprocessorResult.error(String errorMessage) {
    return PreprocessorResult(
      status: PreprocessorStatus.error,
      tensor: null,
      message: 'PREPROCESSOR_ERROR: $errorMessage',
    );
  }

  bool get isReady => status == PreprocessorStatus.ready;
}

/// Preprocessor executing schema validation and feature normalization.
/// 
/// Strictly reports PREPROCESSOR_NOT_READY until real calibration parameters are loaded.
/// NEVER uses random or mock scaling parameters.
class FeaturePreprocessor {
  final FeatureSchema schema;
  final NormalizationParameters normalizationParameters;

  FeaturePreprocessor({
    FeatureSchema? schema,
    NormalizationParameters? normalizationParameters,
  })  : schema = schema ?? FeatureSchema.v1,
        normalizationParameters = normalizationParameters ?? NormalizationParameters.unfitted();

  PreprocessorStatus get status {
    if (normalizationParameters.schemaVersion != schema.schemaVersion) {
      return PreprocessorStatus.error;
    }
    if (normalizationParameters.isReadyFor(schema)) {
      return PreprocessorStatus.ready;
    }
    return PreprocessorStatus.notReady;
  }

  PreprocessorResult process(FeatureVector vector) {
    // 1. NormalizationParameters schema version check
    if (normalizationParameters.schemaVersion != schema.schemaVersion) {
      return PreprocessorResult.error(
        'Schema version mismatch: Normalization parameters schema "${normalizationParameters.schemaVersion}" does not match preprocessor schema "${schema.schemaVersion}"',
      );
    }

    // 2. Vector schema version check
    if (vector.schemaVersion != schema.schemaVersion) {
      return PreprocessorResult.error(
        'Schema version mismatch: Vector schema "${vector.schemaVersion}" does not match preprocessor schema "${schema.schemaVersion}"',
      );
    }

    // 3. Feature count check
    if (vector.length != schema.featureCount) {
      return PreprocessorResult.error(
        'Feature count mismatch: Vector has ${vector.length} features, expected ${schema.featureCount}',
      );
    }

    // 4. Calibration readiness check
    final validationErrors = normalizationParameters.getValidationErrors(schema);
    if (validationErrors.isNotEmpty) {
      return PreprocessorResult.notReady(
        'PREPROCESSOR_NOT_READY: Preprocessor parameters not calibrated for schema ${schema.schemaVersion}: ${validationErrors.join("; ")}',
      );
    }

    try {
      // 64-element model input: 32 semantic features + 32 missingness indicators
      final totalElements = schema.featureCount * 2;
      final buffer = Float32List(totalElements);

      for (int i = 0; i < schema.featureCount; i++) {
        final def = schema.getFeatureByIndex(i);
        final val = vector.getValueByIndex(i);

        double normalizedVal;

        if (val.isMissing) {
          // Impute using strictly fitted real-data parameter
          normalizedVal = normalizationParameters.imputationValues[def.name]!;
        } else {
          final rawNum = val.numericValue ?? 0.0;

          switch (def.normalizationType) {
            case NormalizationType.none:
              normalizedVal = rawNum;
              break;

            case NormalizationType.standard:
              final mean = normalizationParameters.means[def.name]!;
              final std = normalizationParameters.stds[def.name]!;
              normalizedVal = (rawNum - mean) / std;
              break;

            case NormalizationType.minMax:
              final min = normalizationParameters.mins[def.name]!;
              final max = normalizationParameters.maxs[def.name]!;
              final range = max - min;
              normalizedVal = (rawNum - min) / range;
              break;

            case NormalizationType.robust:
              final median = normalizationParameters.medians[def.name]!;
              final iqr = normalizationParameters.iqrs[def.name]!;
              normalizedVal = (rawNum - median) / iqr;
              break;

            case NormalizationType.logScale:
              normalizedVal = math.log(rawNum >= 0 ? rawNum + 1.0 : 1.0);
              break;
          }
        }

        buffer[i] = normalizedVal;
        // Missingness mask at offset 32: 0.0 = present, 1.0 = missing
        buffer[schema.featureCount + i] = val.isMissing ? 1.0 : 0.0;
      }

      final tensor = PreprocessedTensor(
        data: buffer,
        shape: [1, totalElements],
        schemaVersion: schema.schemaVersion,
      );

      return PreprocessorResult.ready(tensor);
    } catch (e) {
      return PreprocessorResult.error(e.toString());
    }
  }
}
