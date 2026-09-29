import '../../models/app_telemetry.dart';
import '../../models/privacy_event.dart';

/// Structured snapshot of Phase 2 Local Intelligence fed into Guardian.
class Phase2IntelligenceSnapshot {
  final double? anomalyScore; // null if baseline/model unavailable
  final bool isBaselineEstablished;
  final String modelStatus;
  final bool isMock;
  final String disclaimer;
  final Map<String, dynamic> featureImportance;

  Phase2IntelligenceSnapshot({
    this.anomalyScore,
    this.isBaselineEstablished = false,
    this.modelStatus = "DEFERRED",
    this.isMock = true,
    this.disclaimer = "MOCK / DEVELOPMENT ONLY: Phase 2 local ML is frozen.",
    this.featureImportance = const {},
  });

  Map<String, dynamic> toJson() => {
        'anomalyScore': anomalyScore,
        'isBaselineEstablished': isBaselineEstablished,
        'modelStatus': modelStatus,
        'isMock': isMock,
        'disclaimer': disclaimer,
        'featureImportance': featureImportance,
      };

  factory Phase2IntelligenceSnapshot.fromJson(Map<String, dynamic> json) =>
      Phase2IntelligenceSnapshot(
        anomalyScore: (json['anomalyScore'] as num?)?.toDouble(),
        isBaselineEstablished: json['isBaselineEstablished'] == true,
        modelStatus: json['modelStatus']?.toString() ?? 'DEFERRED',
        isMock: json['isMock'] ?? true,
        disclaimer: json['disclaimer']?.toString() ??
            'MOCK / DEVELOPMENT ONLY: Phase 2 local ML is frozen.',
        featureImportance:
            (json['featureImportance'] as Map<String, dynamic>?) ?? {},
      );
}

/// Abstract contract allowing Phase 2 Local Intelligence to plug into Guardian.
abstract class Phase2IntelligenceProvider {
  Future<Phase2IntelligenceSnapshot> getIntelligence({
    AppTelemetry? app,
    required PrivacyEvent event,
  });
}
