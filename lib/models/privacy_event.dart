import 'telemetry_diagnostics.dart';

/// Strongly-typed device context (hardware specs + dynamic device state)
class DeviceContext {
  final String manufacturer;
  final String model;
  final String brand;
  final String device;
  final String board;
  final String hardware;
  final String androidVersion;
  final int sdkInt;
  final bool? screenOn;
  final bool? screenLocked;
  final bool? isDeviceSecure;
  final int? batteryPercent;
  final bool? isCharging;
  final String batteryStatus;
  final String batteryPlugged;
  final String batteryHealth;
  final double? batteryTemperatureCelsius;
  final int? batteryVoltageMv;
  final bool? powerSaveMode;
  final bool? deviceIdleMode;
  final int uptimeMs;
  final String timezone;
  final String locale;

  DeviceContext({
    this.manufacturer = "",
    this.model = "",
    this.brand = "",
    this.device = "",
    this.board = "",
    this.hardware = "",
    this.androidVersion = "",
    this.sdkInt = 0,
    this.screenOn,
    this.screenLocked,
    this.isDeviceSecure,
    this.batteryPercent,
    this.isCharging,
    this.batteryStatus = "UNKNOWN",
    this.batteryPlugged = "UNKNOWN",
    this.batteryHealth = "UNKNOWN",
    this.batteryTemperatureCelsius,
    this.batteryVoltageMv,
    this.powerSaveMode,
    this.deviceIdleMode,
    this.uptimeMs = 0,
    this.timezone = "",
    this.locale = "",
  });

  factory DeviceContext.fromMap(Map<dynamic, dynamic> map) {
    bool? parseBool(dynamic v) => v is bool ? v : null;
    return DeviceContext(
      manufacturer: map["manufacturer"]?.toString() ?? "",
      model: map["model"]?.toString() ?? "",
      brand: map["brand"]?.toString() ?? "",
      device: map["device"]?.toString() ?? "",
      board: map["board"]?.toString() ?? "",
      hardware: map["hardware"]?.toString() ?? "",
      androidVersion: map["androidVersion"]?.toString() ?? "",
      sdkInt: (map["sdkInt"] as num?)?.toInt() ?? 0,
      screenOn: parseBool(map["screenOn"]),
      screenLocked: parseBool(map["screenLocked"]),
      isDeviceSecure: parseBool(map["isDeviceSecure"]),
      batteryPercent: (map["batteryPercent"] as num?)?.toInt(),
      isCharging: parseBool(map["isCharging"]),
      batteryStatus: map["batteryStatus"]?.toString() ?? "UNKNOWN",
      batteryPlugged: map["batteryPlugged"]?.toString() ?? "UNKNOWN",
      batteryHealth: map["batteryHealth"]?.toString() ?? "UNKNOWN",
      batteryTemperatureCelsius:
          (map["batteryTemperatureCelsius"] as num?)?.toDouble(),
      batteryVoltageMv: (map["batteryVoltageMv"] as num?)?.toInt(),
      powerSaveMode: parseBool(map["powerSaveMode"]),
      deviceIdleMode: parseBool(map["deviceIdleMode"]),
      uptimeMs: (map["uptimeMs"] as num?)?.toInt() ?? 0,
      timezone: map["timezone"]?.toString() ?? "",
      locale: map["locale"]?.toString() ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "manufacturer": manufacturer,
      "model": model,
      "brand": brand,
      "device": device,
      "board": board,
      "hardware": hardware,
      "androidVersion": androidVersion,
      "sdkInt": sdkInt,
      "screenOn": screenOn,
      "screenLocked": screenLocked,
      "isDeviceSecure": isDeviceSecure,
      "batteryPercent": batteryPercent,
      "isCharging": isCharging,
      "batteryStatus": batteryStatus,
      "batteryPlugged": batteryPlugged,
      "batteryHealth": batteryHealth,
      "batteryTemperatureCelsius": batteryTemperatureCelsius,
      "batteryVoltageMv": batteryVoltageMv,
      "powerSaveMode": powerSaveMode,
      "deviceIdleMode": deviceIdleMode,
      "uptimeMs": uptimeMs,
      "timezone": timezone,
      "locale": locale,
    };
  }
}

