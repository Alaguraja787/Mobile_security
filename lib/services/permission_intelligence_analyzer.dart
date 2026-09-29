import '../models/app_telemetry.dart';

enum PermissionRiskLevel {
  expected,
  low,
  normal,
  review,
  high,
  critical,
  attention,
}

class PermissionRiskResult {
  final AppTelemetry app;
  final PermissionRiskLevel level;
  final int riskScore; // 0 to 100 (0 = completely expected/safe, 100 = verified critical threat)
  final List<FlaggedPermission> flaggedPermissions;
  final String summaryReason;
  final List<String> contextualInferences;

  PermissionRiskResult({
    required this.app,
    required this.level,
    required this.riskScore,
    required this.flaggedPermissions,
    required this.summaryReason,
    required this.contextualInferences,
  });

  String get levelLabel {
    switch (level) {
      case PermissionRiskLevel.expected:
        return 'EXPECTED';
      case PermissionRiskLevel.low:
      case PermissionRiskLevel.normal:
        return 'LOW';
      case PermissionRiskLevel.review:
        return 'REVIEW';
      case PermissionRiskLevel.high:
      case PermissionRiskLevel.attention:
        return 'HIGH';
      case PermissionRiskLevel.critical:
        return 'CRITICAL';
    }
  }

  String get levelEmoji {
    switch (level) {
      case PermissionRiskLevel.expected:
      case PermissionRiskLevel.low:
      case PermissionRiskLevel.normal:
        return '🟢';
      case PermissionRiskLevel.review:
        return '🟡';
      case PermissionRiskLevel.high:
      case PermissionRiskLevel.attention:
        return '🟠';
      case PermissionRiskLevel.critical:
        return '🔴';
    }
  }
}

class FlaggedPermission {
  final String permission;
  final String category;
  final bool isGranted;
  final String sensitivityReason;
  final String relevance; // EXPECTED, RELEVANT, REVIEW, SUSPICIOUS

  FlaggedPermission({
    required this.permission,
    required this.category,
    required this.isGranted,
    required this.sensitivityReason,
    this.relevance = 'REVIEW',
  });
}

class DevicePrivacyScoreBreakdown {
  final int overallScore;
  final int expectedCount;
  final int lowCount;
  final int reviewCount;
  final int highCount;
  final int criticalCount;
  final int totalApps;
  final int criticalPenalty;
  final int highPenalty;
  final int reviewPenalty;

  DevicePrivacyScoreBreakdown({
    required this.overallScore,
    required this.expectedCount,
    required this.lowCount,
    required this.reviewCount,
    required this.highCount,
    required this.criticalCount,
    required this.totalApps,
    required this.criticalPenalty,
    required this.highPenalty,
    required this.reviewPenalty,
  });
}

