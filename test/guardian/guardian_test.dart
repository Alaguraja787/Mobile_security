@Timeout(Duration(seconds: 90))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/guardian/decision/guardian_engine.dart';
import 'package:mobile_privacy_security_project/guardian/mocks/mock_phase2_provider.dart';
import 'package:mobile_privacy_security_project/guardian/models/guardian_decision.dart';
import 'package:mobile_privacy_security_project/guardian/models/guardian_input.dart';
import 'package:mobile_privacy_security_project/guardian/models/severity_confidence.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';

void main() {
  group('Phase 3 — Guardian Intelligence Test Suite', () {
    late GuardianEngine guardianEngine;
    late PrivacyEvent validEvent;
    late AppTelemetry sampleApp;

    setUp(() {
      guardianEngine = GuardianEngine();
      sampleApp = AppTelemetry(
        packageName: 'com.example.testapp',
        appName: 'Test App',
        permissions: ['CAMERA', 'ACCESS_FINE_LOCATION'],
        hasOverlayOp: true,
        uploadBytes: 10 * 1024 * 1024,
      );

      validEvent = PrivacyEvent(
        timestamp: DateTime.now().toIso8601String(),
        deviceContext: DeviceContext(
          screenOn: false,
          screenLocked: true,
        ),
        securityContext: SecurityContext(
          accessibilityEnabled: true,
          selfIsIgnoringBatteryOptimizations: true,
        ),
        network: NetworkTelemetry(
          trafficStatsAvailability: 'VALID',
          deviceTotalTxBytes: 10000000,
          deviceTotalRxBytes: 500000,
        ),
        sensorTelemetry: SensorPrivacyTelemetry(
          sensorAvailability: 'VALID',
          cameraUnavailable: true,
          microphoneHardwareInUse: false,
        ),
        usageSummary: UsageSummary(),
        apps: [sampleApp.toJson()],
      );
    });

    test('1 & 12. Guardian input validation and Phase-2 contract', () async {
      final mockProvider = MockPhase2Provider(mockAnomalyScore: 0.15);
      final intel = await mockProvider.getIntelligence(app: sampleApp, event: validEvent);

      expect(intel.isMock, isTrue);
      expect(intel.disclaimer, contains('MOCK / DEVELOPMENT ONLY'));

      final input = GuardianInput(
        recordId: 'rec_101',
        sessionId: 'sess_202',
        targetApp: sampleApp,
        event: validEvent,
        intelligenceSnapshot: intel,
      );

      expect(input.recordId, equals('rec_101'));
      expect(input.targetApp?.packageName, equals('com.example.testapp'));
    });

    test('2 & 8. Evidence-based reasoning without hardcoded app bias', () async {
      final decision = await guardianEngine.evaluate(app: sampleApp, event: validEvent);

      expect(decision.observedEvidence, isNotEmpty);
      expect(decision.inferences, isNotEmpty);
      expect(decision.summary, isNotEmpty);
      expect(decision.userFacingExplanation, contains('Test App'));
    });

    test('3. Handling of UNAVAILABLE telemetry', () async {
      final unavailableEvent = PrivacyEvent(
        timestamp: DateTime.now().toIso8601String(),
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(trafficStatsAvailability: 'UNAVAILABLE'),
        sensorTelemetry: SensorPrivacyTelemetry(sensorAvailability: 'UNAVAILABLE'),
        usageSummary: UsageSummary(),
        apps: [sampleApp.toJson()],
      );

      final decision = await guardianEngine.evaluate(app: sampleApp, event: unavailableEvent);

      final hasUncertainty = decision.uncertainties.any((u) => u.affectedSignal == 'networkUsage');
      expect(hasUncertainty, isTrue);
      expect(decision.confidence.score, lessThan(1.0));
    });

    test('4. Handling of RESTRICTED telemetry', () async {
      final restrictedEvent = PrivacyEvent(
        timestamp: DateTime.now().toIso8601String(),
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(trafficStatsAvailability: 'RESTRICTED'),
        sensorTelemetry: SensorPrivacyTelemetry(sensorAvailability: 'VALID'),
        usageSummary: UsageSummary(),
        apps: [sampleApp.toJson()],
      );

      final decision = await guardianEngine.evaluate(app: sampleApp, event: restrictedEvent);

      final hasUncertainty = decision.uncertainties.any((u) => u.affectedSignal == 'networkUsage');
      expect(hasUncertainty, isTrue);
    });

    test('5. Handling of DENIED telemetry', () async {
      final deniedEvent = PrivacyEvent(
        timestamp: DateTime.now().toIso8601String(),
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(trafficStatsAvailability: 'DENIED'),
        sensorTelemetry: SensorPrivacyTelemetry(sensorAvailability: 'DENIED'),
        usageSummary: UsageSummary(),
        apps: [sampleApp.toJson()],
      );

      final decision = await guardianEngine.evaluate(app: sampleApp, event: deniedEvent);

      expect(decision.uncertainties.length, greaterThanOrEqualTo(2));
      expect(decision.confidence.score, lessThanOrEqualTo(0.8));
    });

    test('6. Handling of ERROR telemetry', () async {
      final errorEvent = PrivacyEvent(
        timestamp: DateTime.now().toIso8601String(),
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(trafficStatsAvailability: 'ERROR'),
        sensorTelemetry: SensorPrivacyTelemetry(sensorAvailability: 'ERROR'),
        usageSummary: UsageSummary(),
        apps: [sampleApp.toJson()],
      );

      final decision = await guardianEngine.evaluate(app: sampleApp, event: errorEvent);

      expect(decision.confidence.justification.contains('Low confidence') ||
          decision.confidence.justification.contains('Moderate confidence'), isTrue);
    });

    test('7. Low-confidence decision separation from severity', () async {
      final lowConfEvent = PrivacyEvent(
        timestamp: DateTime.now().toIso8601String(),
        deviceContext: DeviceContext(screenLocked: true),
        securityContext: SecurityContext(accessibilityEnabled: true),
        network: NetworkTelemetry(trafficStatsAvailability: 'UNAVAILABLE'),
        sensorTelemetry: SensorPrivacyTelemetry(sensorAvailability: 'UNAVAILABLE'),
        usageSummary: UsageSummary(),
        apps: [sampleApp.toJson()],
      );

      final decision = await guardianEngine.evaluate(app: sampleApp, event: lowConfEvent);

      expect(decision.severity, equals(GuardianSeverity.HIGH));
      expect(decision.confidence.score, lessThan(0.8));
    });

    test('9. Recommendation generation', () async {
      final decision = await guardianEngine.evaluate(app: sampleApp, event: validEvent);

      expect(decision.recommendations, isNotEmpty);
      final recTitles = decision.recommendations.map((r) => r.title).toList();
      expect(recTitles.any((t) => t.contains('Background Data') || t.contains('Display Over Other Apps') || t.contains('Accessibility')), isTrue);
    });

    test('10. Guardian decision serialization & deserialization', () async {
      final decision = await guardianEngine.evaluate(app: sampleApp, event: validEvent);
      final json = decision.toJson();

      final reconstructed = GuardianDecision.fromJson(json);

      expect(reconstructed.decisionId, equals(decision.decisionId));
      expect(reconstructed.severity, equals(decision.severity));
      expect(reconstructed.summary, equals(decision.summary));
      expect(reconstructed.observedEvidence.length, equals(decision.observedEvidence.length));
    });

    test('11. Mock Phase-2 provider disclaimer verification', () async {
      final mockProvider = MockPhase2Provider();
      final intel = await mockProvider.getIntelligence(event: validEvent);

      expect(intel.isMock, isTrue);
      expect(intel.disclaimer, contains('MOCK / DEVELOPMENT ONLY'));
    });

    test('13. Phase-4 contract & non-destructive action request', () async {
      final decision = await guardianEngine.evaluate(app: sampleApp, event: validEvent);

      expect(decision.requiresUserAttention, isTrue);
      expect(decision.phase4ActionRequest, isNotNull);
      expect(decision.phase4ActionRequest?.requiresUserApproval, isTrue);
      expect(decision.phase4ActionRequest?.targetPackageName, equals('com.example.testapp'));
    });
  });
}
