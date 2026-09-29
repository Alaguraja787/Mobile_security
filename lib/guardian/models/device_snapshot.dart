import '../../models/app_telemetry.dart';
import '../../services/permission_intelligence_analyzer.dart';

/// Canonical Status for Permissions
enum PermissionStatus {
  granted,
  denied,
  restricted,
  unavailable,
  unknown,
  error,
}

/// Detailed Permission Record preserving Android platform states
class PermissionRecord {
  final String name;
  final String simpleName;
  final PermissionStatus status;
  final bool isDangerous;
  final String protectionLevel;
  final String group;
  final bool isRequested;
  final bool isGranted;
  final String? usageEvidence;

  PermissionRecord({
    required this.name,
    required this.simpleName,
    required this.status,
    required this.isDangerous,
    this.protectionLevel = 'DANGEROUS',
    this.group = 'CORE',
    required this.isRequested,
    required this.isGranted,
    this.usageEvidence,
  });

  String get permissionName => name;

  Map<String, dynamic> toJson() => {
        'name': name,
        'simpleName': simpleName,
        'status': status.name.toUpperCase(),
        'isDangerous': isDangerous,
        'protectionLevel': protectionLevel,
        'group': group,
        'isRequested': isRequested,
        'isGranted': isGranted,
        if (usageEvidence != null) 'usageEvidence': usageEvidence,
      };
}

/// Structured Canonical Application Usage Summary
class UsageSummary {
  final int todayForegroundMs;
  final int? todayVisibleMs;
  final int? todayForegroundServiceMs;
  final DateTime? lastUsedAt;
  final int? lastUsedTimestampMs;
  final String usageState; // AVAILABLE, USAGE_DATA_UNAVAILABLE, UNAVAILABLE, ERROR, UNKNOWN
  final String todayForegroundFormatted;
  final String lastUsedFormatted;

  UsageSummary({
    required this.todayForegroundMs,
    this.todayVisibleMs,
    this.todayForegroundServiceMs,
    this.lastUsedAt,
    this.lastUsedTimestampMs,
    required this.usageState,
    required this.todayForegroundFormatted,
    required this.lastUsedFormatted,
  });

  bool get isAvailable =>
      usageState == 'AVAILABLE' ||
      usageState == 'GRANTED/AVAILABLE' ||
      usageState == 'VALID';

  bool get isUsedToday => todayForegroundMs > 0;

  Map<String, dynamic> toJson() => {
        'todayForegroundMs': todayForegroundMs,
        'todayVisibleMs': todayVisibleMs,
        'todayForegroundServiceMs': todayForegroundServiceMs,
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'lastUsedTimestampMs': lastUsedTimestampMs,
        'usageState': usageState,
        'todayForegroundFormatted': todayForegroundFormatted,
        'lastUsedFormatted': lastUsedFormatted,
      };

  factory UsageSummary.fromTelemetry(AppTelemetry app) {
    final ms = app.usageTodayMs ?? app.foregroundDurationMs ?? 0;
    final lastTs = app.lastUsedTimestamp ?? app.lastTimeUsedMs;
    final state = app.usageDataState != 'UNKNOWN'
        ? app.usageDataState
        : (app.usageAvailability != 'UNKNOWN'
            ? app.usageAvailability
            : 'UNKNOWN');

    return UsageSummary(
      todayForegroundMs: ms,
      todayVisibleMs: app.visibleTimeMs,
      todayForegroundServiceMs: app.foregroundServiceTimeMs,
      lastUsedAt: lastTs != null && lastTs > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastTs)
          : null,
      lastUsedTimestampMs: lastTs,
      usageState: state,
      todayForegroundFormatted: app.usageTodayFormatted,
      lastUsedFormatted: app.lastUsedFormatted,
    );
  }
}

/// Rich Application Profile extracted from Android PackageManager
class ApplicationProfile {
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
  final AppCategory category;

