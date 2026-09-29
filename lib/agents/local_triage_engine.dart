import '../models/app_telemetry.dart';
import '../models/privacy_event.dart';

class LocalTriageEngine {
  int calculateBaseRisk(
    AppTelemetry app, {
    bool screenLocked = false,
    bool accessibilityEnabled = false,
    bool batteryOptimizationIgnored = false,
    bool vpnActive = false,
  }) {
    int risk = 0;

    // Screen locked + heavy upload
    if (screenLocked && (app.uploadBytes ?? 0) > 5 * 1024 * 1024) {
      risk += 20;
    }

    // Overlay Op
    if (app.hasOverlayOp) {
      risk += 20;
    }

    // Accessibility
    if (accessibilityEnabled) {
      risk += 15;
    }

    // Battery Optimization Disabled
    if (batteryOptimizationIgnored) {
      risk += 10;
    }

    // VPN
    if (vpnActive) {
      risk += 5;
    }

    // Long foreground usage
    if (app.foregroundMinutes != null && app.foregroundMinutes! > 30) {
      risk += 10;
    }

    // Too many permissions
    if (app.permissions.length > 10) {
      risk += 10;
    }

    return risk;
  }

  int calculateRiskFromEvent(AppTelemetry app, PrivacyEvent event) {
    return calculateBaseRisk(
      app,
      screenLocked: event.deviceContext.screenLocked == true,
      accessibilityEnabled: event.securityContext.accessibilityEnabled == true,
      batteryOptimizationIgnored:
          event.securityContext.selfIsIgnoringBatteryOptimizations == true,
      vpnActive: event.securityContext.vpnActive == true || event.network.vpnActive,
    );
  }
}