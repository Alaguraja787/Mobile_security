import 'dart:math';
import '../../models/app_telemetry.dart';
import '../../models/sensor_access_event.dart';
import 'models/agent_necessity_evaluation.dart';

/// Context and Functional Necessity Evaluator for the Privacy Guardian Agent.
///
/// Evaluates live sensor triggers against real-time device context:
/// 1. Foreground Interactive State (is user actively looking at and using this app?)
/// 2. Screen Lock State (is screen locked or asleep?)
/// 3. App Domain & Category (Payment QR scanner vs Calculator vs Social vs Navigation)
/// 4. Hardware Necessity (is the sensor genuinely needed for the active user task?)
class ContextNecessityEvaluator {
  const ContextNecessityEvaluator();

  AgentNecessityEvaluation evaluate({
    required SensorAccessEvent event,
    String? activeForegroundPackage,
    String? appNameOverride,
    AppTelemetry? appTelemetry,
    bool isScreenLocked = false,
  }) {
    final String evalId = 'eval_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    final String pkg = event.packageName ?? 'unknown.system.client';
    final String appName = event.appName ?? appNameOverride ?? (appTelemetry?.appName.isNotEmpty == true ? appTelemetry!.appName : pkg);
    final SensorType sensor = event.sensorType;
    final bool locked = isScreenLocked || event.isScreenLocked;

    // Check if package is actively in the foreground
    final bool isForeground = activeForegroundPackage != null &&
        activeForegroundPackage.isNotEmpty &&
        (activeForegroundPackage == pkg || (event.packageName != null && activeForegroundPackage == event.packageName));

    final String category = _inferAppCategory(pkg, appName, appTelemetry);
    final List<String> facts = [
      'Sensor: ${sensor.label}',
      'Target App: $appName ($pkg)',
      'Foreground Status: ${isForeground ? "ACTIVE_FOREGROUND" : "BACKGROUND_OR_INACTIVE"}',
      'Screen Status: ${locked ? "LOCKED" : "UNLOCKED"}',
      'Inferred Domain: $category',
    ];

    // =========================================================================
    // CASE 1: SCREEN IS LOCKED (CRITICAL THREAT VECTOR)
    // =========================================================================
    if (locked) {
      final isCallApp = _isDialerOrCallApp(pkg, category);
      if (isCallApp && sensor == SensorType.microphone) {
        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.allow,
          necessityScore: 0.85,
          confidence: 'VERIFIED',
          primaryReason: 'Active call audio while screen is locked.',
          detailedExplanation:
              'Microphone access is permitted because $appName appears to be maintaining an ongoing voice call session while your phone is locked.',
          isForeground: isForeground,
          isScreenLocked: true,
          appCategory: category,
          isExpectedPattern: true,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Exception: Active voice call session permitted while screen locked'),
        );
      }

      return AgentNecessityEvaluation(
        evaluationId: evalId,
        packageName: pkg,
        appName: appName,
        sensorType: sensor,
        recommendation: AgentRecommendation.block,
        necessityScore: 0.05,
        confidence: 'VERIFIED',
        primaryReason: 'Unexpected ${sensor.label.toLowerCase()} access while screen was locked.',
        detailedExplanation:
            'I recommended blocking ${sensor.label.toLowerCase()} access because $appName attempted to access hardware sensors while your screen was locked and inactive.',
        isForeground: false,
        isScreenLocked: true,
        appCategory: category,
        isExpectedPattern: false,
        timestamp: DateTime.now(),
        contextFacts: facts..add('High-Risk Anomaly: Hardware access initiated without user awareness'),
      );
    }

    // =========================================================================
    // CASE 2: APP IS IN BACKGROUND OR NOT ACTIVELY BEING USED
    // =========================================================================
    if (!isForeground) {
      // 2A. Camera in Background (NEVER justified for normal apps)
      if (sensor == SensorType.camera) {
        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.block,
          necessityScore: 0.0,
          confidence: 'VERIFIED',
          primaryReason: 'Camera access attempted from the background.',
          detailedExplanation:
              'I recommended blocking camera access because $appName attempted to open the camera hardware while you were not actively using the app.',
          isForeground: false,
          isScreenLocked: false,
          appCategory: category,
          isExpectedPattern: false,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Violation: Background camera capture without visible foreground UI'),
        );
      }