  final List<PermissionRecord> permissions;
  final bool hasOverlayOp;
  final bool hasUsageAccessOp;
  final PermissionRiskResult? riskSummary;
  final UsageSummary usageSummary;

  ApplicationProfile({
    required this.appName,
    required this.packageName,
    required this.isSystemApp,
    required this.isEnabled,
    required this.uid,
    required this.targetSdkVersion,
    required this.minSdkVersion,
    required this.versionName,
    required this.versionCode,
    required this.firstInstallTime,
    required this.lastUpdateTime,
    required this.installerPackage,
    required this.category,
    required this.permissions,
    required this.hasOverlayOp,
    required this.hasUsageAccessOp,
    this.riskSummary,
    required this.usageSummary,
  });

  List<PermissionRecord> get grantedPermissions =>
      permissions.where((p) => p.isGranted).toList();

  String get riskLevel => riskSummary?.levelLabel ?? 'NORMAL';

  bool hasPermission(String permSnippet, {bool grantedOnly = true}) {
    final needle = permSnippet.toUpperCase();
    return permissions.any((p) {
      final nameUp = p.name.toUpperCase();
      final simpleUp = p.simpleName.toUpperCase();
      bool matches = nameUp.contains(needle) || simpleUp.contains(needle);
      if (!matches && (needle == 'RECORD_AUDIO' || needle == 'MICROPHONE')) {
        matches = nameUp.contains('AUDIO') ||
            simpleUp.contains('AUDIO') ||
            nameUp.contains('MIC') ||
            simpleUp.contains('MIC');
      }
      return matches && (!grantedOnly || p.isGranted);
    });
  }

  factory ApplicationProfile.fromTelemetry(
    AppTelemetry app, [
    PermissionIntelligenceAnalyzer? analyzer,
  ]) {
    final List<PermissionRecord> records = [];
    final allPerms = <String>{...app.requestedPermissions, ...app.grantedPermissions}.toList();

    for (final perm in allPerms) {
      final isGranted = app.grantedPermissions.contains(perm);
      final isDangerous = app.dangerousGrantedPermissions.contains(perm) ||
          app.dangerousRequestedPermissions.contains(perm);

      final simple = perm.contains('.') ? perm.split('.').last : perm;

      records.add(PermissionRecord(
        name: perm,
        simpleName: simple,
        status: isGranted ? PermissionStatus.granted : PermissionStatus.denied,
        isDangerous: isDangerous,
        protectionLevel: isDangerous ? 'DANGEROUS' : 'NORMAL',
        group: _inferGroup(simple),
        isRequested: true,
        isGranted: isGranted,
      ));
    }

    final risk = analyzer?.analyzeApp(app);
    final usage = UsageSummary.fromTelemetry(app);

    return ApplicationProfile(
      appName: app.appName,
      packageName: app.packageName,
      isSystemApp: app.isSystemApp,
      isEnabled: app.isEnabled,
      uid: app.uid,
      targetSdkVersion: app.targetSdkVersion,
      minSdkVersion: app.minSdkVersion,
      versionName: app.versionName,
      versionCode: app.versionCode,
      firstInstallTime: app.firstInstallTime,
      lastUpdateTime: app.lastUpdateTime,
      installerPackage: app.installerPackage,
      category: app.category,
      permissions: records,
      hasOverlayOp: app.hasOverlayOp,
      hasUsageAccessOp: app.hasUsageAccessOp,
      riskSummary: risk,
      usageSummary: usage,
    );
  }

  static String _inferGroup(String simplePerm) {
    final u = simplePerm.toUpperCase();
    if (u.contains('CAMERA')) return 'CAMERA';
    if (u.contains('RECORD_AUDIO') || u.contains('MICROPHONE')) return 'MICROPHONE';
    if (u.contains('LOCATION')) return 'LOCATION';
    if (u.contains('CONTACTS')) return 'CONTACTS';
    if (u.contains('STORAGE') || u.contains('MEDIA')) return 'STORAGE';
    if (u.contains('PHONE') || u.contains('SMS') || u.contains('CALL')) return 'TELEPHONY';
    return 'GENERAL';
  }
}

