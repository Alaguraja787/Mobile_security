import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/models/app_info.dart';
import 'package:mobile_privacy_security_project/models/telemetry_diagnostics.dart';
import 'package:mobile_privacy_security_project/telemetry/app_telemetry_builder.dart';

void main() {
  group('Mobile Device Layer - Telemetry Models & Builder Tests', () {
    test('PrivacyEvent parses genuine Android telemetry map accurately with sub-models', () {
      final sampleNativeMap = {
        "timestamp": "2026-08-12T10:00:00Z",
        "deviceContext": {
          "manufacturer": "Google",
          "model": "Pixel 8",
          "brand": "google",
          "device": "shiba",
          "board": "shiba",
          "hardware": "zuma",
          "androidVersion": "14",
          "sdkInt": 34,
          "screenOn": true,
          "screenLocked": false,
          "isDeviceSecure": true,
          "batteryPercent": 85,
          "isCharging": true,
          "batteryStatus": "CHARGING",
          "batteryPlugged": "AC",
          "batteryHealth": "GOOD",
          "batteryTemperatureCelsius": 31.5,
          "batteryVoltageMv": 4150,
          "powerSaveMode": false,
          "deviceIdleMode": false,
          "uptimeMs": 3600000,
          "timezone": "Asia/Kolkata",
          "locale": "en-US"
        },
        "deviceSecurity": {
          "selfCanDrawOverlays": true,
          "selfIsIgnoringBatteryOptimizations": true,
          "selfCanRequestPackageInstalls": false,
          "accessibilityEnabled": false,
          "enabledAccessibilityServices": <String>[],
          "developerOptionsEnabled": false,
          "adbEnabled": false,
          "isDeviceSecure": true,
          "vpnActive": false,
          "rootDetection": {
            "isRootedHeuristic": false,
            "confidence": "NONE",
            "matchedIndicators": <String>[],
            "disclaimer": "Probabilistic heuristic."
          }
        },
        "network": {
          "isConnected": true,
          "transport": "WIFI",
          "isMetered": false,
          "downstreamBandwidthKbps": 100000,
          "upstreamBandwidthKbps": 50000,
          "vpnActive": false,
          "deviceTotalTxBytes": 5242880,
          "deviceTotalRxBytes": 10485760,
          "deviceMobileTxBytes": 0,
          "deviceMobileRxBytes": 0,
        },
        "sensorTelemetry": {
          "cameraHardwareInUse": true,
          "unavailableCamerasCount": 1,
          "microphoneHardwareInUse": true,
          "activeAudioRecordingsCount": 1,
          "isMicrophoneMuted": false,
          "audioMode": "NORMAL",
          "attributionScope": "DEVICE_LEVEL_ONLY"
        },
        "usageSummary": {
          "usageAccessGranted": true,
          "availability": "AVAILABLE",
          "reason": "",
          "currentForegroundApp": "com.example.testapp",
          "totalForegroundDurationMs": 120000,
          "totalForegroundTransitions": 4
        },
        "diagnostics": [
          {
            "field": "screenState",
            "value": "Interactive: true, Locked: false",
            "sourceApi": "PowerManager / KeyguardManager",
            "scope": "DEVICE",
            "collectionType": "PERIODIC_SNAPSHOT",
            "availability": "AVAILABLE",
            "limitation": "Real-time inspection"
          }
        ],
        "apps": [
          {
            "appName": "Test Application",
            "packageName": "com.example.testapp",
            "isSystemApp": false,
            "isEnabled": true,
            "uid": 10150,
            "targetSdkVersion": 34,
            "minSdkVersion": 26,
            "versionName": "1.0.0",
            "versionCode": 100,
            "firstInstallTime": 1720000000000,
            "lastUpdateTime": 1723000000000,
            "installerPackage": "com.android.vending",
            "requestedPermissions": [
              "android.permission.CAMERA",
              "android.permission.INTERNET"
            ],
            "grantedPermissions": [
              "android.permission.CAMERA",
              "android.permission.INTERNET"
            ],
            "deniedPermissions": <String>[],
            "dangerousPermissions": [
              "android.permission.CAMERA"
            ],
            "hasOverlayOp": true,
            "hasUsageAccessOp": false,
            "foregroundDurationMs": 60000,
            "foregroundMinutes": 1.0,
            "foregroundTransitionCount": 2,
            "lastTimeUsedMs": 1723456789000,
            "isCurrentlyForeground": true,
            "isRecentlyUsedDerived": true,
            "uploadBytes": 1024,
            "downloadBytes": 2048,
            "networkUsageAvailability": "AVAILABLE",
            "networkUsageSource": "NetworkStatsManager"
          }
        ]
      };

      final event = PrivacyEvent.fromMap(sampleNativeMap);

      expect(event.timestamp, "2026-08-12T10:00:00Z");
      expect(event.deviceContext.manufacturer, "Google");
      expect(event.deviceContext.batteryPercent, 85);
      expect(event.deviceContext.batteryStatus, "CHARGING");
      expect(event.securityContext.selfCanDrawOverlays, true);
      expect(event.securityContext.isRootedHeuristic, false);
      expect(event.securityContext.rootConfidence, "NONE");
      expect(event.network.transport, "WIFI");
      expect(event.network.deviceTotalTxBytes, 5242880);
      expect(event.sensorTelemetry.cameraHardwareInUse, true);
      expect(event.sensorTelemetry.microphoneHardwareInUse, true);
      expect(event.sensorTelemetry.attributionScope, "DEVICE_LEVEL_ONLY");
      expect(event.usageSummary.usageAccessGranted, true);
      expect(event.usageSummary.totalForegroundTransitions, 4);
      expect(event.diagnostics.length, 1);
      expect(event.diagnostics.first.field, "screenState");

      // Backward compatibility getters
      expect(event.screenLocked, false);
      expect(event.screenOn, true);
      expect(event.isDeviceSecure, true);
      expect(event.uploadBytes, 5242880);
      expect(event.downloadBytes, 10485760);
      expect(event.networkTransport, "WIFI");
      expect(event.hasOverlayPermission, true);
      expect(event.accessibilityEnabled, false);
      expect(event.batteryOptimizationIgnored, true);
      expect(event.vpnActive, false);
      expect(event.apps.length, 1);
    });

    test('AppTelemetryBuilder isolates UID traffic and maps real metrics', () {
      final sampleNativeMap = {
        "timestamp": "2026-08-12T10:00:00Z",
        "deviceContext": {"screenLocked": true},
        "deviceSecurity": {"selfCanDrawOverlays": false, "vpnActive": true},
        "network": {"deviceTotalTxBytes": 50000000, "deviceTotalRxBytes": 100000000},
        "apps": [
          {
            "appName": "Safe App",
            "packageName": "com.safe.app",
            "isSystemApp": false,
            "uid": 10201,
            "requestedPermissions": ["android.permission.INTERNET"],
            "grantedPermissions": ["android.permission.INTERNET"],
            "deniedPermissions": <String>[],
            "dangerousPermissions": <String>[],
            "hasOverlayOp": false,
            "hasUsageAccessOp": true,
            "foregroundDurationMs": 330000,
            "foregroundMinutes": 5.5,
            "foregroundTransitionCount": 3,
            "lastTimeUsedMs": 1723456789000,
            "isCurrentlyForeground": false,
            "isRecentlyUsedDerived": true,
            "uploadBytes": 1024,
            "downloadBytes": 4096,
            "networkUsageAvailability": "AVAILABLE",
            "networkUsageSource": "NetworkStatsManager"
          }
        ]
      };

      final event = PrivacyEvent.fromMap(sampleNativeMap);
      final builder = AppTelemetryBuilder();
      final List<AppTelemetry> appTelemetryList = builder.build(event);

      expect(appTelemetryList.length, 1);
      final AppTelemetry app = appTelemetryList.first;

      expect(app.appName, "Safe App");
      expect(app.packageName, "com.safe.app");
      expect(app.uid, 10201);
      expect(app.foregroundDurationMs, 330000);
      expect(app.foregroundMinutes, 5.5);
      expect(app.foregroundTransitionCount, 3);
      expect(app.isActive, true);
      expect(app.uploadBytes, 1024);
      expect(app.downloadBytes, 4096);
      expect(app.networkUsageAvailability, "AVAILABLE");
      expect(app.hasOverlayOp, false);
      expect(app.hasUsageAccessOp, true);

      // Device-level state is on PrivacyEvent sub-models, NOT on AppTelemetry
      expect(event.deviceContext.screenLocked, true);
      expect(event.securityContext.vpnActive, true);
    });

    test('AppInfo parses JSON accurately', () {
      final info = AppInfo.fromJson({
        "appName": "Camera Pro",
        "packageName": "com.camera.pro",
        "isSystemApp": false,
        "isEnabled": true,
        "uid": 10300,
        "versionName": "2.1.0",
        "versionCode": 21,
        "requestedPermissions": ["android.permission.CAMERA", "android.permission.RECORD_AUDIO"],
        "grantedPermissions": ["android.permission.CAMERA"],
        "dangerousPermissions": ["android.permission.CAMERA"],
      });

      expect(info.name, "Camera Pro");
      expect(info.package, "com.camera.pro");
      expect(info.uid, 10300);
      expect(info.permissions.length, 2);
      expect(info.grantedPermissions.length, 1);
      expect(info.dangerousPermissions.contains("android.permission.CAMERA"), true);
    });

    test('TelemetryDiagnosticItem parses JSON accurately', () {
      final item = TelemetryDiagnosticItem.fromMap({
        "field": "appNetworkUsage",
        "value": "Aggregated via NetworkStatsManager",
        "sourceApi": "NetworkStatsManager.querySummary",
        "scope": "APP",
        "collectionType": "HISTORICAL_STATISTIC",
        "availability": "AVAILABLE",
        "limitation": "Requires PACKAGE_USAGE_STATS"
      });

      expect(item.field, "appNetworkUsage");
      expect(item.availability, "AVAILABLE");
      expect(item.scope, "APP");
      expect(item.collectionType, "HISTORICAL_STATISTIC");
    });

    test('Availability semantics correctly handle RESTRICTED, UNAVAILABLE, and ZERO_REPORTED', () {
      final restrictedNativeMap = {
        "timestamp": "2026-08-12T10:00:00Z",
        "deviceContext": {
          "screenOn": false,
          "batteryPercent": -1,
          "batteryStatus": "UNKNOWN"
        },
        "deviceSecurity": {
          "selfCanDrawOverlays": false,
          "accessibilityEnabled": false
        },
        "network": {
          "isConnected": false,
          "transport": "NONE",
          "trafficStatsAvailability": "UNSUPPORTED",
          "deviceTotalTxBytes": null,
          "deviceTotalRxBytes": null,
        },
        "sensorTelemetry": {
          "cameraHardwareInUse": false,
          "microphoneHardwareInUse": false,
          "attributionScope": "DEVICE_LEVEL_ONLY",
          "sensorAvailability": "AVAILABLE"
        },
        "usageSummary": {
          "usageAccessGranted": false,
          "availability": "RESTRICTED",
          "reason": "PACKAGE_USAGE_STATS_REQUIRED",
          "currentForegroundApp": null,
          "totalForegroundDurationMs": 0,
          "totalForegroundTransitions": 0
        },
        "apps": [
          {
            "appName": "Restricted App",
            "packageName": "com.restricted.app",
            "uid": 10400,
            "requestedPermissions": ["android.permission.INTERNET"],
            "grantedPermissions": ["android.permission.INTERNET"],
            "deniedPermissions": <String>[],
            "dangerousGrantedPermissions": <String>[],
            "dangerousRequestedPermissions": <String>[],
            "hasOverlayOp": false,
            "hasUsageAccessOp": false,
            "foregroundDurationMs": null,
            "foregroundMinutes": null,
            "foregroundTransitionCount": null,
            "lastTimeUsedMs": null,
            "isCurrentlyForeground": null,
            "isRecentlyUsedDerived": null,
            "usageAvailability": "RESTRICTED",
            "uploadBytes": null,
            "downloadBytes": null,
            "networkUsageAvailability": "RESTRICTED",
            "networkUsageSource": "UNAVAILABLE_NO_PERMISSION"
          }
        ]
      };

      final event = PrivacyEvent.fromMap(restrictedNativeMap);
      expect(event.usageSummary.usageAccessGranted, false);
      expect(event.usageSummary.availability, "RESTRICTED");
      expect(event.network.trafficStatsAvailability, "UNSUPPORTED");
      expect(event.network.deviceTotalTxBytes, isNull);
      expect(event.uploadBytes, isNull);
      expect(event.downloadBytes, isNull);
      expect(event.mobileUploadBytes, isNull);
      expect(event.mobileDownloadBytes, isNull);

      final builder = AppTelemetryBuilder();
      final apps = builder.build(event);
      expect(apps.first.usageAvailability, "RESTRICTED");
      expect(apps.first.networkUsageAvailability, "RESTRICTED");
      expect(apps.first.networkUsageSource, "UNAVAILABLE_NO_PERMISSION");
      expect(apps.first.uploadBytes, isNull);
      expect(apps.first.downloadBytes, isNull);
      expect(apps.first.foregroundDurationMs, isNull);
      expect(apps.first.foregroundMinutes, isNull);
      expect(apps.first.foregroundTransitionCount, isNull);
      expect(apps.first.lastTimeUsedMs, isNull);
      expect(apps.first.isCurrentlyForeground, isNull);
      expect(apps.first.isRecentlyUsedDerived, isNull);
      expect(apps.first.isActive, isNull);
    });

    test('TelemetryHealth parses all collector health states and foreground service state accurately', () {
      final sampleHealthMap = {
        "timestamp": "2026-08-13T12:00:00Z",
        "deviceContext": {"screenOn": true},
        "deviceSecurity": {"vpnActive": false},
        "network": {"isConnected": true},
        "sensorTelemetry": {"sensorAvailability": "AVAILABLE"},
        "usageSummary": {"usageAccessGranted": true},
        "telemetryHealth": {
          "permissions": {
            "status": "VALID",
            "message": "24 packages scanned",
            "sourceApi": "PackageManager.getInstalledPackages",
            "lastSuccessTimestampMs": 1723500000000
          },
          "usage": {
            "status": "RESTRICTED",
            "message": "PACKAGE_USAGE_STATS permission required",
            "sourceApi": "UsageStatsManager / UsageEvents",
            "lastSuccessTimestampMs": 0
          },
          "network": {
            "status": "VALID",
            "message": "Operating nominally",
            "sourceApi": "TrafficStats / ConnectivityManager",
            "lastSuccessTimestampMs": 1723500000000
          },
          "security": {
            "status": "VALID",
            "message": "Operating nominally",
            "sourceApi": "Settings.Global / KeyguardManager",
            "lastSuccessTimestampMs": 1723500000000
          },
          "sensors": {
            "status": "VALID",
            "message": "Camera & Audio callbacks active",
            "sourceApi": "CameraManager / AudioManager",
            "lastSuccessTimestampMs": 1723500000000
          },
          "deviceContext": {
            "status": "VALID",
            "message": "Operating nominally",
            "sourceApi": "PowerManager / BatteryManager",
            "lastSuccessTimestampMs": 1723500000000
          },
          "foregroundService": {
            "state": "RUNNING",
            "isRunning": true,
            "lastError": null,
            "foregroundServiceType": "dataSync",
            "maxDurationHours": 6
          }
        },
        "apps": []
      };

      final event = PrivacyEvent.fromMap(sampleHealthMap);
      expect(event.telemetryHealth.permissions.status, "VALID");
      expect(event.telemetryHealth.permissions.message, "24 packages scanned");
      expect(event.telemetryHealth.usage.status, "RESTRICTED");
      expect(event.telemetryHealth.usage.sourceApi, "UsageStatsManager / UsageEvents");
      expect(event.telemetryHealth.network.status, "VALID");
      expect(event.telemetryHealth.security.status, "VALID");
      expect(event.telemetryHealth.sensors.status, "VALID");
      expect(event.telemetryHealth.deviceContext.status, "VALID");
      expect(event.telemetryHealth.foregroundService?["state"], "RUNNING");
      expect(event.telemetryHealth.foregroundService?["isRunning"], true);
      expect(event.telemetryHealth.foregroundService?["maxDurationHours"], 6);

      final serialized = event.toJson();
      expect(serialized.containsKey("telemetryHealth"), true);
      expect((serialized["telemetryHealth"] as Map)["permissions"]["status"], "VALID");
      expect((serialized["telemetryHealth"] as Map)["usage"]["status"], "RESTRICTED");
      expect((serialized["telemetryHealth"] as Map)["foregroundService"]["state"], "RUNNING");
    });

    test('dangerousGrantedPermissions and dangerousRequestedPermissions are distinctly classified', () {
      final sampleAppMap = {
        "timestamp": "2026-08-13T12:00:00Z",
        "deviceContext": {},
        "deviceSecurity": {},
        "network": {},
        "sensorTelemetry": {},
        "usageSummary": {},
        "apps": [
          {
            "appName": "Camera Pro App",
            "packageName": "com.camera.pro",
            "uid": 10500,
            "requestedPermissions": [
              "android.permission.CAMERA",
              "android.permission.RECORD_AUDIO",
              "android.permission.ACCESS_FINE_LOCATION",
              "android.permission.INTERNET"
            ],
            "grantedPermissions": [
              "android.permission.CAMERA",
              "android.permission.INTERNET"
            ],
            "deniedPermissions": [
              "android.permission.RECORD_AUDIO",
              "android.permission.ACCESS_FINE_LOCATION"
            ],
            "dangerousGrantedPermissions": [
              "android.permission.CAMERA"
            ],
            "dangerousRequestedPermissions": [
              "android.permission.CAMERA",
              "android.permission.RECORD_AUDIO",
              "android.permission.ACCESS_FINE_LOCATION"
            ],
            "foregroundMinutes": 0.0
          }
        ]
      };

      final event = PrivacyEvent.fromMap(sampleAppMap);
      final builder = AppTelemetryBuilder();
      final apps = builder.build(event);

      expect(apps.length, 1);
      final app = apps.first;
      expect(app.dangerousGrantedPermissions.length, 1);
      expect(app.dangerousGrantedPermissions.contains("android.permission.CAMERA"), true);
      expect(app.dangerousRequestedPermissions.length, 3);
      expect(app.dangerousRequestedPermissions.contains("android.permission.RECORD_AUDIO"), true);
      expect(app.dangerousRequestedPermissions.contains("android.permission.ACCESS_FINE_LOCATION"), true);
      expect(app.deniedPermissions.length, 2);
    });

    test('Explicit network failure semantics distinguish ZERO_REPORTED from ERROR and RESTRICTED', () {
      final multiStatusMap = {
        "timestamp": "2026-08-13T12:00:00Z",
        "deviceContext": {},
        "deviceSecurity": {},
        "network": {},
        "sensorTelemetry": {},
        "usageSummary": {},
        "apps": [
          {
            "appName": "Zero Usage App",
            "packageName": "com.zero.app",
            "uid": 10001,
            "requestedPermissions": <String>[],
            "grantedPermissions": <String>[],
            "deniedPermissions": <String>[],
            "dangerousGrantedPermissions": <String>[],
            "dangerousRequestedPermissions": <String>[],
            "foregroundMinutes": 0.0,
            "uploadBytes": 0,
            "downloadBytes": 0,
            "networkUsageAvailability": "ZERO_REPORTED",
            "networkUsageSource": "NetworkStatsManager",
            "usageAvailability": "ZERO_REPORTED"
          },
          {
            "appName": "Error Query App",
            "packageName": "com.error.app",
            "uid": 10002,
            "requestedPermissions": <String>[],
            "grantedPermissions": <String>[],
            "deniedPermissions": <String>[],
            "dangerousGrantedPermissions": <String>[],
            "dangerousRequestedPermissions": <String>[],
            "foregroundMinutes": 0.0,
            "uploadBytes": null,
            "downloadBytes": null,
            "networkUsageAvailability": "ERROR",
            "networkUsageSource": "QUERY_ERROR",
            "usageAvailability": "ERROR"
          },
          {
            "appName": "Active Valid App",
            "packageName": "com.active.app",
            "uid": 10003,
            "requestedPermissions": <String>[],
            "grantedPermissions": <String>[],
            "deniedPermissions": <String>[],
            "dangerousGrantedPermissions": <String>[],
            "dangerousRequestedPermissions": <String>[],
            "foregroundMinutes": 10.0,
            "uploadBytes": 2048,
            "downloadBytes": 4096,
            "networkUsageAvailability": "VALID",
            "networkUsageSource": "NetworkStatsManager",
            "usageAvailability": "VALID"
          },
          {
            "appName": "Unavailable Network App",
            "packageName": "com.unavail.app",
            "uid": 10004,
            "requestedPermissions": <String>[],
            "grantedPermissions": <String>[],
            "deniedPermissions": <String>[],
            "dangerousGrantedPermissions": <String>[],
            "dangerousRequestedPermissions": <String>[],
            "foregroundMinutes": 0.0,
            "uploadBytes": null,
            "downloadBytes": null,
            "networkUsageAvailability": "UNAVAILABLE",
            "networkUsageSource": "SERVICE_UNAVAILABLE",
            "usageAvailability": "UNAVAILABLE"
          },
          {
            "appName": "Invalid UID App",
            "packageName": "com.invalid.uid.app",
            "uid": -1,
            "requestedPermissions": <String>[],
            "grantedPermissions": <String>[],
            "deniedPermissions": <String>[],
            "dangerousGrantedPermissions": <String>[],
            "dangerousRequestedPermissions": <String>[],
            "foregroundMinutes": 0.0,
            "uploadBytes": null,
            "downloadBytes": null,
            "networkUsageAvailability": "UNAVAILABLE",
            "networkUsageSource": "INVALID_UID",
            "usageAvailability": "RESTRICTED"
          }
        ]
      };

      final event = PrivacyEvent.fromMap(multiStatusMap);
      final builder = AppTelemetryBuilder();
      final apps = builder.build(event);

      expect(apps.length, 5);

      // ZERO_REPORTED: Genuine zero query
      final zeroApp = apps[0];
      expect(zeroApp.networkUsageAvailability, "ZERO_REPORTED");
      expect(zeroApp.isNetworkStatsAvailable, true);
      expect(zeroApp.uploadBytes, 0);
      expect(zeroApp.downloadBytes, 0);

      // ERROR: Failure -> null bytes (not fabricated 0)
      final errorApp = apps[1];
      expect(errorApp.networkUsageAvailability, "ERROR");
      expect(errorApp.isNetworkStatsAvailable, false);
      expect(errorApp.uploadBytes, isNull);
      expect(errorApp.downloadBytes, isNull);
      expect(errorApp.networkUsageSource, "QUERY_ERROR");

      // VALID: Genuine traffic
      final activeApp = apps[2];
      expect(activeApp.networkUsageAvailability, "VALID");
      expect(activeApp.isNetworkStatsAvailable, true);
      expect(activeApp.uploadBytes, 2048);
      expect(activeApp.downloadBytes, 4096);

      // UNAVAILABLE: Service missing -> null bytes
      final unavailApp = apps[3];
      expect(unavailApp.networkUsageAvailability, "UNAVAILABLE");
      expect(unavailApp.isNetworkStatsAvailable, false);
      expect(unavailApp.uploadBytes, isNull);
      expect(unavailApp.downloadBytes, isNull);
      expect(unavailApp.networkUsageSource, "SERVICE_UNAVAILABLE");

      // INVALID_UID: Missing/Negative UID -> null bytes
      final invalidUidApp = apps[4];
      expect(invalidUidApp.networkUsageAvailability, "UNAVAILABLE");
      expect(invalidUidApp.isNetworkStatsAvailable, false);
      expect(invalidUidApp.uploadBytes, isNull);
      expect(invalidUidApp.downloadBytes, isNull);
      expect(invalidUidApp.networkUsageSource, "INVALID_UID");
    });

    test('AppTelemetry strictly contains only app-level data and no device context', () {
      final app = AppTelemetry(
        appName: "Test",
        packageName: "com.test",
        uid: 10001,
        foregroundMinutes: 2.0,
      );

      final map = app.toJson();
      // Verify app-level fields exist
      expect(map.containsKey("packageName"), true);
      expect(map.containsKey("appName"), true);
      expect(map.containsKey("foregroundTransitionCount"), true);
      expect(map.containsKey("foregroundDurationMs"), true);
      expect(map.containsKey("uploadBytes"), true);
      expect(map.containsKey("downloadBytes"), true);

      // Verify device-level fields DO NOT exist in AppTelemetry
      expect(map.containsKey("screenOn"), false);
      expect(map.containsKey("screenLocked"), false);
      expect(map.containsKey("batteryPercent"), false);
      expect(map.containsKey("isCharging"), false);
      expect(map.containsKey("vpnActive"), false);
      expect(map.containsKey("cameraHardwareInUse"), false);
      expect(map.containsKey("microphoneHardwareInUse"), false);
      expect(map.containsKey("deviceTotalTxBytes"), false);
    });

    test('Foreground service START_FAILED and TIMEOUT states are captured without reporting RUNNING', () {
      final startFailedMap = {
        "timestamp": "2026-08-14T10:00:00Z",
        "deviceContext": {},
        "deviceSecurity": {},
        "network": {},
        "sensorTelemetry": {},
        "usageSummary": {},
        "apps": [],
        "telemetryHealth": {
          "permissions": {"status": "VALID"},
          "usage": {"status": "RESTRICTED"},
          "network": {"status": "VALID"},
          "security": {"status": "VALID"},
          "sensors": {"status": "VALID"},
          "deviceContext": {"status": "VALID"},
          "foregroundService": {
            "state": "START_FAILED",
            "isRunning": false,
            "lastError": "Foreground service start rejected: ForegroundServiceStartNotAllowedException",
            "foregroundServiceType": "dataSync",
            "maxDurationHours": 6
          }
        }
      };

      final startFailedEvent = PrivacyEvent.fromMap(startFailedMap);
      expect(startFailedEvent.telemetryHealth.foregroundService?["state"], "START_FAILED");
      expect(startFailedEvent.telemetryHealth.foregroundService?["isRunning"], false);
      expect(startFailedEvent.telemetryHealth.foregroundService?["lastError"], contains("ForegroundServiceStartNotAllowedException"));

      final timeoutMap = {
        "timestamp": "2026-08-14T10:00:00Z",
        "deviceContext": {},
        "deviceSecurity": {},
        "network": {},
        "sensorTelemetry": {},
        "usageSummary": {},
        "apps": [],
        "telemetryHealth": {
          "permissions": {"status": "VALID"},
          "usage": {"status": "RESTRICTED"},
          "network": {"status": "VALID"},
          "security": {"status": "VALID"},
          "sensors": {"status": "VALID"},
          "deviceContext": {"status": "VALID"},
          "foregroundService": {
            "state": "TIMEOUT",
            "isRunning": false,
            "lastError": "dataSync execution limit reached (Android 15+ 6h limit)",
            "foregroundServiceType": "dataSync",
            "maxDurationHours": 6
          }
        }
      };

      final timeoutEvent = PrivacyEvent.fromMap(timeoutMap);
      expect(timeoutEvent.telemetryHealth.foregroundService?["state"], "TIMEOUT");
      expect(timeoutEvent.telemetryHealth.foregroundService?["isRunning"], false);
      expect(timeoutEvent.telemetryHealth.foregroundService?["state"], isNot("RUNNING"));
    });

    test('Root detection reports observation with rootDetectionMethod=HEURISTIC without definitive claims', () {
      final heuristicSecurityMap = {
        "timestamp": "2026-08-14T10:00:00Z",
        "deviceContext": {},
        "deviceSecurity": {
          "rootDetection": {
            "rootDetectionMethod": "HEURISTIC",
            "isRootedHeuristic": true,
            "confidence": "HEURISTIC_INDICATOR",
            "matchedIndicators": ["BUILD_TAGS_TEST_KEYS"],
            "disclaimer": "Observation only. Heuristic root signals cannot authoritatively confirm or disprove root."
          }
        },
        "network": {},
        "sensorTelemetry": {},
        "usageSummary": {},
        "apps": []
      };

      final event = PrivacyEvent.fromMap(heuristicSecurityMap);
      expect(event.securityContext.rootDetectionMethod, "HEURISTIC");
      expect(event.securityContext.isRootedHeuristic, true);
      expect(event.securityContext.rootConfidence, "HEURISTIC_INDICATOR");
      expect(event.securityContext.rootIndicators, ["BUILD_TAGS_TEST_KEYS"]);
      expect(event.securityContext.rootDisclaimer, contains("Observation only"));

      final serialized = event.toJson();
      final rootJson = (serialized["deviceSecurity"] as Map)["rootDetection"] as Map;
      expect(rootJson["rootDetectionMethod"], "HEURISTIC");
      expect(rootJson["confidence"], "HEURISTIC_INDICATOR");
    });

    test('Null preservation: missing/error values remain null and never default to 0/false/VALID/AVAILABLE', () {
      final nullNativeMap = {
        "timestamp": "2026-08-14T10:00:00Z",
        "deviceContext": {
          "screenOn": null,
          "screenLocked": null,
          "isDeviceSecure": null,
          "batteryPercent": null,
          "isCharging": null,
          "batteryTemperatureCelsius": null,
          "batteryVoltageMv": null,
          "powerSaveMode": null,
          "deviceIdleMode": null,
        },
        "deviceSecurity": {
          "selfCanDrawOverlays": null,
          "selfIsIgnoringBatteryOptimizations": null,
          "selfCanRequestPackageInstalls": null,
          "accessibilityEnabled": null,
          "enabledAccessibilityServices": null,
          "developerOptionsEnabled": null,
          "adbEnabled": null,
          "isDeviceSecure": null,
          "vpnActive": null,
        },
        "network": {
          "isConnected": false,
          "trafficStatsAvailability": "UNSUPPORTED",
          "deviceTotalTxBytes": null,
          "deviceTotalRxBytes": null,
        },
        "sensorTelemetry": {
          "cameraUnavailable": null,
          "cameraHardwareInUse": null,
          "unavailableCamerasCount": null,
          "microphoneHardwareInUse": null,
          "activeAudioRecordingsCount": null,
          "isMicrophoneMuted": null,
          "sensorAvailability": "ERROR"
        },
        "usageSummary": {
          "usageAccessGranted": false,
          "availability": "RESTRICTED",
          "totalForegroundDurationMs": null,
          "totalForegroundTransitions": null
        },
        "apps": []
      };

      final event = PrivacyEvent.fromMap(nullNativeMap);

      // Device context null checks
      expect(event.deviceContext.screenOn, isNull);
      expect(event.deviceContext.screenLocked, isNull);
      expect(event.deviceContext.isDeviceSecure, isNull);
      expect(event.deviceContext.batteryPercent, isNull);
      expect(event.deviceContext.isCharging, isNull);
      expect(event.deviceContext.batteryTemperatureCelsius, isNull);
      expect(event.deviceContext.batteryVoltageMv, isNull);
      expect(event.deviceContext.powerSaveMode, isNull);
      expect(event.deviceContext.deviceIdleMode, isNull);

      // Security context null checks
      expect(event.securityContext.selfCanDrawOverlays, isNull);
      expect(event.securityContext.selfIsIgnoringBatteryOptimizations, isNull);
      expect(event.securityContext.selfCanRequestPackageInstalls, isNull);
      expect(event.securityContext.accessibilityEnabled, isNull);
      expect(event.securityContext.enabledAccessibilityServices, isNull);
      expect(event.securityContext.developerOptionsEnabled, isNull);
      expect(event.securityContext.adbEnabled, isNull);
      expect(event.securityContext.isDeviceSecure, isNull);
      expect(event.securityContext.vpnActive, isNull);

      // Sensor telemetry null checks & camera semantics
      expect(event.sensorTelemetry.cameraUnavailable, isNull);
      expect(event.sensorTelemetry.cameraHardwareInUse, isNull);
      expect(event.sensorTelemetry.unavailableCamerasCount, isNull);
      expect(event.sensorTelemetry.microphoneHardwareInUse, isNull);
      expect(event.sensorTelemetry.sensorAvailability, "ERROR");

      // Usage summary null checks
      expect(event.usageSummary.totalForegroundDurationMs, isNull);
      expect(event.usageSummary.totalForegroundTransitions, isNull);

      // Backward compatibility getters
      expect(event.screenLocked, isNull);
      expect(event.screenOn, isNull);
      expect(event.isDeviceSecure, isNull);
      expect(event.hasOverlayPermission, isNull);
      expect(event.accessibilityEnabled, isNull);
      expect(event.batteryOptimizationIgnored, isNull);
      expect(event.cameraHardwareInUse, isNull);
      expect(event.cameraUnavailable, isNull);
      expect(event.microphoneHardwareInUse, isNull);
      expect(event.foregroundTime, isNull);
      expect(event.launchCount, isNull);
    });

    test('Genuine zero and false values are preserved accurately and distinct from null', () {
      final genuineZeroMap = {
        "timestamp": "2026-08-14T10:00:00Z",
        "deviceContext": {
          "screenOn": false,
          "screenLocked": false,
          "isDeviceSecure": false,
          "batteryPercent": 0,
          "isCharging": false,
          "batteryTemperatureCelsius": 0.0,
          "batteryVoltageMv": 0,
          "powerSaveMode": false,
          "deviceIdleMode": false,
        },
        "deviceSecurity": {
          "selfCanDrawOverlays": false,
          "selfIsIgnoringBatteryOptimizations": false,
          "selfCanRequestPackageInstalls": false,
          "accessibilityEnabled": false,
          "enabledAccessibilityServices": <String>[],
          "developerOptionsEnabled": false,
          "adbEnabled": false,
          "isDeviceSecure": false,
          "vpnActive": false,
        },
        "sensorTelemetry": {
          "cameraUnavailable": false,
          "cameraHardwareInUse": null,
          "unavailableCamerasCount": 0,
          "microphoneHardwareInUse": false,
          "activeAudioRecordingsCount": 0,
          "isMicrophoneMuted": false,
          "sensorAvailability": "AVAILABLE"
        },
        "usageSummary": {
          "usageAccessGranted": true,
          "availability": "ZERO_REPORTED",
          "totalForegroundDurationMs": 0,
          "totalForegroundTransitions": 0
        },
        "apps": []
      };

      final event = PrivacyEvent.fromMap(genuineZeroMap);

      expect(event.deviceContext.screenOn, false);
      expect(event.deviceContext.screenLocked, false);
      expect(event.deviceContext.isDeviceSecure, false);
      expect(event.deviceContext.batteryPercent, 0);
      expect(event.deviceContext.isCharging, false);
      expect(event.deviceContext.batteryTemperatureCelsius, 0.0);
      expect(event.deviceContext.batteryVoltageMv, 0);
      expect(event.deviceContext.powerSaveMode, false);
      expect(event.deviceContext.deviceIdleMode, false);

      expect(event.securityContext.selfCanDrawOverlays, false);
      expect(event.securityContext.selfIsIgnoringBatteryOptimizations, false);
      expect(event.securityContext.accessibilityEnabled, false);
      expect(event.securityContext.enabledAccessibilityServices, isEmpty);
      expect(event.securityContext.developerOptionsEnabled, false);
      expect(event.securityContext.adbEnabled, false);
      expect(event.securityContext.isDeviceSecure, false);
      expect(event.securityContext.vpnActive, false);

      expect(event.sensorTelemetry.cameraUnavailable, false);
      expect(event.sensorTelemetry.cameraHardwareInUse, isNull);
      expect(event.sensorTelemetry.unavailableCamerasCount, 0);
      expect(event.sensorTelemetry.microphoneHardwareInUse, false);

      expect(event.usageSummary.totalForegroundDurationMs, 0);
      expect(event.usageSummary.totalForegroundTransitions, 0);
    });

    test('Omitted/missing telemetry defaults to UNKNOWN instead of inventing VALID or healthy state', () {
      final emptyMap = {
        "timestamp": "2026-08-14T10:00:00Z",
        "deviceContext": {},
        "deviceSecurity": {},
        "network": {},
        "sensorTelemetry": {},
        "usageSummary": {},
        "apps": [
          {
            "appName": "Unknown App",
            "packageName": "com.unknown.app",
          }
        ]
      };

      final event = PrivacyEvent.fromMap(emptyMap);

      // Health must default to UNKNOWN, not VALID
      expect(event.telemetryHealth.permissions.status, "UNKNOWN");
      expect(event.telemetryHealth.usage.status, "UNKNOWN");
      expect(event.telemetryHealth.network.status, "UNKNOWN");
      expect(event.telemetryHealth.security.status, "UNKNOWN");
      expect(event.telemetryHealth.sensors.status, "UNKNOWN");
      expect(event.telemetryHealth.deviceContext.status, "UNKNOWN");

      // Network & Sensor availability must default to UNKNOWN
      expect(event.network.trafficStatsAvailability, "UNKNOWN");
      expect(event.sensorTelemetry.sensorAvailability, "UNKNOWN");
      expect(event.sensorTelemetry.audioMode, "UNKNOWN");
      expect(event.usageSummary.availability, "UNKNOWN");

      // App telemetry builder must preserve UNKNOWN
      final builder = AppTelemetryBuilder();
      final apps = builder.build(event);
      expect(apps.first.usageAvailability, "UNKNOWN");
      expect(apps.first.networkUsageAvailability, "UNKNOWN");
      expect(apps.first.networkUsageSource, "UNKNOWN");
      expect(apps.first.foregroundDurationMs, isNull);
      expect(apps.first.foregroundMinutes, isNull);
      expect(apps.first.lastTimeUsedMs, isNull);
      expect(apps.first.foregroundTransitionCount, isNull);
      expect(apps.first.isCurrentlyForeground, isNull);
      expect(apps.first.isRecentlyUsedDerived, isNull);
      expect(apps.first.isActive, isNull);
    });

    test('AppUsage telemetry nullability: Case 1 (Actual), Case 2 (Genuine Zero/False), Case 3 (Null/Unavailable)', () {
      final nativeMap = {
        "timestamp": "2026-08-17T10:00:00Z",
        "deviceContext": {},
        "deviceSecurity": {},
        "network": {},
        "sensorTelemetry": {},
        "usageSummary": {
          "usageAccessGranted": true,
          "availability": "VALID",
        },
        "apps": [
          // Case 1: Android reported actual positive usage
          {
            "appName": "Case 1 Active App",
            "packageName": "com.case1.active",
            "uid": 10101,
            "foregroundDurationMs": 120000,
            "foregroundMinutes": 2.0,
            "lastTimeUsedMs": 1723456789000,
            "foregroundTransitionCount": 5,
            "isCurrentlyForeground": true,
            "isRecentlyUsedDerived": true,
            "usageAvailability": "VALID",
          },
          // Case 2: Android reported genuine zero / false usage
          {
            "appName": "Case 2 Zero App",
            "packageName": "com.case2.zero",
            "uid": 10102,
            "foregroundDurationMs": 0,
            "foregroundMinutes": 0.0,
            "lastTimeUsedMs": 0,
            "foregroundTransitionCount": 0,
            "isCurrentlyForeground": false,
            "isRecentlyUsedDerived": false,
            "usageAvailability": "ZERO_REPORTED",
          },
          // Case 3: Android usage telemetry unavailable (null)
          {
            "appName": "Case 3 Null App",
            "packageName": "com.case3.null",
            "uid": 10103,
            "foregroundDurationMs": null,
            "foregroundMinutes": null,
            "lastTimeUsedMs": null,
            "foregroundTransitionCount": null,
            "isCurrentlyForeground": null,
            "isRecentlyUsedDerived": null,
            "usageAvailability": "RESTRICTED",
          },
        ]
      };

      final event = PrivacyEvent.fromMap(nativeMap);
      final builder = AppTelemetryBuilder();
      final apps = builder.build(event);

      expect(apps.length, 3);

      // CASE 1: Actual value preserved accurately
      final case1 = apps[0];
      expect(case1.packageName, "com.case1.active");
      expect(case1.foregroundDurationMs, 120000);
      expect(case1.foregroundMinutes, 2.0);
      expect(case1.lastTimeUsedMs, 1723456789000);
      expect(case1.foregroundTransitionCount, 5);
      expect(case1.isCurrentlyForeground, true);
      expect(case1.isRecentlyUsedDerived, true);
      expect(case1.isActive, true);
      expect(case1.foregroundTimeMs, 120000);
      expect(case1.foregroundTime, 120000);
      expect(case1.launchCount, 5);
      expect(case1.isUsageStatsAvailable, true);

      // CASE 2: Genuine 0 / false preserved accurately (distinct from null)
      final case2 = apps[1];
      expect(case2.packageName, "com.case2.zero");
      expect(case2.foregroundDurationMs, 0);
      expect(case2.foregroundMinutes, 0.0);
      expect(case2.lastTimeUsedMs, 0);
      expect(case2.foregroundTransitionCount, 0);
      expect(case2.isCurrentlyForeground, false);
      expect(case2.isRecentlyUsedDerived, false);
      expect(case2.isActive, false);
      expect(case2.foregroundTimeMs, 0);
      expect(case2.foregroundTime, 0);
      expect(case2.launchCount, 0);
      expect(case2.isUsageStatsAvailable, true);

      // CASE 3: Null / unavailable preserved as null (never defaulted to 0 or false)
      final case3 = apps[2];
      expect(case3.packageName, "com.case3.null");
      expect(case3.foregroundDurationMs, isNull);
      expect(case3.foregroundMinutes, isNull);
      expect(case3.lastTimeUsedMs, isNull);
      expect(case3.foregroundTransitionCount, isNull);
      expect(case3.isCurrentlyForeground, isNull);
      expect(case3.isRecentlyUsedDerived, isNull);
      expect(case3.isActive, isNull);
      expect(case3.foregroundTimeMs, isNull);
      expect(case3.foregroundTime, isNull);
      expect(case3.launchCount, isNull);
      expect(case3.isUsageStatsAvailable, false);

      // Verify JSON serialization preservation
      final case1Json = case1.toJson();
      expect(case1Json["foregroundDurationMs"], 120000);
      expect(case1Json["foregroundMinutes"], 2.0);
      expect(case1Json["lastTimeUsedMs"], 1723456789000);
      expect(case1Json["foregroundTransitionCount"], 5);
      expect(case1Json["isCurrentlyForeground"], true);
      expect(case1Json["isRecentlyUsedDerived"], true);

      final case2Json = case2.toJson();
      expect(case2Json["foregroundDurationMs"], 0);
      expect(case2Json["foregroundMinutes"], 0.0);
      expect(case2Json["lastTimeUsedMs"], 0);
      expect(case2Json["foregroundTransitionCount"], 0);
      expect(case2Json["isCurrentlyForeground"], false);
      expect(case2Json["isRecentlyUsedDerived"], false);

      final case3Json = case3.toJson();
      expect(case3Json["foregroundDurationMs"], isNull);
      expect(case3Json["foregroundMinutes"], isNull);
      expect(case3Json["lastTimeUsedMs"], isNull);
      expect(case3Json["foregroundTransitionCount"], isNull);
      expect(case3Json["isCurrentlyForeground"], isNull);
      expect(case3Json["isRecentlyUsedDerived"], isNull);
    });
  });
}