/// Strongly-typed device security context
class SecurityContext {
  final bool? selfCanDrawOverlays;
  final bool? selfIsIgnoringBatteryOptimizations;
  final bool? selfCanRequestPackageInstalls;
  final bool? accessibilityEnabled;
  final List<String>? enabledAccessibilityServices;
  final bool? developerOptionsEnabled;
  final bool? adbEnabled;
  final bool? isDeviceSecure;
  final bool? vpnActive;
  final String rootDetectionMethod;
  final bool isRootedHeuristic;
  final String rootConfidence;
  final List<String> rootIndicators;
  final String rootDisclaimer;

  SecurityContext({
    this.selfCanDrawOverlays,
    this.selfIsIgnoringBatteryOptimizations,
    this.selfCanRequestPackageInstalls,
    this.accessibilityEnabled,
    this.enabledAccessibilityServices,
    this.developerOptionsEnabled,
    this.adbEnabled,
    this.isDeviceSecure,
    this.vpnActive,
    this.rootDetectionMethod = "HEURISTIC",
    this.isRootedHeuristic = false,
    this.rootConfidence = "NONE",
    this.rootIndicators = const [],
    this.rootDisclaimer = "",
  });

  factory SecurityContext.fromMap(Map<dynamic, dynamic> map) {
    final rootMap = map["rootDetection"] is Map
        ? Map<String, dynamic>.from(map["rootDetection"] as Map)
        : <String, dynamic>{};

    bool? parseBool(dynamic val1, [dynamic val2]) {
      if (val1 is bool) return val1;
      if (val2 is bool) return val2;
      return null;
    }

    final rawServices = map["enabledAccessibilityServices"];
    final List<String>? services = rawServices is List
        ? List<String>.from(rawServices.map((e) => e.toString()))
        : null;

    return SecurityContext(
      selfCanDrawOverlays: parseBool(
          map["selfCanDrawOverlays"], map["hasOverlayPermission"]),
      selfIsIgnoringBatteryOptimizations: parseBool(
          map["selfIsIgnoringBatteryOptimizations"],
          map["batteryOptimizationIgnored"]),
      selfCanRequestPackageInstalls: parseBool(
          map["selfCanRequestPackageInstalls"],
          map["unknownSourcesAllowed"]),
      accessibilityEnabled: parseBool(map["accessibilityEnabled"]),
      enabledAccessibilityServices: services,
      developerOptionsEnabled: parseBool(map["developerOptionsEnabled"]),
      adbEnabled: parseBool(map["adbEnabled"]),
      isDeviceSecure: parseBool(map["isDeviceSecure"]),
      vpnActive: parseBool(map["vpnActive"]),
      rootDetectionMethod:
          rootMap["rootDetectionMethod"]?.toString() ?? "HEURISTIC",
      isRootedHeuristic: rootMap["isRootedHeuristic"] == true ||
          map["rootDetected"] == true,
      rootConfidence: rootMap["confidence"]?.toString() ?? "NONE",
      rootIndicators: List<String>.from(rootMap["matchedIndicators"] ?? []),
      rootDisclaimer: rootMap["disclaimer"]?.toString() ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "selfCanDrawOverlays": selfCanDrawOverlays,
      "selfIsIgnoringBatteryOptimizations":
          selfIsIgnoringBatteryOptimizations,
      "selfCanRequestPackageInstalls": selfCanRequestPackageInstalls,
      "accessibilityEnabled": accessibilityEnabled,
      "enabledAccessibilityServices": enabledAccessibilityServices,
      "developerOptionsEnabled": developerOptionsEnabled,
      "adbEnabled": adbEnabled,
      "isDeviceSecure": isDeviceSecure,
      "vpnActive": vpnActive,
      "rootDetection": {
        "rootDetectionMethod": rootDetectionMethod,
        "isRootedHeuristic": isRootedHeuristic,
        "confidence": rootConfidence,
        "matchedIndicators": rootIndicators,
        "disclaimer": rootDisclaimer,
      },
    };
  }
}

/// Strongly-typed device-level network telemetry
class NetworkTelemetry {
  final bool isConnected;
  final String transport;
  final bool isMetered;
  final int downstreamBandwidthKbps;
  final int upstreamBandwidthKbps;
  final bool vpnActive;
  final String trafficStatsAvailability;
  final int? deviceTotalTxBytes;
  final int? deviceTotalRxBytes;
  final int? deviceMobileTxBytes;
  final int? deviceMobileRxBytes;

