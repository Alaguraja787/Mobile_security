// ignore_for_file: avoid_print
import 'package:flutter/services.dart';

class AndroidCollector {
  static const MethodChannel _channel = MethodChannel("privacy_sentinel");
  static const EventChannel _eventChannel =
      EventChannel("privacy_sentinel_events");

  static Stream<Map<String, dynamic>>? _cachedRawStream;

  /// Raw broadcast stream from native EventChannel
  Stream<Map<String, dynamic>> get rawEventStream {
    _cachedRawStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    }).asBroadcastStream();
    return _cachedRawStream!;
  }

  /// Stream of live full telemetry snapshots emitted by the native layer
  Stream<Map<String, dynamic>> get telemetryStream {
    return rawEventStream.where((event) =>
        event["type"] != "sensor_access" &&
        event["type"] != "media_access" &&
        event.isNotEmpty);
  }

  /// Stream of live real-time sensor access events emitted by the native layer
  Stream<Map<String, dynamic>> get sensorAccessStream {
    return rawEventStream
        .where((event) =>
            event["type"] == "sensor_access" ||
            event["type"] == "media_access")
        .map((event) {
      print('SENSOR_EVENT_RECEIVED_FLUTTER: sensor=${event["sensor"]} state=${event["state"]} pkg=${event["packageName"]}');
      print('''SENSOR_ACCESS_EVENT_RECEIVED:
sensor: ${event["sensor"]}
state: ${event["state"]}
packageName: ${event["packageName"]}
appName: ${event["appName"]}
timestamp: ${event["timestamp"]}
confidence: ${event["confidence"]}
attributionScope: ${event["attributionScope"]}
availability: ${event["availability"]}''');
      return event;
    });
  }

  /// Collects complete unified device telemetry from Android native layer
  Future<Map<String, dynamic>> collectTelemetry(
      {bool forceRefresh = false}) async {
    try {
      final result = await _channel.invokeMethod("getTelemetry", {
        "forceRefresh": forceRefresh,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      final errorHealthItem = {
        "status": "ERROR",
        "message": e.toString(),
        "sourceApi": "AndroidCollector",
        "lastSuccessTimestampMs": 0,
      };
      return {
        "error": e.toString(),
        "timestamp": DateTime.now().toIso8601String(),
        "apps": <dynamic>[],
        "usage": <dynamic>[],
        "network": <String, dynamic>{},
        "deviceContext": <String, dynamic>{},
        "deviceSecurity": <String, dynamic>{},
        "sensorTelemetry": <String, dynamic>{},
        "usageSummary": <String, dynamic>{},
        "telemetryHealth": {
          "permissions": errorHealthItem,
          "usage": errorHealthItem,
          "network": errorHealthItem,
          "security": errorHealthItem,
          "sensors": errorHealthItem,
          "deviceContext": errorHealthItem,
        },
      };
    }
  }

  /// Collects installed application list with real permissions and metadata
  Future<List<Map<String, dynamic>>> getInstalledApps(
      {bool forceRefresh = false}) async {
    try {
      final result = await _channel.invokeMethod("getInstalledApps", {
        "forceRefresh": forceRefresh,
      });
      if (result is List) {
        return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Collects usage statistics and events if permission is granted
  Future<Map<String, dynamic>> getUsageStats(
      {bool forceRefresh = false}) async {
    try {
      final result = await _channel.invokeMethod("getUsageStats", {
        "forceRefresh": forceRefresh,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {"usageAccessGranted": false, "error": e.toString()};
    }
  }

  /// Collects real-time device context (battery, screen, uptime, locale, power mode)
  Future<Map<String, dynamic>> getDeviceContext() async {
    try {
      final result = await _channel.invokeMethod("getDeviceContext");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  /// Collects device security signals (overlay, accessibility, vpn, developer options, root)
  Future<Map<String, dynamic>> getDeviceSecurity() async {
    try {
      final result = await _channel.invokeMethod("getDeviceSecurity");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  /// Collects network usage, transports, bandwidth, and metered status
  Future<Map<String, dynamic>> getNetworkTelemetry() async {
    try {
      final result = await _channel.invokeMethod("getNetworkTelemetry");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  /// Collects camera and microphone sensor hardware states
  Future<Map<String, dynamic>> getSensorTelemetry() async {
    try {
      final result = await _channel.invokeMethod("getSensorTelemetry");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  /// Collects structured health status across all major telemetry collectors
  Future<Map<String, dynamic>> getTelemetryHealth() async {
    try {
      final result = await _channel.invokeMethod("getTelemetryHealth");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  /// Checks whether Usage Stats access is granted by the user in system settings
  Future<bool> isUsageAccessGranted() async {
    try {
      final result = await _channel.invokeMethod("isUsageAccessGranted");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Android Usage Access Settings screen
  Future<bool> openUsageAccessSettings() async {
    try {
      final result = await _channel.invokeMethod("openUsageAccessSettings");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether overlay (SYSTEM_ALERT_WINDOW) permission is granted
  Future<bool> isOverlayPermissionGranted() async {
    try {
      final result = await _channel.invokeMethod("isOverlayPermissionGranted");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Android Overlay Permission settings screen for this app
  Future<bool> openOverlaySettings() async {
    try {
      final result = await _channel.invokeMethod("openOverlaySettings");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether battery optimization is ignored for this app
  Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final result =
          await _channel.invokeMethod("isBatteryOptimizationIgnored");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Android Battery Optimization Settings screen
  Future<bool> openBatteryOptimizationSettings() async {
    try {
      final result =
          await _channel.invokeMethod("openBatteryOptimizationSettings");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Starts the Android Telemetry Foreground Service
  Future<bool> startForegroundService() async {
    try {
      final result = await _channel.invokeMethod("startForegroundService");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Stops the Android Telemetry Foreground Service
  Future<bool> stopForegroundService() async {
    try {
      final result = await _channel.invokeMethod("stopForegroundService");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Checks if foreground service is actively running
  Future<bool> isForegroundServiceRunning() async {
    try {
      final result = await _channel.invokeMethod("isForegroundServiceRunning");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Gets foreground service state ("RUNNING", "STOPPED", "TIMEOUT", "START_FAILED")
  Future<String> getForegroundServiceState() async {
    try {
      final result = await _channel.invokeMethod("getForegroundServiceState");
      return result?.toString() ?? "STOPPED";
    } catch (_) {
      return "STOPPED";
    }
  }

  /// Gets foreground service health and execution limits
  Future<Map<String, dynamic>> getForegroundServiceHealth() async {
    try {
      final result = await _channel.invokeMethod("getForegroundServiceHealth");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Notifies native Android collector that a collection session has started
  Future<bool> startCollectionSession(String sessionId) async {
    try {
      final result = await _channel.invokeMethod("startCollectionSession", {
        "sessionId": sessionId,
      });
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Notifies native Android collector that a collection session has stopped
  Future<bool> stopCollectionSession() async {
    try {
      final result = await _channel.invokeMethod("stopCollectionSession");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves dynamic sensor monitoring capabilities detected on the current Android device
  Future<Map<String, dynamic>> getSensorCapabilities() async {
    try {
      final result = await _channel.invokeMethod("getSensorCapabilities");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  /// Triggers lightweight native current-state reconciliation without polling.
  Future<Map<String, dynamic>> reconcileSensorState() async {
    try {
      final result = await _channel.invokeMethod("reconcileSensorState");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  /// Checks POST_NOTIFICATIONS runtime permission state:
  /// GRANTED, DENIED, NOT_REQUESTED, UNAVAILABLE
  Future<String> checkNotificationPermission() async {
    try {
      final result = await _channel.invokeMethod<String>("checkNotificationPermission");
      return result ?? "UNAVAILABLE";
    } catch (_) {
      return "UNAVAILABLE";
    }
  }

  /// Requests POST_NOTIFICATIONS runtime permission
  Future<bool> requestNotificationPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>("requestNotificationPermission");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Checks notification channel state for privacy_sensor_alerts
  Future<Map<String, dynamic>> checkNotificationChannel([String channelId = "privacy_sensor_alerts"]) async {
    try {
      final result = await _channel.invokeMethod("checkNotificationChannel", {"channelId": channelId});
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {"exists": false, "disabled": true};
    } catch (_) {
      return {"exists": false, "disabled": true};
    }
  }

  /// Retrieves current Shizuku status, permission state, and Precise Mode configuration
  Future<Map<String, dynamic>> getShizukuStatus() async {
    try {
      final result = await _channel.invokeMethod("getShizukuStatus");
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        "state": "OFF",
        "lifecycleState": "SHIZUKU_UNAVAILABLE",
        "status": "Standard Monitoring",
        "isPreciseModeEnabled": false,
        "isShizukuAvailable": false,
        "hasPermission": false,
        "isServiceBound": false,
        "summary": "Uses standard Android privacy monitoring."
      };
    } catch (e) {
      return {
        "state": "ERROR",
        "lifecycleState": "SHIZUKU_ERROR",
        "status": "Standard Monitoring",
        "isPreciseModeEnabled": false,
        "isShizukuAvailable": false,
        "hasPermission": false,
        "isServiceBound": false,
        "summary": "Error querying Shizuku status: $e"
      };
    }
  }

  /// Sets whether user has opted into Precise App Attribution via Shizuku
  Future<bool> setPreciseModeEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod("setPreciseModeEnabled", {"enabled": enabled});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Explicitly requests Shizuku permission upon user action
  Future<bool> requestShizukuPermission() async {
    try {
      final result = await _channel.invokeMethod("requestShizukuPermission");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Launches or navigates to Shizuku application for user configuration
  Future<bool> openShizukuApp() async {
    try {
      final result = await _channel.invokeMethod("openShizukuApp");
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android system application details/permissions settings for target package
  Future<bool> openAppSettings(String packageName) async {
    try {
      final result = await _channel.invokeMethod("openAppSettings", {
        "packageName": packageName,
      });
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Phase 4 Action: Blocks camera or microphone permission for a verified app via UserService
  Future<Map<String, dynamic>> blockSensorAccess(String packageName, String sensor) async {
    try {
      final result = await _channel.invokeMethod("blockSensorAccess", {
        "packageName": packageName,
        "sensor": sensor,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {"success": false, "verified": false, "error": "Invalid response format"};
    } catch (e) {
      return {"success": false, "verified": false, "error": e.toString()};
    }
  }

  /// Phase 4 Action: Restores camera or microphone permission for an app via UserService
  Future<Map<String, dynamic>> restoreSensorAccess(String packageName, String sensor) async {
    try {
      final result = await _channel.invokeMethod("restoreSensorAccess", {
        "packageName": packageName,
        "sensor": sensor,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {"success": false, "verified": false, "error": "Invalid response format"};
    } catch (e) {
      return {"success": false, "verified": false, "error": e.toString()};
    }
  }

  /// Checks actual system permission state for a sensor
  Future<bool> checkSensorPermission(String packageName, String sensor) async {
    try {
      final result = await _channel.invokeMethod<bool>("checkSensorPermission", {
        "packageName": packageName,
        "sensor": sensor,
      });
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves user action audit log
  Future<List<Map<String, dynamic>>> getUserActionAuditLog() async {
    try {
      final result = await _channel.invokeMethod("getUserActionAuditLog");
      if (result is List) {
        return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Checks if spoken voice alerts (TTS aloud) are enabled
  Future<bool> isVoiceAlertsEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>("isVoiceAlertsEnabled");
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Updates whether spoken voice alerts (TTS aloud) are enabled or silent notification only
  Future<bool> setVoiceAlertsEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>("setVoiceAlertsEnabled", {
        "enabled": enabled,
      });
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Checks if visual sensor alert notifications are enabled
  Future<bool> isNotificationsEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>("isNotificationsEnabled");
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Updates whether visual sensor alert notifications are enabled
  Future<bool> setNotificationsEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>("setNotificationsEnabled", {
        "enabled": enabled,
      });
      return result ?? true;
    } catch (_) {
      return false;
    }
  }
}