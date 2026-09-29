import '../schemas/feature_definition.dart';
import '../schemas/feature_schema.dart';

/// Parameters for feature normalization fitted strictly on real training datasets.
/// 
/// In Phase 2 before real telemetry collection, this remains unfitted.
class NormalizationParameters {
  final String schemaVersion;
  final bool isFitted;
  final Map<String, double> means;
  final Map<String, double> stds;
  final Map<String, double> mins;
  final Map<String, double> maxs;
  final Map<String, double> medians;
  final Map<String, double> iqrs;
  final Map<String, double> imputationValues;

  const NormalizationParameters({
    required this.schemaVersion,
    required this.isFitted,
    this.means = const {},
    this.stds = const {},
    this.mins = const {},
    this.maxs = const {},
    this.medians = const {},
    this.iqrs = const {},
    this.imputationValues = const {},
  });

  /// Factory representing the initial unfitted state (NO fake scaler parameters)
  factory NormalizationParameters.unfitted({String schemaVersion = '1.0.0'}) {
    return NormalizationParameters(
      schemaVersion: schemaVersion,
      isFitted: false,
    );
  }

  /// Validates whether the parameters meet all readiness rules against the schema.
  List<String> getValidationErrors(FeatureSchema schema) {
    final errors = <String>[];

    if (!isFitted) {
      errors.add('Parameters are marked unfitted (isFitted=false).');
      return errors;
    }

    if (schemaVersion != schema.schemaVersion) {
      errors.add('Schema version mismatch: parameters version $schemaVersion != schema version ${schema.schemaVersion}');
    }

    for (final def in schema.features) {
      final name = def.name;

      // Check imputation parameter
      final imp = imputationValues[name];
      if (imp == null) {
        errors.add('Missing imputation parameter for feature "$name"');
      } else if (!imp.isFinite) {
        errors.add('Non-finite imputation parameter for feature "$name": $imp');
      }

      // Check normalization-specific parameters
      switch (def.normalizationType) {
        case NormalizationType.standard:
          final mean = means[name];
          final std = stds[name];
          if (mean == null || !mean.isFinite) {
            errors.add('Missing or non-finite mean for standard normalized feature "$name"');
          }
          if (std == null || !std.isFinite || std <= 0.0) {
            errors.add('Invalid, missing, non-positive, or non-finite std for feature "$name": $std');
          }
          break;

        case NormalizationType.minMax:
          final min = mins[name];
          final max = maxs[name];
          if (min == null || !min.isFinite) {
            errors.add('Missing or non-finite min for minMax normalized feature "$name"');
          }
          if (max == null || !max.isFinite) {
            errors.add('Missing or non-finite max for minMax normalized feature "$name"');
          }
          if (min != null && max != null && min.isFinite && max.isFinite && max <= min) {
            errors.add('Invalid min/max range for feature "$name": max ($max) <= min ($min)');
          }
          break;

        case NormalizationType.robust:
          final med = medians[name];
          final iqr = iqrs[name];
          if (med == null || !med.isFinite) {
            errors.add('Missing or non-finite median for robust normalized feature "$name"');
          }
          if (iqr == null || !iqr.isFinite || iqr <= 0.0) {
            errors.add('Invalid, missing, non-positive, or non-finite IQR for feature "$name": $iqr');
          }
          break;

        case NormalizationType.logScale:
        case NormalizationType.none:
          break;
      }
    }

    return errors;
  }

  bool isReadyFor(FeatureSchema schema) => getValidationErrors(schema).isEmpty;

  factory NormalizationParameters.fromJson(Map<String, dynamic> json) {
    Map<String, double> parseDoubleMap(dynamic raw) {
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
      }
      return const {};
    }

    return NormalizationParameters(
      schemaVersion: json['schemaVersion']?.toString() ?? '1.0.0',
      isFitted: json['isFitted'] == true,
      means: parseDoubleMap(json['means']),
      stds: parseDoubleMap(json['stds']),
      mins: parseDoubleMap(json['mins']),
      maxs: parseDoubleMap(json['maxs']),
      medians: parseDoubleMap(json['medians']),
      iqrs: parseDoubleMap(json['iqrs']),
      imputationValues: parseDoubleMap(json['imputationValues']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'isFitted': isFitted,
      'means': means,
      'stds': stds,
      'mins': mins,
      'maxs': maxs,
      'medians': medians,
      'iqrs': iqrs,
      'imputationValues': imputationValues,
    };
  }
}