/// Context-Aware Permission Intelligence Analyzer.
/// 
/// Evaluates:
/// Permission capability groups + App purpose/category + Relevance +
/// System baseline + Suspicious combos -> Contextual Risk
/// 
/// Core Principle: Sensitive permission granted != CRITICAL or HIGH.
/// Expected permissions for category are scored conservatively.
class PermissionIntelligenceAnalyzer {
  /// Analyzes an application's telemetry and returns a structured contextual risk evaluation.
  PermissionRiskResult analyzeApp(AppTelemetry app) {
    final List<FlaggedPermission> flagged = [];
    final List<String> inferences = [];
    int baseScore = 0;

    final AppCategory category = app.category;
    final bool isUtility = _isUtilityApp(app, category);

    // 1. Group Granted Permissions by Functional Capability
    bool hasMic = false;
    bool hasCam = false;
    bool hasContacts = false;
    bool hasLocation = false;
    bool hasTelephonySms = false;
    bool hasStorage = false;

    for (final perm in app.grantedPermissions) {
      final permUpper = perm.toUpperCase();
      if (permUpper.contains('RECORD_AUDIO') || permUpper.contains('MICROPHONE')) {
        hasMic = true;
      } else if (permUpper.contains('CAMERA')) {
        hasCam = true;
      } else if (permUpper.contains('CONTACTS') || permUpper.contains('GET_ACCOUNTS')) {
        hasContacts = true;
      } else if (permUpper.contains('LOCATION')) {
        hasLocation = true;
      } else if (permUpper.contains('SMS') ||
          permUpper.contains('CALL_LOG') ||
          permUpper.contains('OUTGOING_CALLS') ||
          permUpper.contains('READ_PHONE_STATE') ||
          permUpper.contains('CALL_PHONE')) {
        hasTelephonySms = true;
      } else if (permUpper.contains('STORAGE') || permUpper.contains('READ_MEDIA')) {
        hasStorage = true;
      }
    }

    // 2. Evaluate Special AppOps Privileges
    if (app.hasOverlayOp) {
      final bool isExpectedOverlay = app.isSystemApp || category == AppCategory.social;
      final int weight = isExpectedOverlay ? 5 : (isUtility ? 25 : 15);
      baseScore += weight;
      flagged.add(FlaggedPermission(
        permission: 'SYSTEM_ALERT_WINDOW (Overlay)',
        category: 'SYSTEM_OVERLAY',
        isGranted: true,
        sensitivityReason: 'Overlay permission allows displaying content over other applications.',
        relevance: isExpectedOverlay ? 'RELEVANT' : 'REVIEW',
      ));
      inferences.add('App has active System Alert Window (Overlay) privilege.');
    }

    if (app.hasUsageAccessOp) {
      baseScore += 5;
      flagged.add(FlaggedPermission(
        permission: 'PACKAGE_USAGE_STATS',
        category: 'USAGE_TRACKING',
        isGranted: true,
        sensitivityReason: 'Usage access allows inspecting application execution history.',
        relevance: 'REVIEW',
      ));
      inferences.add('App has access to system package usage statistics.');
    }

    // 3. Evaluate Capability Groups (Assessed ONCE per functional capability)
    if (hasMic) {
      final bool isExpected = category == AppCategory.audio ||
          category == AppCategory.video ||
          category == AppCategory.social;
      final int weight = isExpected ? 4 : (isUtility ? 25 : 10);
      baseScore += weight;
      flagged.add(FlaggedPermission(
        permission: 'RECORD_AUDIO',
        category: 'MICROPHONE',
        isGranted: true,
        sensitivityReason: isExpected
            ? 'Microphone access is standard for audio, video, or communication features.'
            : (isUtility
                ? 'Microphone access on a utility app. Verify if voice input is needed.'
                : 'Microphone permission enabled for audio capture features.'),
        relevance: isExpected ? 'EXPECTED' : 'REVIEW',
      ));
    }

    if (hasCam) {
      final bool isExpected = category == AppCategory.image ||
          category == AppCategory.video ||
          category == AppCategory.social;
      final int weight = isExpected ? 4 : (isUtility ? 25 : 10);
      baseScore += weight;
      flagged.add(FlaggedPermission(
        permission: 'CAMERA',
        category: 'CAMERA',
        isGranted: true,
        sensitivityReason: isExpected
            ? 'Camera access matches photo, video, or video calling functionality.'
            : (isUtility
                ? 'Camera access on a utility app. Review camera necessity.'
                : 'Camera hardware access enabled for image/video features.'),
        relevance: isExpected ? 'EXPECTED' : 'REVIEW',
      ));
    }

    if (hasContacts) {
      final bool isExpected = category == AppCategory.social || category == AppCategory.productivity;
      final int weight = isExpected ? 5 : (isUtility ? 25 : 12);
      baseScore += weight;
      flagged.add(FlaggedPermission(
        permission: 'READ_CONTACTS',
        category: 'CONTACTS',
        isGranted: true,
        sensitivityReason: isExpected
            ? 'Contacts permission enabled for user directory or communication lookup.'
            : 'Address book access granted. Review contact synchronization need.',
        relevance: isExpected ? 'EXPECTED' : 'REVIEW',
      ));
    }

    if (hasLocation) {
      final bool isExpected = category == AppCategory.maps;
      final int weight = isExpected ? 4 : (isUtility ? 20 : 10);
      baseScore += weight;
      flagged.add(FlaggedPermission(
        permission: 'LOCATION',
        category: 'LOCATION',
        isGranted: true,
        sensitivityReason: isExpected
            ? 'Location tracking is expected for navigation and mapping.'
            : 'Geographical location access enabled.',
        relevance: isExpected ? 'EXPECTED' : 'REVIEW',
      ));
    }

    if (hasTelephonySms) {
      final bool isExpected = category == AppCategory.social || app.isSystemApp;
      final int weight = isExpected ? 5 : (isUtility ? 30 : 15);
      baseScore += weight;
      flagged.add(FlaggedPermission(
        permission: 'TELEPHONY_SMS',
        category: 'SMS_CALLS',
        isGranted: true,
        sensitivityReason: isExpected
            ? 'Telephony/SMS capabilities consistent with communication application.'
            : 'Telephony or SMS privileges enabled.',
        relevance: isExpected ? 'EXPECTED' : 'REVIEW',
      ));
    }

    if (hasStorage) {
      final bool isExpected = category == AppCategory.image ||
          category == AppCategory.video ||
          category == AppCategory.audio ||
          category == AppCategory.productivity ||
          category == AppCategory.social;
      final int weight = isExpected ? 2 : 6;
      baseScore += weight;
      flagged.add(FlaggedPermission(
        permission: 'STORAGE_MEDIA',
        category: 'STORAGE',
        isGranted: true,
        sensitivityReason: isExpected
            ? 'Media/file storage access matches media handling purpose.'
            : 'File system or media library access granted.',
        relevance: isExpected ? 'EXPECTED' : 'REVIEW',
      ));
    }

    // 4. Evaluate Verified Suspicious Combinations (Combo Exploits)
    if (app.hasOverlayOp && !app.isSystemApp && (hasMic || hasCam || hasTelephonySms) && category != AppCategory.social) {
      baseScore += 25;
      inferences.add('Anomalous combination: Overlay active with background sensor or telephony permissions.');
    }

    // 5. System Package Baseline Adjustment
    if (app.isSystemApp) {
      baseScore = (baseScore * 0.35).round();
      inferences.add('Core platform package: operational baseline dampening applied.');
    }

    final int finalScore = baseScore.clamp(0, 100);

    PermissionRiskLevel level;
    String summary;

    if (finalScore >= 75) {
      level = PermissionRiskLevel.high;
      summary = 'High accumulation of anomalous permissions requiring privacy review.';
    } else if (finalScore >= 50) {
      level = PermissionRiskLevel.review;
      summary = 'Sensitive permissions granted that warrant review based on your usage patterns.';
    } else if (finalScore >= 25) {
      level = PermissionRiskLevel.low;
      summary = 'Permissions granted appear consistent with normal application behavior.';
    } else {
      level = PermissionRiskLevel.expected;
      summary = 'Permissions are standard and expected for this application category.';
    }

    return PermissionRiskResult(
      app: app,
      level: level,
      riskScore: finalScore,
      flaggedPermissions: flagged,
      summaryReason: summary,
      contextualInferences: inferences,
    );
  }