  NetworkTelemetry({
    this.isConnected = false,
    this.transport = "NONE",
    this.isMetered = false,
    this.downstreamBandwidthKbps = 0,
    this.upstreamBandwidthKbps = 0,
    this.vpnActive = false,
    this.trafficStatsAvailability = "UNKNOWN",
    this.deviceTotalTxBytes,
    this.deviceTotalRxBytes,
    this.deviceMobileTxBytes,
    this.deviceMobileRxBytes,
  });

  factory NetworkTelemetry.fromMap(Map<dynamic, dynamic> map) {
    return NetworkTelemetry(
      isConnected: map["isConnected"] == true,
      transport: map["transport"]?.toString() ?? "NONE",
      isMetered: map["isMetered"] == true,
      downstreamBandwidthKbps:
          (map["downstreamBandwidthKbps"] as num?)?.toInt() ?? 0,
      upstreamBandwidthKbps:
          (map["upstreamBandwidthKbps"] as num?)?.toInt() ?? 0,
      vpnActive: map["vpnActive"] == true,
      trafficStatsAvailability:
          map["trafficStatsAvailability"]?.toString() ?? "UNKNOWN",
      deviceTotalTxBytes: (map["deviceTotalTxBytes"] as num?)?.toInt() ??
          (map["uploadBytes"] as num?)?.toInt(),
      deviceTotalRxBytes: (map["deviceTotalRxBytes"] as num?)?.toInt() ??
          (map["downloadBytes"] as num?)?.toInt(),
      deviceMobileTxBytes:
          (map["deviceMobileTxBytes"] as num?)?.toInt() ??
              (map["mobileUploadBytes"] as num?)?.toInt(),
      deviceMobileRxBytes:
          (map["deviceMobileRxBytes"] as num?)?.toInt() ??
              (map["mobileDownloadBytes"] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "isConnected": isConnected,
      "transport": transport,
      "isMetered": isMetered,
      "downstreamBandwidthKbps": downstreamBandwidthKbps,
      "upstreamBandwidthKbps": upstreamBandwidthKbps,
      "vpnActive": vpnActive,
      "trafficStatsAvailability": trafficStatsAvailability,
      "deviceTotalTxBytes": deviceTotalTxBytes,
      "deviceTotalRxBytes": deviceTotalRxBytes,
      "deviceMobileTxBytes": deviceMobileTxBytes,
      "deviceMobileRxBytes": deviceMobileRxBytes,
    };
  }
}

/// Strongly-typed sensor privacy telemetry
class SensorPrivacyTelemetry {
  final bool? cameraUnavailable;
  final bool? cameraHardwareInUse;
  final int? unavailableCamerasCount;
  final bool? microphoneHardwareInUse;
  final int? activeAudioRecordingsCount;
  final bool? isMicrophoneMuted;
  final String audioMode;
  final String attributionScope;
  final String sensorAvailability;

  SensorPrivacyTelemetry({
    this.cameraUnavailable,
    this.cameraHardwareInUse,
    this.unavailableCamerasCount,
    this.microphoneHardwareInUse,
    this.activeAudioRecordingsCount,
    this.isMicrophoneMuted,
    this.audioMode = "UNKNOWN",
    this.attributionScope = "DEVICE_LEVEL_ONLY",
    this.sensorAvailability = "UNKNOWN",
  });

  factory SensorPrivacyTelemetry.fromMap(Map<dynamic, dynamic> map) {
    bool? parseBool(dynamic v) => v is bool ? v : null;
    return SensorPrivacyTelemetry(
      cameraUnavailable: parseBool(map["cameraUnavailable"]),
      cameraHardwareInUse: parseBool(map["cameraHardwareInUse"]),
      unavailableCamerasCount:
          (map["unavailableCamerasCount"] as num?)?.toInt(),
      microphoneHardwareInUse: parseBool(map["microphoneHardwareInUse"]),
      activeAudioRecordingsCount:
          (map["activeAudioRecordingsCount"] as num?)?.toInt(),
      isMicrophoneMuted: parseBool(map["isMicrophoneMuted"]),
      audioMode: map["audioMode"]?.toString() ?? "UNKNOWN",
      attributionScope:
          map["attributionScope"]?.toString() ?? "DEVICE_LEVEL_ONLY",
      sensorAvailability:
          map["sensorAvailability"]?.toString() ?? "UNKNOWN",
    );
  }

  /// Explicit device-level camera availability status (CameraManager.AvailabilityCallback)
  bool? get cameraAvailable =>
      cameraUnavailable != null ? !cameraUnavailable! : null;

