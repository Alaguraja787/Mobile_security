import '../../models/app_telemetry.dart';
import '../../models/privacy_event.dart';
import '../interfaces/phase2_intelligence_provider.dart';

/// MOCK / DEVELOPMENT ONLY implementation of Phase 2 Intelligence Provider.
///
/// MUST NOT be presented as real ML detection.
class MockPhase2Provider implements Phase2IntelligenceProvider {
  final double? mockAnomalyScore;
  final bool mockBaselineEstablished;

  MockPhase2Provider({
    this.mockAnomalyScore,
    this.mockBaselineEstablished = false,
  });

  @override
  Future<Phase2IntelligenceSnapshot> getIntelligence({
    AppTelemetry? app,
    required PrivacyEvent event,
  }) async {
    return Phase2IntelligenceSnapshot(
      anomalyScore: mockAnomalyScore,
      isBaselineEstablished: mockBaselineEstablished,
      modelStatus: "MOCK_STUB_ONLY",
      isMock: true,
      disclaimer: "MOCK / DEVELOPMENT ONLY: Phase 2 local ML is frozen.",
      featureImportance: {
        'mock_signal': 0.0,
      },
    );
  }
}
