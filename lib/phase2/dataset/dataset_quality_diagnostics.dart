import 'dataset_record.dart';

/// Comprehensive collection quality metrics for Phase 1 telemetry datasets.
class DatasetQualityDiagnostics {
  final int totalPersistedRecords;
  final int uniquePackages;
  final int uniqueSessions;
  final String collectionStart;
  final String collectionEnd;
  final int actualObservedDurationSeconds;
  final double samplingIntervalSeconds;
  final int duplicateCount;
  final int validationRejectionCount;
  final int persistenceFailureCount;
  final int storageSizeBytes;

  // Availability breakdown across telemetry signals
  final int validCount;
  final int zeroReportedCount;
  final int deniedCount;
  final int restrictedCount;
  final int unavailableCount;
  final int errorCount;
  final int unknownCount;

  // Missingness statistics
  final int missingFeatureCount;
  final Map<String, double> perFeatureMissingnessPercentage;

  const DatasetQualityDiagnostics({
    required this.totalPersistedRecords,
    required this.uniquePackages,
    required this.uniqueSessions,
    required this.collectionStart,
    required this.collectionEnd,
    required this.actualObservedDurationSeconds,
    required this.samplingIntervalSeconds,
    required this.duplicateCount,
    required this.validationRejectionCount,
    required this.persistenceFailureCount,
    required this.storageSizeBytes,
    required this.validCount,
    required this.zeroReportedCount,
    required this.deniedCount,
    required this.restrictedCount,
    required this.unavailableCount,
    required this.errorCount,
    required this.unknownCount,
    required this.missingFeatureCount,
    required this.perFeatureMissingnessPercentage,
  });

  /// Computes a DatasetQualityDiagnostics report from a list of persisted DatasetRecords
  factory DatasetQualityDiagnostics.fromRecords(
    List<DatasetRecord> records, {
    int storageSize = 0,
    int duplicates = 0,
    int validationRejections = 0,
    int persistenceFailures = 0,
  }) {
    if (records.isEmpty) {
      return DatasetQualityDiagnostics(
        totalPersistedRecords: 0,
        uniquePackages: 0,
        uniqueSessions: 0,
        collectionStart: 'N/A',
        collectionEnd: 'N/A',
        actualObservedDurationSeconds: 0,
        samplingIntervalSeconds: 0.0,
        duplicateCount: duplicates,
        validationRejectionCount: validationRejections,
        persistenceFailureCount: persistenceFailures,
        storageSizeBytes: storageSize,
        validCount: 0,
        zeroReportedCount: 0,
        deniedCount: 0,
        restrictedCount: 0,
        unavailableCount: 0,
        errorCount: 0,
        unknownCount: 0,
        missingFeatureCount: 0,
        perFeatureMissingnessPercentage: {},
      );
    }

    final packages = records.map((r) => r.packageName).toSet();
    final sessions = records.map((r) => r.sessionId ?? 'none').toSet();

    final sortedTimestamps = records
        .map((r) => r.timestamp)
        .where((ts) => ts.isNotEmpty)
        .toList()
      ..sort();

    final collectionStart = sortedTimestamps.isNotEmpty ? sortedTimestamps.first : 'N/A';
    final collectionEnd = sortedTimestamps.isNotEmpty ? sortedTimestamps.last : 'N/A';

    int durationSec = 0;
    if (sortedTimestamps.isNotEmpty) {
      final startDt = DateTime.tryParse(sortedTimestamps.first);
      final endDt = DateTime.tryParse(sortedTimestamps.last);
      if (startDt != null && endDt != null) {
        durationSec = endDt.difference(startDt).inSeconds.abs();
      }
    }

    final intervalSec = records.length > 1 && durationSec > 0
        ? (durationSec / (records.length - 1))
        : 0.0;

    int valid = 0;
    int zeroReported = 0;
    int denied = 0;
    int restricted = 0;
    int unavailable = 0;
    int error = 0;
    int unknown = 0;

    int missingFeaturesTotal = 0;
    final featureMissingCounts = <String, int>{};

    for (final record in records) {
      final health = record.collectorHealthStatus.toUpperCase();
      switch (health) {
        case 'VALID':
          valid++;
          break;
        case 'ZERO_REPORTED':
          zeroReported++;
          break;
        case 'DENIED':
          denied++;
          break;
        case 'RESTRICTED':
          restricted++;
          break;
        case 'UNAVAILABLE':
          unavailable++;
          break;
        case 'ERROR':
          error++;
          break;
        default:
          unknown++;
          break;
      }

      // Calculate feature missingness
      for (final val in record.featureVector.values) {
        if (val.isMissing) {
          missingFeaturesTotal++;
          featureMissingCounts[val.featureName] =
              (featureMissingCounts[val.featureName] ?? 0) + 1;
        }
      }
    }

    final perFeatureMissingness = <String, double>{};
    for (final entry in featureMissingCounts.entries) {
      perFeatureMissingness[entry.key] =
          (entry.value / records.length) * 100.0;
    }

    return DatasetQualityDiagnostics(
      totalPersistedRecords: records.length,
      uniquePackages: packages.length,
      uniqueSessions: sessions.length,
      collectionStart: collectionStart,
      collectionEnd: collectionEnd,
      actualObservedDurationSeconds: durationSec,
      samplingIntervalSeconds: double.parse(intervalSec.toStringAsFixed(2)),
      duplicateCount: duplicates,
      validationRejectionCount: validationRejections,
      persistenceFailureCount: persistenceFailures,
      storageSizeBytes: storageSize,
      validCount: valid,
      zeroReportedCount: zeroReported,
      deniedCount: denied,
      restrictedCount: restricted,
      unavailableCount: unavailable,
      errorCount: error,
      unknownCount: unknown,
      missingFeatureCount: missingFeaturesTotal,
      perFeatureMissingnessPercentage: perFeatureMissingness,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalPersistedRecords': totalPersistedRecords,
      'uniquePackages': uniquePackages,
      'uniqueSessions': uniqueSessions,
      'collectionStart': collectionStart,
      'collectionEnd': collectionEnd,
      'actualObservedDurationSeconds': actualObservedDurationSeconds,
      'samplingIntervalSeconds': samplingIntervalSeconds,
      'duplicateCount': duplicateCount,
      'validationRejectionCount': validationRejectionCount,
      'persistenceFailureCount': persistenceFailureCount,
      'storageSizeBytes': storageSizeBytes,
      'availabilityBreakdown': {
        'VALID': validCount,
        'ZERO_REPORTED': zeroReportedCount,
        'DENIED': deniedCount,
        'RESTRICTED': restrictedCount,
        'UNAVAILABLE': unavailableCount,
        'ERROR': errorCount,
        'UNKNOWN': unknownCount,
      },
      'missingFeatureCount': missingFeatureCount,
      'perFeatureMissingnessPercentage': perFeatureMissingnessPercentage,
    };
  }
}
