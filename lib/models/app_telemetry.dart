/// Canonical Application-Level Telemetry Model for Mobile Device Layer.
/// 
/// Strictly contains ONLY app-specific attributes (package metadata, dynamic permission states,
/// AppOps, UsageStatsManager transitions, and NetworkStatsManager traffic).
/// 
/// Field Semantics:
/// - appName: String | Source: PackageManager.getApplicationLabel | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - packageName: String | Source: PackageInfo.packageName | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - isSystemApp: bool | Source: ApplicationInfo.FLAG_SYSTEM | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - isEnabled: bool | Source: ApplicationInfo.enabled | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - uid: int | Source: ApplicationInfo.uid | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - targetSdkVersion: int | Source: ApplicationInfo.targetSdkVersion | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - minSdkVersion: int | Source: ApplicationInfo.minSdkVersion | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - versionName: String | Source: PackageInfo.versionName | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - versionCode: int | Source: PackageInfo.versionCode/longVersionCode | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - firstInstallTime: int | Source: PackageInfo.firstInstallTime | Scope: APP | Raw: true | Time: Static ms | Availability: VALID
/// - lastUpdateTime: int | Source: PackageInfo.lastUpdateTime | Scope: APP | Raw: true | Time: Static ms | Availability: VALID
/// - installerPackage: String | Source: PackageManager.getInstallSourceInfo | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - requestedPermissions: `List<String>` | Source: PackageInfo.requestedPermissions | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - grantedPermissions: `List<String>` | Source: PackageInfo.requestedPermissionsFlags / checkPermission | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - deniedPermissions: `List<String>` | Source: Derived complement (requested - granted) | Scope: APP | Derived: true | Time: Static | Availability: VALID
/// - dangerousGrantedPermissions: `List<String>` | Source: PermissionInfo.PROTECTION_DANGEROUS (granted) | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - dangerousRequestedPermissions: `List<String>` | Source: PermissionInfo.PROTECTION_DANGEROUS (all requested) | Scope: APP | Raw: true | Time: Static | Availability: VALID
/// - hasOverlayOp: bool | Source: AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW | Scope: APP | Raw: true | Time: Real-time snapshot | Availability: VALID
/// - hasUsageAccessOp: bool | Source: AppOpsManager.OPSTR_GET_USAGE_STATS | Scope: APP | Raw: true | Time: Real-time snapshot | Availability: VALID
/// - foregroundDurationMs: int? | Source: UsageStatsManager.queryUsageStats | Scope: APP | Raw: true | Time: 24h Interval ms | Null when ERROR/RESTRICTED/UNAVAILABLE
/// - foregroundMinutes: double? | Source: Derived (foregroundDurationMs / 60000.0) | Scope: APP | Derived: true | Time: 24h Interval | Null when ERROR/RESTRICTED/UNAVAILABLE
/// - lastTimeUsedMs: int? | Source: UsageStatsManager.lastTimeUsed / UsageEvents | Scope: APP | Raw: true | Time: Epoch ms | Null when ERROR/RESTRICTED/UNAVAILABLE
/// - foregroundTransitionCount: int? | Source: UsageEvents (MOVE_TO_FOREGROUND/ACTIVITY_RESUMED) | Scope: APP | Raw: true | Time: 24h Interval | Null when ERROR/RESTRICTED/UNAVAILABLE
/// - isCurrentlyForeground: bool? | Source: UsageEvents latest transition state | Scope: APP | Raw: true | Time: Real-time snapshot | Null when ERROR/RESTRICTED/UNAVAILABLE
/// - isRecentlyUsedDerived: bool? | Source: Derived ((now - lastTimeUsedMs) < 5 min) | Scope: APP | Derived: true | Time: Real-time heuristic | Null when ERROR/RESTRICTED/UNAVAILABLE
/// - usageAvailability: String | Source: Permission / Service verification | Scope: APP | Status: VALID | ZERO_REPORTED | RESTRICTED | UNAVAILABLE | ERROR
/// - uploadBytes: int? | Source: NetworkStatsManager.querySummary (UID) | Scope: APP | Raw: true | Time: 24h Interval bytes | Null when ERROR/RESTRICTED/UNAVAILABLE
/// - downloadBytes: int? | Source: NetworkStatsManager.querySummary (UID) | Scope: APP | Raw: true | Time: 24h Interval bytes | Null when ERROR/RESTRICTED/UNAVAILABLE
/// - networkUsageAvailability: String | Source: NetworkStatsManager query status | Scope: APP | Status: VALID | ZERO_REPORTED | DENIED | RESTRICTED | UNAVAILABLE | ERROR
/// - networkUsageSource: String | Source: NetworkStatsManager | Scope: APP | Status: String
enum AppCategory {
  undefined,
  game,
  audio,
  video,
  image,
  social,
  news,
  maps,
  productivity,
  accessibility,
}