  String get cameraAvailabilityStatus {
    if (cameraUnavailable == true) return "CAMERA_UNAVAILABLE";
    if (cameraUnavailable == false) return "CAMERA_AVAILABLE";
    return "UNKNOWN";
  }

  Map<String, dynamic> toJson() {
    return {
      "cameraUnavailable": cameraUnavailable,
      "cameraAvailable": cameraAvailable,
      "cameraAvailabilityStatus": cameraAvailabilityStatus,
      "cameraHardwareInUse": cameraHardwareInUse,
      "unavailableCamerasCount": unavailableCamerasCount,
      "microphoneHardwareInUse": microphoneHardwareInUse,
      "activeAudioRecordingsCount": activeAudioRecordingsCount,
      "isMicrophoneMuted": isMicrophoneMuted,
      "audioMode": audioMode,
      "attributionScope": attributionScope,
      "sensorAvailability": sensorAvailability,
    };
  }
}

/// Strongly-typed usage summary
class UsageSummary {
  final bool usageAccessGranted;
  final String availability;
  final String reason;
  final int queriedIntervalHours;
  final int intervalStartTimeMs;
  final int intervalEndTimeMs;
  final String? currentForegroundApp;
  final int? totalForegroundDurationMs;
  final int? totalForegroundTransitions;

  UsageSummary({
    this.usageAccessGranted = false,
    this.availability = "UNKNOWN",
    this.reason = "",
    this.queriedIntervalHours = 24,
    this.intervalStartTimeMs = 0,
    this.intervalEndTimeMs = 0,
    this.currentForegroundApp,
    this.totalForegroundDurationMs,
    this.totalForegroundTransitions,
  });

  factory UsageSummary.fromMap(Map<dynamic, dynamic> map) {
    return UsageSummary(
      usageAccessGranted: map["usageAccessGranted"] == true,
      availability: map["availability"]?.toString() ?? "UNKNOWN",
      reason: map["reason"]?.toString() ?? "",
      queriedIntervalHours: (map["queriedIntervalHours"] as num?)?.toInt() ?? 24,
      intervalStartTimeMs: (map["intervalStartTimeMs"] as num?)?.toInt() ?? 0,
      intervalEndTimeMs: (map["intervalEndTimeMs"] as num?)?.toInt() ?? 0,
      currentForegroundApp: map["currentForegroundApp"]?.toString(),
      totalForegroundDurationMs:
          (map["totalForegroundDurationMs"] as num?)?.toInt() ??
              (map["totalForegroundTimeMs"] as num?)?.toInt(),
      totalForegroundTransitions:
          (map["totalForegroundTransitions"] as num?)?.toInt() ??
              (map["totalLaunchCount"] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "usageAccessGranted": usageAccessGranted,
      "availability": availability,
      "reason": reason,
      "queriedIntervalHours": queriedIntervalHours,
      "intervalStartTimeMs": intervalStartTimeMs,
      "intervalEndTimeMs": intervalEndTimeMs,
      "currentForegroundApp": currentForegroundApp,
      "totalForegroundDurationMs": totalForegroundDurationMs,
      "totalForegroundTransitions": totalForegroundTransitions,
    };
  }
}

/// Represents the health state of an individual telemetry collector.
class CollectorHealth {
  final String status; // "VALID" | "DENIED" | "RESTRICTED" | "UNAVAILABLE" | "ERROR" | "PARTIAL" | "UNKNOWN"
  final String message;
  final String sourceApi;
  final int lastSuccessTimestampMs;

  CollectorHealth({
    this.status = "UNKNOWN",
    this.message = "Health status unknown",
    this.sourceApi = "",
    this.lastSuccessTimestampMs = 0,
  });

  factory CollectorHealth.fromMap(Map<dynamic, dynamic> map) {
    return CollectorHealth(
      status: map["status"]?.toString() ?? "UNKNOWN",
      message: map["message"]?.toString() ?? "Health status unknown",
      sourceApi: map["sourceApi"]?.toString() ?? "",
      lastSuccessTimestampMs:
          (map["lastSuccessTimestampMs"] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "status": status,
      "message": message,
      "sourceApi": sourceApi,
      "lastSuccessTimestampMs": lastSuccessTimestampMs,
    };
  }
}

/// Structured health status for all five major telemetry collector subsystems.
class TelemetryHealth {
  final CollectorHealth permissions;
  final CollectorHealth usage;
  final CollectorHealth network;
  final CollectorHealth security;
  final CollectorHealth sensors;
  final CollectorHealth deviceContext;
  final Map<String, dynamic>? foregroundService;

