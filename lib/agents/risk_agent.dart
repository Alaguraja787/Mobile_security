import '../guardian/decision/guardian_engine.dart';
import '../guardian/models/severity_confidence.dart';
import '../models/app_telemetry.dart';
import '../models/privacy_event.dart';
import '../models/risk_assessment.dart';

/// Legacy adapter for RiskAgent delegating to Phase 3 Guardian Intelligence.
class RiskAgent {
  final GuardianEngine guardianEngine;

  RiskAgent({GuardianEngine? guardianEngine})
      : guardianEngine = guardianEngine ?? GuardianEngine();

  Future<RiskAssessment> analyze(AppTelemetry app, [PrivacyEvent? event]) async {
    final defaultEvent = event ??
        PrivacyEvent(
          timestamp: DateTime.now().toIso8601String(),
          deviceContext: DeviceContext(),
          securityContext: SecurityContext(),
          network: NetworkTelemetry(),
          sensorTelemetry: SensorPrivacyTelemetry(),
          usageSummary: UsageSummary(),
          apps: [app.toJson()],
        );

    final decision = await guardianEngine.evaluate(app: app, event: defaultEvent);

    int score;
    switch (decision.severity) {
      case GuardianSeverity.CRITICAL:
        score = 95;
        break;
      case GuardianSeverity.HIGH:
        score = 80;
        break;
      case GuardianSeverity.MEDIUM:
        score = 50;
        break;
      case GuardianSeverity.LOW:
        score = 20;
        break;
    }

    return RiskAssessment(
      score: score,
      level: decision.severity.name,
      reason: decision.summary,
    );
  }
}