  /// Calculates detailed breakdown of device privacy health findings.
  DevicePrivacyScoreBreakdown calculateDevicePrivacyScoreBreakdown(List<PermissionRiskResult> results) {
    if (results.isEmpty) {
      return DevicePrivacyScoreBreakdown(
        overallScore: 100,
        expectedCount: 0,
        lowCount: 0,
        reviewCount: 0,
        highCount: 0,
        criticalCount: 0,
        totalApps: 0,
        criticalPenalty: 0,
        highPenalty: 0,
        reviewPenalty: 0,
      );
    }

    int expectedCount = 0;
    int lowCount = 0;
    int reviewCount = 0;
    int highCount = 0;
    int criticalCount = 0;

    for (final res in results) {
      switch (res.level) {
        case PermissionRiskLevel.critical:
          criticalCount++;
          break;
        case PermissionRiskLevel.high:
        case PermissionRiskLevel.attention:
          highCount++;
          break;
        case PermissionRiskLevel.review:
          reviewCount++;
          break;
        case PermissionRiskLevel.low:
        case PermissionRiskLevel.normal:
          lowCount++;
          break;
        case PermissionRiskLevel.expected:
          expectedCount++;
          break;
      }
    }

    // Proportional penalty calculation (never clamp artificially at 20)
    final int criticalPenalty = (criticalCount * 15).clamp(0, 45);
    final int highPenalty = (highCount * 5).clamp(0, 30);
    final int reviewPenalty = (reviewCount * 1).clamp(0, 15);

    final int score = (100 - criticalPenalty - highPenalty - reviewPenalty).clamp(0, 100);

    return DevicePrivacyScoreBreakdown(
      overallScore: score,
      expectedCount: expectedCount,
      lowCount: lowCount,
      reviewCount: reviewCount,
      highCount: highCount,
      criticalCount: criticalCount,
      totalApps: results.length,
      criticalPenalty: criticalPenalty,
      highPenalty: highPenalty,
      reviewPenalty: reviewPenalty,
    );
  }

  /// Calculates overall dynamic device privacy score (0 - 100, where 100 = Excellent Privacy Health)
  int calculateDevicePrivacyScore(List<PermissionRiskResult> results) {
    return calculateDevicePrivacyScoreBreakdown(results).overallScore;
  }

  bool _isUtilityApp(AppTelemetry app, AppCategory category) {
    if (category == AppCategory.game ||
        category == AppCategory.image ||
        category == AppCategory.video ||
        category == AppCategory.audio ||
        category == AppCategory.social ||
        category == AppCategory.maps) {
      return false;
    }

    final nameLower = app.appName.toLowerCase();
    final pkgLower = app.packageName.toLowerCase();

    return nameLower.contains('calculator') ||
        nameLower.contains('clock') ||
        nameLower.contains('timer') ||
        nameLower.contains('compass') ||
        nameLower.contains('flashlight') ||
        pkgLower.contains('calculator') ||
        pkgLower.contains('clock');
  }
}