class AppTelemetry {
  final String appName;
  final String packageName;
  final bool isSystemApp;
  final bool isEnabled;
  final int uid;
  final int targetSdkVersion;
  final int minSdkVersion;
  final String versionName;
  final int versionCode;
  final int firstInstallTime;
  final int lastUpdateTime;
  final String installerPackage;
  final int appCategory;

  // Real dynamic permission classification from Android PackageManager
  final List<String> requestedPermissions;
  final List<String> grantedPermissions;
  final List<String> deniedPermissions;
  final List<String> dangerousGrantedPermissions;
  final List<String> dangerousRequestedPermissions;

  // Per-application AppOps
  final bool hasOverlayOp;
  final bool hasUsageAccessOp;

  // Legitimate UsageStats telemetry
  final double? foregroundMinutes;
  final int? foregroundDurationMs;
  final int? usageTodayMs;
  final int? visibleTimeMs;
  final int? foregroundServiceTimeMs;
  final int? lastTimeUsedMs;
  final int? lastUsedTimestamp;
  final int? foregroundTransitionCount;
  final bool? isCurrentlyForeground;
  final bool? isRecentlyUsedDerived;
  final String usageAvailability;
  final String usageDataState;

  // Per-application network stats (NetworkStatsManager)
  final int? uploadBytes;
  final int? downloadBytes;
  final String networkUsageAvailability;
  final String networkUsageSource;

  AppTelemetry({
    required this.appName,
    required this.packageName,
    this.isSystemApp = false,
    this.isEnabled = true,
    this.uid = -1,
    this.targetSdkVersion = 0,
    this.minSdkVersion = 0,
    this.versionName = "",
    this.versionCode = 0,
    this.firstInstallTime = 0,
    this.lastUpdateTime = 0,
    this.installerPackage = "",
    this.appCategory = -1,
    List<String>? requestedPermissions,
    List<String>? permissions,
    this.grantedPermissions = const [],
    this.deniedPermissions = const [],
    List<String>? dangerousGrantedPermissions,
    List<String>? dangerousPermissions,
    this.dangerousRequestedPermissions = const [],
    this.hasOverlayOp = false,
    this.hasUsageAccessOp = false,
    this.foregroundMinutes,
    this.foregroundDurationMs,
    this.usageTodayMs,
    this.visibleTimeMs,
    this.foregroundServiceTimeMs,
    this.lastTimeUsedMs,
    this.lastUsedTimestamp,
    this.foregroundTransitionCount,
    this.isCurrentlyForeground,
    this.isRecentlyUsedDerived,
    this.usageAvailability = "UNKNOWN",
    this.usageDataState = "UNKNOWN",
    this.uploadBytes,
    this.downloadBytes,
    this.networkUsageAvailability = "UNKNOWN",
    this.networkUsageSource = "UNKNOWN",
  })  : requestedPermissions = requestedPermissions ?? permissions ?? const [],
        dangerousGrantedPermissions = dangerousGrantedPermissions ??
            dangerousPermissions ??
            const [];

  AppCategory get category {
    switch (appCategory) {
      case 0:
        return AppCategory.game;
      case 1:
        return AppCategory.audio;
      case 2:
        return AppCategory.video;
      case 3:
        return AppCategory.image;
      case 4:
        return AppCategory.social;
      case 5:
        return AppCategory.news;
      case 6:
        return AppCategory.maps;
      case 7:
        return AppCategory.productivity;
      case 8:
        return AppCategory.accessibility;
      default:
        return AppCategory.undefined;
    }
  }