  TelemetryHealth({
    required this.permissions,
    required this.usage,
    required this.network,
    required this.security,
    required this.sensors,
    required this.deviceContext,
    this.foregroundService,
  });

  factory TelemetryHealth.fromMap(Map<dynamic, dynamic> map) {
    return TelemetryHealth(
      permissions: CollectorHealth.fromMap(
          map["permissions"] is Map ? map["permissions"] as Map : {}),
      usage: CollectorHealth.fromMap(
          map["usage"] is Map ? map["usage"] as Map : {}),
      network: CollectorHealth.fromMap(
          map["network"] is Map ? map["network"] as Map : {}),
      security: CollectorHealth.fromMap(
          map["security"] is Map ? map["security"] as Map : {}),
      sensors: CollectorHealth.fromMap(
          map["sensors"] is Map ? map["sensors"] as Map : {}),
      deviceContext: CollectorHealth.fromMap(
          map["deviceContext"] is Map ? map["deviceContext"] as Map : {}),
      foregroundService: map["foregroundService"] is Map
          ? Map<String, dynamic>.from(map["foregroundService"] as Map)
          : null,
    );
  }

  factory TelemetryHealth.defaultUnknown() {
    return TelemetryHealth(
      permissions: CollectorHealth(status: "UNKNOWN", message: "Health status not yet collected", sourceApi: "PackageManager.getInstalledPackages"),
      usage: CollectorHealth(status: "UNKNOWN", message: "Health status not yet collected", sourceApi: "UsageStatsManager / UsageEvents"),
      network: CollectorHealth(status: "UNKNOWN", message: "Health status not yet collected", sourceApi: "TrafficStats / ConnectivityManager / NetworkStatsManager"),
      security: CollectorHealth(status: "UNKNOWN", message: "Health status not yet collected", sourceApi: "Settings.Global / KeyguardManager / PowerManager"),
      sensors: CollectorHealth(status: "UNKNOWN", message: "Health status not yet collected", sourceApi: "CameraManager / AudioManager"),
      deviceContext: CollectorHealth(status: "UNKNOWN", message: "Health status not yet collected", sourceApi: "PowerManager / KeyguardManager / BatteryManager"),
      foregroundService: {"state": "UNKNOWN", "isRunning": false},
    );
  }

  factory TelemetryHealth.defaultHealthy() {
    return TelemetryHealth(
      permissions: CollectorHealth(status: "VALID", message: "Operating nominally", sourceApi: "PackageManager.getInstalledPackages"),
      usage: CollectorHealth(status: "VALID", message: "Operating nominally", sourceApi: "UsageStatsManager / UsageEvents"),
      network: CollectorHealth(status: "VALID", message: "Operating nominally", sourceApi: "TrafficStats / ConnectivityManager / NetworkStatsManager"),
      security: CollectorHealth(status: "VALID", message: "Operating nominally", sourceApi: "Settings.Global / KeyguardManager / PowerManager"),
      sensors: CollectorHealth(status: "VALID", message: "Operating nominally", sourceApi: "CameraManager / AudioManager"),
      deviceContext: CollectorHealth(status: "VALID", message: "Operating nominally", sourceApi: "PowerManager / KeyguardManager / BatteryManager"),
      foregroundService: {"state": "STOPPED", "isRunning": false},
    );
  }

  Map<String, dynamic> toJson() {
    final res = <String, dynamic>{
      "permissions": permissions.toJson(),
      "usage": usage.toJson(),
      "network": network.toJson(),
      "security": security.toJson(),
      "sensors": sensors.toJson(),
      "deviceContext": deviceContext.toJson(),
    };
    if (foregroundService != null) {
      res["foregroundService"] = foregroundService!;
    }
    return res;
  }
}

/// Main normalized Privacy Event containing structured contexts and app inventory.
class PrivacyEvent {
  final String timestamp;
  final DeviceContext deviceContext;
  final SecurityContext securityContext;
  final NetworkTelemetry network;
  final SensorPrivacyTelemetry sensorTelemetry;
  final UsageSummary usageSummary;
  final TelemetryHealth telemetryHealth;
  final List<dynamic> apps;
  final List<TelemetryDiagnosticItem> diagnostics;

