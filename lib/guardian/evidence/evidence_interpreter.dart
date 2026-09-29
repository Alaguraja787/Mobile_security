import '../models/evidence.dart';
import '../models/guardian_input.dart';

class InterpretationResult {
  final List<ObservedFact> facts;
  final List<Uncertainty> uncertainties;

  InterpretationResult({
    required this.facts,
    required this.uncertainties,
  });
}

/// Converts raw PrivacyEvent & AppTelemetry into structured facts and availability-aware uncertainties.
class EvidenceInterpreter {
  InterpretationResult interpret(GuardianInput input) {
    final List<ObservedFact> facts = [];
    final List<Uncertainty> uncertainties = [];

    final event = input.event;
    final app = input.targetApp;

    // 1. Device Screen Context
    if (event.deviceContext.screenLocked != null) {
      facts.add(ObservedFact(
        id: 'fact_screen_locked',
        category: 'DEVICE',
        description: event.deviceContext.screenLocked == true
            ? 'Screen is locked'
            : 'Screen is unlocked',
        availabilityState: 'VALID',
        rawValue: event.deviceContext.screenLocked,
      ));
    } else {
      uncertainties.add(Uncertainty(
        affectedSignal: 'screenLocked',
        reason: 'Screen locked status is null or unavailable from system context.',
        impactOnDecision: 'Cannot definitively determine if user was actively interacting.',
      ));
    }

    // 2. Network Telemetry & Heavy Background Data
    final networkAvailability = event.network.trafficStatsAvailability;
    if (networkAvailability != 'VALID') {
      uncertainties.add(Uncertainty(
        affectedSignal: 'networkUsage',
        reason: 'Network stats availability state is $networkAvailability.',
        impactOnDecision: 'Background network transfer volume may be incomplete or zero-reported.',
      ));
    } else {
      final upload = app?.uploadBytes ?? event.network.deviceTotalTxBytes ?? 0;
      final download = app?.downloadBytes ?? event.network.deviceTotalRxBytes ?? 0;

      if (upload > 5 * 1024 * 1024) {
        facts.add(ObservedFact(
          id: 'fact_heavy_upload',
          category: 'NETWORK',
          description: 'High outbound data transfer observed ($upload bytes uploaded)',
          availabilityState: networkAvailability,
          rawValue: upload,
        ));
      }

      if (download > 10 * 1024 * 1024) {
        facts.add(ObservedFact(
          id: 'fact_heavy_download',
          category: 'NETWORK',
          description: 'High inbound data transfer observed ($download bytes downloaded)',
          availabilityState: networkAvailability,
          rawValue: download,
        ));
      }
    }

    // 3. Security & Permission Context
    if (event.securityContext.accessibilityEnabled == true) {
      facts.add(ObservedFact(
        id: 'fact_accessibility_enabled',
        category: 'PERMISSION',
        description: 'System accessibility service is enabled',
        availabilityState: 'VALID',
        rawValue: true,
      ));
    }

    if (event.securityContext.selfIsIgnoringBatteryOptimizations == true) {
      facts.add(ObservedFact(
        id: 'fact_battery_opt_ignored',
        category: 'DEVICE',
        description: 'Battery optimization is disabled for application',
        availabilityState: 'VALID',
        rawValue: true,
      ));
    }

    if (app != null && app.hasOverlayOp) {
      facts.add(ObservedFact(
        id: 'fact_overlay_permission',
        category: 'PERMISSION',
        description: 'System alert / overlay permission is granted',
        availabilityState: 'VALID',
        rawValue: true,
      ));
    }

    // 4. Sensor Availability Context
    final sensorAvailability = event.sensorTelemetry.sensorAvailability;
    if (sensorAvailability != 'VALID') {
      uncertainties.add(Uncertainty(
        affectedSignal: 'sensorTelemetry',
        reason: 'Sensor telemetry availability state is $sensorAvailability.',
        impactOnDecision: 'Hardware camera/microphone state cannot be verified dynamically.',
      ));
    } else {
      if (event.sensorTelemetry.cameraUnavailable == true) {
        facts.add(ObservedFact(
          id: 'fact_camera_in_use',
          category: 'SENSOR',
          description: 'Camera hardware is active / occupied',
          availabilityState: sensorAvailability,
          rawValue: true,
        ));
      }

      if (event.sensorTelemetry.microphoneHardwareInUse == true) {
        facts.add(ObservedFact(
          id: 'fact_mic_in_use',
          category: 'SENSOR',
          description: 'Microphone hardware is actively recording audio',
          availabilityState: sensorAvailability,
          rawValue: true,
        ));
      }
    }

    // 5. Phase 2 Intelligence Snapshot Boundary Assessment
    if (input.intelligenceSnapshot.isMock) {
      uncertainties.add(Uncertainty(
        affectedSignal: 'behaviorBaseline',
        reason: input.intelligenceSnapshot.disclaimer,
        impactOnDecision: 'No learned behavioral baseline or ML anomaly score is active.',
      ));
    }

    return InterpretationResult(
      facts: facts,
      uncertainties: uncertainties,
    );
  }
}
