import '../schemas/feature_definition.dart';
import 'feature_value.dart';

/// Explicit strategy handler for missing telemetry.
/// 
/// Guarantees that unavailable, denied, restricted, error, and unknown statuses
/// are never conflated with genuine zero traffic, false permissions, or safe indicators.
abstract class MissingDataStrategy {
  /// Resolves the numeric value or throws/flags if preservation requires distinct handling
  double? resolveNumeric(FeatureValue value, FeatureDefinition definition);

  /// Generates a binary missing indicator mask (0.0 = present, 1.0 = missing)
  double getMissingIndicator(FeatureValue value) {
    return value.isMissing ? 1.0 : 0.0;
  }
}

/// Default Phase 2 strategy: preserves nulls cleanly for uncalibrated pipelines,
/// and produces explicit presence masks so future ML models can learn from missingness.
class StandardMissingDataStrategy implements MissingDataStrategy {
  const StandardMissingDataStrategy();

  @override
  double? resolveNumeric(FeatureValue value, FeatureDefinition definition) {
    if (value.status == FeatureAvailabilityStatus.valid ||
        value.status == FeatureAvailabilityStatus.zeroReported) {
      return value.numericValue;
    }
    // Preserves null when missing (RESTRICTED, DENIED, UNAVAILABLE, ERROR, UNKNOWN)
    return null;
  }

  @override
  double getMissingIndicator(FeatureValue value) {
    return value.isMissing ? 1.0 : 0.0;
  }
}
