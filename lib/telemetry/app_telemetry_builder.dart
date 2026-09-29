import '../models/app_telemetry.dart';
import '../models/privacy_event.dart';

class AppTelemetryBuilder {
  List<AppTelemetry> build(PrivacyEvent telemetry) {
    final List<AppTelemetry> result = [];

    for (final rawApp in telemetry.apps) {
      if (rawApp is! Map) continue;
      final app = Map<String, dynamic>.from(rawApp);

      final String packageName = app["packageName"]?.toString() ?? "";
      if (packageName.isEmpty) continue;

      final String appName = app["appName"]?.toString() ?? packageName;
      final bool isSystemApp = app["isSystemApp"] == true;
      final bool isEnabled = app["isEnabled"] != false;
      final int uid = (app["uid"] as num?)?.toInt() ?? -1;
      final int targetSdkVersion =
          (app["targetSdkVersion"] as num?)?.toInt() ?? 0;
      final int minSdkVersion =
          (app["minSdkVersion"] as num?)?.toInt() ?? 0;
      final String versionName = app["versionName"]?.toString() ?? "";
      final int versionCode = (app["versionCode"] as num?)?.toInt() ?? 0;
      final int firstInstallTime =
          (app["firstInstallTime"] as num?)?.toInt() ?? 0;
      final int lastUpdateTime = (app["lastUpdateTime"] as num?)?.toInt() ?? 0;
      final String installerPackage =
          app["installerPackage"]?.toString() ?? "";
      final int appCategory = (app["appCategory"] as num?)?.toInt() ?? -1;

      final List<String> requestedPermissions =
          List<String>.from(app["requestedPermissions"] ?? []);
      final List<String> grantedPermissions =
          List<String>.from(app["grantedPermissions"] ?? []);
      final List<String> deniedPermissions =
          List<String>.from(app["deniedPermissions"] ?? []);
      final List<String> dangerousGrantedPermissions =
          List<String>.from(app["dangerousGrantedPermissions"] ?? []);
      final List<String> dangerousRequestedPermissions =
          List<String>.from(app["dangerousRequestedPermissions"] ?? []);

      final bool hasOverlayOp = app["hasOverlayOp"] == true;
      final bool hasUsageAccessOp = app["hasUsageAccessOp"] == true;

      // Legitimate UsageStats values
      final double? foregroundMinutes =
          (app["foregroundMinutes"] as num?)?.toDouble();
      final int? foregroundDurationMs =
          (app["foregroundDurationMs"] as num?)?.toInt();
      final int? usageTodayMs = (app["usageTodayMs"] as num?)?.toInt() ?? foregroundDurationMs;
      final int? visibleTimeMs = (app["visibleTimeMs"] as num?)?.toInt();
      final int? foregroundServiceTimeMs =
          (app["foregroundServiceTimeMs"] as num?)?.toInt();
      final int? lastTimeUsedMs = (app["lastTimeUsedMs"] as num?)?.toInt();
      final int? lastUsedTimestamp =
          (app["lastUsedTimestamp"] as num?)?.toInt() ?? lastTimeUsedMs;
      final int? foregroundTransitionCount =
          (app["foregroundTransitionCount"] as num?)?.toInt();
      final bool? isCurrentlyForeground = app["isCurrentlyForeground"] is bool
          ? app["isCurrentlyForeground"] as bool
          : null;
      final bool? isRecentlyUsedDerived = app["isRecentlyUsedDerived"] is bool
          ? app["isRecentlyUsedDerived"] as bool
          : null;
      final String usageAvailability =
          app["usageAvailability"]?.toString() ?? "UNKNOWN";
      final String usageDataState =
          app["usageDataState"]?.toString() ?? usageAvailability;

      // Real per-UID network traffic from NetworkStatsManager (null on error/restricted/unavailable)
      final int? uploadBytes = (app["uploadBytes"] as num?)?.toInt();
      final int? downloadBytes = (app["downloadBytes"] as num?)?.toInt();
      final String netAvailability =
          app["networkUsageAvailability"]?.toString() ?? "UNKNOWN";
      final String netSource =
          app["networkUsageSource"]?.toString() ?? "UNKNOWN";

      result.add(
        AppTelemetry(
          appName: appName,
          packageName: packageName,
          isSystemApp: isSystemApp,
          isEnabled: isEnabled,
          uid: uid,
          targetSdkVersion: targetSdkVersion,
          minSdkVersion: minSdkVersion,
          versionName: versionName,
          versionCode: versionCode,
          firstInstallTime: firstInstallTime,
          lastUpdateTime: lastUpdateTime,
          installerPackage: installerPackage,
          appCategory: appCategory,
          requestedPermissions: requestedPermissions,
          grantedPermissions: grantedPermissions,
          deniedPermissions: deniedPermissions,
          dangerousGrantedPermissions: dangerousGrantedPermissions,
          dangerousRequestedPermissions: dangerousRequestedPermissions,
          hasOverlayOp: hasOverlayOp,
          hasUsageAccessOp: hasUsageAccessOp,
          foregroundMinutes: foregroundMinutes,
          foregroundDurationMs: foregroundDurationMs,
          usageTodayMs: usageTodayMs,
          visibleTimeMs: visibleTimeMs,
          foregroundServiceTimeMs: foregroundServiceTimeMs,
          lastTimeUsedMs: lastTimeUsedMs,
          lastUsedTimestamp: lastUsedTimestamp,
          foregroundTransitionCount: foregroundTransitionCount,
          isCurrentlyForeground: isCurrentlyForeground,
          isRecentlyUsedDerived: isRecentlyUsedDerived,
          usageAvailability: usageAvailability,
          usageDataState: usageDataState,
          uploadBytes: uploadBytes,
          downloadBytes: downloadBytes,
          networkUsageAvailability: netAvailability,
          networkUsageSource: netSource,
        ),
      );
    }

    return result;
  }
}