      // 2B. Microphone in Background
      if (sensor == SensorType.microphone) {
        final isAudioPlayerOrRecorder = category == 'MEDIA_RECORDER' || category == 'COMMUNICATION';
        if (isAudioPlayerOrRecorder) {
          return AgentNecessityEvaluation(
            evaluationId: evalId,
            packageName: pkg,
            appName: appName,
            sensorType: sensor,
            recommendation: AgentRecommendation.askUser,
            necessityScore: 0.50,
            confidence: 'HIGH',
            primaryReason: 'Background microphone recording initiated.',
            detailedExplanation:
                '$appName is recording audio in the background. Verify if you have an active call or voice note in progress.',
            isForeground: false,
            isScreenLocked: false,
            appCategory: category,
            isExpectedPattern: true,
            timestamp: DateTime.now(),
            contextFacts: facts..add('Ambiguous: Background audio by communication app'),
          );
        }

        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.block,
          necessityScore: 0.10,
          confidence: 'VERIFIED',
          primaryReason: 'Unexpected microphone access detected outside active app usage.',
          detailedExplanation:
              'I recommended blocking microphone access because $appName accessed the microphone while you were not actively using the app.',
          isForeground: false,
          isScreenLocked: false,
          appCategory: category,
          isExpectedPattern: false,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Risk: Covert background acoustic monitoring'),
        );
      }

      // 2C. Background Location
      if (sensor == SensorType.location) {
        final isNavigationOrRide = category == 'NAVIGATION' || category == 'RIDE_SHARING' || category == 'DELIVERY';
        if (isNavigationOrRide) {
          return AgentNecessityEvaluation(
            evaluationId: evalId,
            packageName: pkg,
            appName: appName,
            sensorType: sensor,
            recommendation: AgentRecommendation.allow,
            necessityScore: 0.80,
            confidence: 'HIGH',
            primaryReason: 'Background location for travel or navigation.',
            detailedExplanation:
                'Location access appears necessary for $appName to provide active route tracking or ride updates.',
            isForeground: false,
            isScreenLocked: false,
            appCategory: category,
            isExpectedPattern: true,
            timestamp: DateTime.now(),
            contextFacts: facts..add('Permitted: Navigation service location ping'),
          );
        }

        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.askUser,
          necessityScore: 0.35,
          confidence: 'MEDIUM',
          primaryReason: 'Background location ping detected.',
          detailedExplanation:
              '$appName requested your location in the background without active screen interaction. Review if continuous location is required.',
          isForeground: false,
          isScreenLocked: false,
          appCategory: category,
          isExpectedPattern: false,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Review: Background location without active trip'),
        );
      }
    }

    // =========================================================================
    // CASE 3: APP IS ACTIVELY IN FOREGROUND (USER INTERACTION)
    // =========================================================================
    // 3A. Payment / Banking (e.g. Google Pay, Paytm, PhonePe, Bank)
    if (category == 'PAYMENT' || category == 'FINANCE') {
      if (sensor == SensorType.camera) {
        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.allow,
          necessityScore: 0.95,
          confidence: 'VERIFIED',
          primaryReason: 'Camera access necessary for QR payment scanning.',
          detailedExplanation:
              'Camera access appears necessary because you are actively using $appName to scan a payment QR code or document.',
          isForeground: true,
          isScreenLocked: false,
          appCategory: category,
          isExpectedPattern: true,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Legitimate Intent: QR Scanner viewfinder in active financial app'),
        );
      }

      if (sensor == SensorType.microphone) {
        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.askUser,
          necessityScore: 0.30,
          confidence: 'HIGH',
          primaryReason: 'Microphone accessed inside payment app.',
          detailedExplanation:
              'Verify if you are using voice search or audio features inside $appName, as payment apps typically do not require constant microphone access.',
          isForeground: true,
          isScreenLocked: false,
          appCategory: category,
          isExpectedPattern: false,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Caution: Microphone inside finance application'),
        );
      }
    }

    // 3B. Camera & Media Recording Apps (Google Camera, Snapchat, Photo capture)
    if (category == 'CAMERA' || category == 'MEDIA_RECORDER') {
      if (sensor == SensorType.camera || sensor == SensorType.microphone) {
        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.allow,
          necessityScore: 0.98,
          confidence: 'VERIFIED',
          primaryReason: '${sensor.label} is essential for active photo or video capture.',
          detailedExplanation:
              'Access is necessary because you are actively using $appName to capture photos or record audio.',
          isForeground: true,
          isScreenLocked: false,
          appCategory: category,
          isExpectedPattern: true,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Legitimate Intent: Core camera/audio capture function in foreground'),
        );
      }
    }

    // 3C. Communication & Social Media (WhatsApp, Signal, Telegram, Instagram)
    if (category == 'COMMUNICATION' || category == 'SOCIAL') {
      if (sensor == SensorType.camera || sensor == SensorType.microphone) {
        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.allow,
          necessityScore: 0.88,
          confidence: 'VERIFIED',
          primaryReason: '${sensor.label} active during foreground messaging.',
          detailedExplanation:
              'Access appears expected because you are actively using $appName for photo sharing or voice communication.',
          isForeground: true,
          isScreenLocked: false,
          appCategory: category,
          isExpectedPattern: true,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Legitimate Intent: In-app camera/mic sharing in foreground'),
        );
      }
    }

    // 3D. Utility Apps (Calculator, Notes, Flashlight, Clock, System Tools)
    if (category == 'UTILITY' || category == 'CALCULATOR') {
      if (sensor == SensorType.camera || sensor == SensorType.microphone || sensor == SensorType.location) {
        return AgentNecessityEvaluation(
          evaluationId: evalId,
          packageName: pkg,
          appName: appName,
          sensorType: sensor,
          recommendation: AgentRecommendation.block,
          necessityScore: 0.05,
          confidence: 'VERIFIED',
          primaryReason: 'Utility application does not require ${sensor.label.toLowerCase()} access.',
          detailedExplanation:
              'I recommended blocking because $appName core functionality as a utility does not require access to your ${sensor.label.toLowerCase()}.',
          isForeground: true,
          isScreenLocked: false,
          appCategory: category,
          isExpectedPattern: false,
          timestamp: DateTime.now(),
          contextFacts: facts..add('Severe Mismatch: Over-privileged utility application requesting sensor access'),
        );
      }
    }

    // 3E. General Fallback for Foreground Apps
    return AgentNecessityEvaluation(
      evaluationId: evalId,
      packageName: pkg,
      appName: appName,
      sensorType: sensor,
      recommendation: AgentRecommendation.askUser,
      necessityScore: 0.50,
      confidence: 'MEDIUM',
      primaryReason: '${sensor.label} accessed while app is open.',
      detailedExplanation:
          'Verify if you intended to grant $appName access to ${sensor.label.toLowerCase()} during your current session.',
      isForeground: true,
      isScreenLocked: false,
      appCategory: category,
      isExpectedPattern: true,
      timestamp: DateTime.now(),
      contextFacts: facts..add('Standard: In-app sensor trigger awaiting user confirmation'),
    );
  }

  String _inferAppCategory(String pkg, String appName, AppTelemetry? telemetry) {
    final lowerPkg = pkg.toLowerCase();
    final lowerName = appName.toLowerCase();

    if (lowerPkg.contains('pay') ||
        lowerPkg.contains('gpay') ||
        lowerPkg.contains('paisa') ||
        lowerPkg.contains('bank') ||
        lowerName.contains('pay') ||
        lowerName.contains('wallet')) {
      return 'PAYMENT';
    }

    if (lowerPkg.contains('calc') || lowerName.contains('calc') || lowerPkg.contains('torch') || lowerName.contains('flashlight')) {
      return 'CALCULATOR';
    }

    if (lowerPkg.contains('camera') || lowerName.contains('camera') || lowerPkg.contains('vlc') || lowerPkg.contains('gallery')) {
      return 'CAMERA';
    }

    if (lowerPkg.contains('maps') || lowerPkg.contains('waze') || lowerPkg.contains('navigation')) {
      return 'NAVIGATION';
    }

    if (lowerPkg.contains('uber') || lowerPkg.contains('lyft') || lowerPkg.contains('ola') || lowerPkg.contains('grab')) {
      return 'RIDE_SHARING';
    }

    if (lowerPkg.contains('whatsapp') ||
        lowerPkg.contains('signal') ||
        lowerPkg.contains('telegram') ||
        lowerPkg.contains('dialer') ||
        lowerPkg.contains('phone')) {
      return 'COMMUNICATION';
    }

    if (lowerPkg.contains('instagram') ||
        lowerPkg.contains('facebook') ||
        lowerPkg.contains('snapchat') ||
        lowerPkg.contains('tiktok') ||
        lowerPkg.contains('twitter') ||
        lowerPkg.contains('reddit')) {
      return 'SOCIAL';
    }

    return telemetry?.category.name ?? 'GENERAL';
  }

  bool _isDialerOrCallApp(String pkg, String category) {
    final lower = pkg.toLowerCase();
    return category == 'COMMUNICATION' ||
        lower.contains('dialer') ||
        lower.contains('telecom') ||
        lower.contains('call') ||
        lower.contains('phone');
  }
}
