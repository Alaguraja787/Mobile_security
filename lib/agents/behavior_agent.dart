import '../models/privacy_event.dart';

class BehaviorAgent {

  List<String> analyze(
      PrivacyEvent event
  ) {

    List<String> findings = [];

    if (event.screenLocked == true &&
        event.uploadBytes != null &&
        event.uploadBytes! > 5000000) {

      findings.add(
          "High upload while screen locked");
    }

    if (event.hasOverlayPermission == true) {

      findings.add(
          "Overlay permission enabled");
    }

    if (event.accessibilityEnabled == true) {

      findings.add(
          "Accessibility service enabled");
    }

    if (event.vpnActive == true) {

      findings.add(
          "VPN connection detected");
    }

    if (event.batteryOptimizationIgnored == true) {

      findings.add(
          "Battery optimization disabled");
    }

    return findings;
  }

}