/// Canonical Device Snapshot representing the entire state of discovered device applications
class DeviceSnapshot {
  final DateTime timestamp;
  final List<ApplicationProfile> applications;
  final int totalDiscoveredApps;
  final int totalPermissionsCount;

  // Local Usage Index: packageName -> UsageSummary
  late final Map<String, UsageSummary> usageByPackage = {
    for (final app in applications) app.packageName: app.usageSummary,
  };

  DeviceSnapshot({
    required this.timestamp,
    required this.applications,
  })  : totalDiscoveredApps = applications.length,
        totalPermissionsCount = applications.fold(
            0, (sum, a) => sum + a.permissions.length);

  int get highRiskAppsCount => applications
      .where((a) => a.riskLevel == 'HIGH' || a.riskLevel == 'CRITICAL')
      .length;

  int get totalUniquePermissionsAcrossDevice {
    final unique = <String>{};
    for (final app in applications) {
      for (final p in app.permissions) {
        unique.add(p.permissionName);
      }
    }
    return unique.length;
  }

  factory DeviceSnapshot.fromAppTelemetryList(
    List<AppTelemetry> apps, [
    PermissionIntelligenceAnalyzer? analyzer,
  ]) {
    final profiles = apps.map((a) => ApplicationProfile.fromTelemetry(a, analyzer)).toList();
    return DeviceSnapshot(
      timestamp: DateTime.now(),
      applications: profiles,
    );
  }

  bool get isUsageAccessGranted =>
      applications.any((a) =>
          a.usageSummary.usageState != 'USAGE_DATA_UNAVAILABLE' &&
          a.usageSummary.usageState != 'RESTRICTED' &&
          a.usageSummary.usageState != 'UNAVAILABLE');

  int get totalForegroundTimeTodayMs => applications.fold(
      0, (sum, a) => sum + a.usageSummary.todayForegroundMs);

  String get totalForegroundTimeTodayFormatted =>
      AppTelemetry.formatDuration(totalForegroundTimeTodayMs);

  List<ApplicationProfile> getUsedAppsToday() {
    final used = applications
        .where((a) => a.usageSummary.todayForegroundMs > 0)
        .toList();
    used.sort((a, b) =>
        b.usageSummary.todayForegroundMs.compareTo(a.usageSummary.todayForegroundMs));
    return used;
  }

  List<ApplicationProfile> getUnusedAppsToday() {
    return applications
        .where((a) => a.usageSummary.todayForegroundMs == 0)
        .toList();
  }

  List<ApplicationProfile> getTopUsedApps({int limit = 5}) {
    final used = getUsedAppsToday();
    return used.take(limit).toList();
  }

  ApplicationProfile? getLastUsedApp() {
    ApplicationProfile? latestApp;
    int maxTs = 0;
    for (final app in applications) {
      final ts = app.usageSummary.lastUsedTimestampMs ?? 0;
      if (ts > maxTs) {
        maxTs = ts;
        latestApp = app;
      }
    }
    return latestApp;
  }

  List<ApplicationProfile> findAppsWithPermission(String permSnippet, {bool grantedOnly = true}) {
    return applications
        .where((a) => a.hasPermission(permSnippet, grantedOnly: grantedOnly))
        .toList();
  }

  ApplicationProfile? findAppByNameOrPackage(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;

    // Exact package match
    for (final app in applications) {
      if (app.packageName.toLowerCase() == q) return app;
    }
    // Exact label match
    for (final app in applications) {
      if (app.appName.toLowerCase() == q) return app;
    }
    // Substring match
    for (final app in applications) {
      if (app.packageName.toLowerCase().contains(q) ||
          app.appName.toLowerCase().contains(q)) {
        return app;
      }
    }
    return null;
  }
}