  PrivacyEvent({
    required this.timestamp,
    required this.deviceContext,
    required this.securityContext,
    required this.network,
    required this.sensorTelemetry,
    required this.usageSummary,
    TelemetryHealth? telemetryHealth,
    required this.apps,
    this.diagnostics = const [],
  }) : telemetryHealth = telemetryHealth ?? TelemetryHealth.defaultUnknown();

  factory PrivacyEvent.fromMap(Map<dynamic, dynamic> map) {
    final devCtxMap = Map<String, dynamic>.from(map["deviceContext"] ?? {});
    final secCtxMap = Map<String, dynamic>.from(map["deviceSecurity"] ?? {});
    final netMap = Map<String, dynamic>.from(map["network"] ?? {});
    final sensorMap = Map<String, dynamic>.from(map["sensorTelemetry"] ?? {});
    final usageMap = Map<String, dynamic>.from(map["usageSummary"] ?? {});
    final healthMap = Map<String, dynamic>.from(map["telemetryHealth"] ?? {});

    final rawDiagnostics = (map["diagnostics"] as List<dynamic>?) ?? [];
    final parsedDiagnostics = rawDiagnostics
        .whereType<Map<dynamic, dynamic>>()
        .map((d) => TelemetryDiagnosticItem.fromMap(d))
        .toList();

    return PrivacyEvent(
      timestamp: map["timestamp"]?.toString() ?? DateTime.now().toIso8601String(),
      deviceContext: DeviceContext.fromMap(devCtxMap),
      securityContext: SecurityContext.fromMap(secCtxMap),
      network: NetworkTelemetry.fromMap(netMap),
      sensorTelemetry: SensorPrivacyTelemetry.fromMap(sensorMap),
      usageSummary: UsageSummary.fromMap(usageMap),
      telemetryHealth: healthMap.isNotEmpty
          ? TelemetryHealth.fromMap(healthMap)
          : TelemetryHealth.defaultUnknown(),
      apps: List<dynamic>.from(map["apps"] ?? []),
      diagnostics: parsedDiagnostics,
    );
  }

  // ---------------------------------------------------------------------------
  // Backward compatibility getters (safe delegates to nested sub-models)
  // ---------------------------------------------------------------------------
  bool? get screenLocked => deviceContext.screenLocked;
  bool? get screenOn => deviceContext.screenOn;
  bool? get isDeviceSecure => deviceContext.isDeviceSecure;
  int? get uploadBytes => network.deviceTotalTxBytes;
  int? get downloadBytes => network.deviceTotalRxBytes;
  int? get mobileUploadBytes => network.deviceMobileTxBytes;
  int? get mobileDownloadBytes => network.deviceMobileRxBytes;
  String get networkTransport => network.transport;
  bool get isMetered => network.isMetered;
  int? get foregroundTime => usageSummary.totalForegroundDurationMs;
  int? get launchCount => usageSummary.totalForegroundTransitions;
  bool? get hasOverlayPermission => securityContext.selfCanDrawOverlays;
  bool? get accessibilityEnabled => securityContext.accessibilityEnabled;
  List<String>? get enabledAccessibilityServices =>
      securityContext.enabledAccessibilityServices;
  bool? get batteryOptimizationIgnored =>
      securityContext.selfIsIgnoringBatteryOptimizations;
  bool? get vpnActive => securityContext.vpnActive != null
      ? (securityContext.vpnActive == true || network.vpnActive)
      : (network.vpnActive ? true : null);
  bool? get developerOptionsEnabled =>
      securityContext.developerOptionsEnabled;
  bool? get adbEnabled => securityContext.adbEnabled;
  bool? get unknownSourcesAllowed =>
      securityContext.selfCanRequestPackageInstalls;
  bool get rootDetected => securityContext.isRootedHeuristic;
  bool? get cameraHardwareInUse => sensorTelemetry.cameraHardwareInUse;
  bool? get cameraUnavailable => sensorTelemetry.cameraUnavailable;
  bool? get microphoneHardwareInUse =>
      sensorTelemetry.microphoneHardwareInUse;
  List<dynamic> get usage => [];

  Map<String, dynamic> toJson() {
    return {
      "timestamp": timestamp,
      "deviceContext": deviceContext.toJson(),
      "deviceSecurity": securityContext.toJson(),
      "network": network.toJson(),
      "sensorTelemetry": sensorTelemetry.toJson(),
      "usageSummary": usageSummary.toJson(),
      "telemetryHealth": telemetryHealth.toJson(),
      "apps": apps,
      "diagnostics": diagnostics.map((d) => d.toJson()).toList(),
    };
  }
}