  /// Backward-compatible clean accessors for FeatureEncoder, UI widgets, and legacy callers
  List<String> get permissions => requestedPermissions;
  List<String> get dangerousPermissions => dangerousGrantedPermissions;
  bool? get isActive => isRecentlyUsedDerived;
  bool get hasOverlayPermission => hasOverlayOp;
  bool get hasUsageAccessPermission => hasUsageAccessOp;
  int? get foregroundTimeMs => foregroundDurationMs;
  int? get foregroundTime => foregroundDurationMs;
  int? get launchCount => foregroundTransitionCount;
  bool get isNetworkStatsAvailable =>
      networkUsageAvailability == "VALID" ||
      networkUsageAvailability == "ZERO_REPORTED";
  bool get isUsageStatsAvailable =>
      usageAvailability == "VALID" ||
      usageAvailability == "ZERO_REPORTED" ||
      usageDataState == "AVAILABLE";

  String get usageTodayFormatted {
    if (usageDataState == 'USAGE_DATA_UNAVAILABLE' || usageAvailability == 'USAGE_DATA_UNAVAILABLE') {
      return 'Usage Access Required';
    }
    if (usageDataState == 'UNAVAILABLE' || usageAvailability == 'UNAVAILABLE') {
      return 'Unavailable';
    }
    final ms = usageTodayMs ?? foregroundDurationMs;
    if (ms == null) return 'Unavailable';
    return formatDuration(ms);
  }

  static String formatDuration(int ms) {
    if (ms <= 0) return '0m';
    final seconds = (ms / 1000).round();
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours > 0) {
      return remainingMinutes > 0 ? '${hours}h ${remainingMinutes}m' : '${hours}h';
    }
    return '${minutes}m';
  }

  String get lastUsedFormatted {
    final ts = lastUsedTimestamp ?? lastTimeUsedMs;
    if (ts == null || ts <= 0) return 'Not used today';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24 && dt.day == now.day) {
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $period';
    }
    return '${dt.day}/${dt.month}';
  }

  Map<String, dynamic> toJson() {
    return {
      "appName": appName,
      "packageName": packageName,
      "isSystemApp": isSystemApp,
      "isEnabled": isEnabled,
      "uid": uid,
      "targetSdkVersion": targetSdkVersion,
      "minSdkVersion": minSdkVersion,
      "versionName": versionName,
      "versionCode": versionCode,
      "firstInstallTime": firstInstallTime,
      "lastUpdateTime": lastUpdateTime,
      "installerPackage": installerPackage,
      "appCategory": appCategory,
      "requestedPermissions": requestedPermissions,
      "grantedPermissions": grantedPermissions,
      "deniedPermissions": deniedPermissions,
      "dangerousGrantedPermissions": dangerousGrantedPermissions,
      "dangerousRequestedPermissions": dangerousRequestedPermissions,
      "hasOverlayOp": hasOverlayOp,
      "hasUsageAccessOp": hasUsageAccessOp,
      "foregroundMinutes": foregroundMinutes,
      "foregroundDurationMs": foregroundDurationMs,
      "usageTodayMs": usageTodayMs,
      "visibleTimeMs": visibleTimeMs,
      "foregroundServiceTimeMs": foregroundServiceTimeMs,
      "lastTimeUsedMs": lastTimeUsedMs,
      "lastUsedTimestamp": lastUsedTimestamp,
      "foregroundTransitionCount": foregroundTransitionCount,
      "isCurrentlyForeground": isCurrentlyForeground,
      "isRecentlyUsedDerived": isRecentlyUsedDerived,
      "usageAvailability": usageAvailability,
      "usageDataState": usageDataState,
      "usageTodayFormatted": usageTodayFormatted,
      "lastUsedFormatted": lastUsedFormatted,
      "uploadBytes": uploadBytes,
      "downloadBytes": downloadBytes,
      "networkUsageAvailability": networkUsageAvailability,
      "networkUsageSource": networkUsageSource,
    };
  }
}