import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/guardian/agent/context_necessity_evaluator.dart';
import 'package:mobile_privacy_security_project/guardian/agent/privacy_guardian_agent.dart';
import 'package:mobile_privacy_security_project/guardian/agent/models/agent_necessity_evaluation.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/models/sensor_access_event.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';
import 'package:mobile_privacy_security_project/services/privacy_alert_manager.dart';
import 'package:mobile_privacy_security_project/services/privacy_notification_service.dart';
import 'package:mobile_privacy_security_project/services/sensor_access_service.dart';
import 'package:mobile_privacy_security_project/telemetry/collectors/android_collector.dart';
import 'package:mobile_privacy_security_project/telemetry/telemetry_service.dart';

class FakeAndroidCollector extends Fake implements AndroidCollector {
  final List<Map<String, dynamic>> blockedCalls = [];

  @override
  Stream<Map<String, dynamic>> get sensorAccessStream => const Stream.empty();

  @override
  Future<Map<String, dynamic>> blockSensorAccess(String packageName, String sensor) async {
    blockedCalls.add({'package': packageName, 'sensor': sensor});
    return {'success': true, 'verified': true, 'package': packageName, 'sensor': sensor};
  }

  @override
  Future<Map<String, dynamic>> restoreSensorAccess(String packageName, String sensor) async {
    return {'success': true, 'verified': true, 'package': packageName, 'sensor': sensor};
  }
}

void main() {
  group('Autonomous Privacy Guardian Agent — Context & Necessity Evaluator', () {
    const evaluator = ContextNecessityEvaluator();

    test('Scenario 1: Google Pay camera access in active foreground -> ALLOW (QR Scanning Context)', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.google.android.apps.nbu.paisa.user',
        appName: 'Google Pay',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final eval = evaluator.evaluate(
        event: event,
        activeForegroundPackage: 'com.google.android.apps.nbu.paisa.user',
        isScreenLocked: false,
      );

      expect(eval.recommendation, equals(AgentRecommendation.allow));
      expect(eval.necessityScore, greaterThanOrEqualTo(0.90));
      expect(eval.primaryReason.toLowerCase(), contains('qr'));
      expect(eval.detailedExplanation, contains('Google Pay'));
      expect(eval.isForeground, isTrue);
      expect(eval.isScreenLocked, isFalse);
    });

    test('Scenario 2: Background microphone access outside active app usage -> BLOCK', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final eval = evaluator.evaluate(
        event: event,
        activeForegroundPackage: 'com.android.launcher', // User is on home screen!
        isScreenLocked: false,
      );

      expect(eval.recommendation, equals(AgentRecommendation.block));
      expect(eval.necessityScore, lessThanOrEqualTo(0.20));
      expect(eval.primaryReason.toLowerCase(), contains('microphone'));
      expect(eval.detailedExplanation, contains('Instagram'));
      expect(eval.detailedExplanation, contains('while you were not actively using the app'));
      expect(eval.isForeground, isFalse);
    });

    test('Scenario 3: Calculator / Utility app requesting camera or microphone -> BLOCK', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.google.android.calculator',
        appName: 'Calculator',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      final eval = evaluator.evaluate(
        event: event,
        activeForegroundPackage: 'com.google.android.calculator',
        isScreenLocked: false,
      );

      expect(eval.recommendation, equals(AgentRecommendation.block));
      expect(eval.necessityScore, lessThanOrEqualTo(0.10));
      expect(eval.primaryReason, contains('Utility application does not require microphone access'));
      expect(eval.detailedExplanation, contains('Calculator core functionality as a utility'));
    });

    test('Scenario 4: Screen locked camera or microphone access -> BLOCK', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.example.unknownapp',
        appName: 'Unknown App',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
        isScreenLocked: true,
      );

      final eval = evaluator.evaluate(
        event: event,
        activeForegroundPackage: null,
        isScreenLocked: true,
      );

      expect(eval.recommendation, equals(AgentRecommendation.block));
      expect(eval.necessityScore, lessThanOrEqualTo(0.10));
      expect(eval.primaryReason, contains('while screen was locked'));
      expect(eval.isScreenLocked, isTrue);
    });

    test('Scenario 5: Active voice call with screen locked -> ALLOW', () {
      final event = SensorAccessEvent(
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.google.android.dialer',
        appName: 'Phone',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
        isScreenLocked: true,
      );

      final eval = evaluator.evaluate(
        event: event,
        activeForegroundPackage: 'com.google.android.dialer',
        isScreenLocked: true,
      );

      expect(eval.recommendation, equals(AgentRecommendation.allow));
      expect(eval.primaryReason, contains('Active call audio while screen is locked'));
      expect(eval.isScreenLocked, isTrue);
    });
  });

  group('Autonomous Privacy Guardian Agent — Orchestrator & Governance Execution', () {
    late FakeAndroidCollector fakeCollector;
    late SensorAccessService sensorService;
    late PrivacyAlertManager alertManager;
    late PrivacyNotificationService notificationService;
    late GuardianService guardianService;
    late PrivacyGuardianAgent agent;

    setUp(() {
      fakeCollector = FakeAndroidCollector();
      sensorService = SensorAccessService(collector: fakeCollector);
      alertManager = PrivacyAlertManager();
      notificationService = PrivacyNotificationService(
        collector: fakeCollector,
        customNotificationSender: ({required int id, required String title, required String body}) async {},
      );
      guardianService = GuardianService();

      agent = PrivacyGuardianAgent(
        sensorAccessService: sensorService,
        telemetryService: TelemetryService(),
        alertManager: alertManager,
        notificationService: notificationService,
        guardianService: guardianService,
      );
    });

    tearDown(() {
      agent.stop();
      sensorService.dispose();
    });

    test('Agent evaluates sensor events and records rich recommendations in AlertManager', () async {
      guardianService.updateTelemetryContext([
        AppTelemetry(
          packageName: 'com.google.android.apps.nbu.paisa.user',
          appName: 'Google Pay',
          lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch,
          usageTodayMs: 60000,
        ),
      ]);
      agent.start();

      final event = SensorAccessEvent(
        eventId: 'test_gpay_event_1',
        sensorType: SensorType.camera,
        state: SensorAccessState.started,
        packageName: 'com.google.android.apps.nbu.paisa.user',
        appName: 'Google Pay',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      sensorService.processEvent(event);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(alertManager.alerts, isNotEmpty);
      final alert = alertManager.alerts.first;
      expect(alert.appName, equals('Google Pay'));
      expect(alert.agentRecommendation, equals(AgentRecommendation.allow));
      expect(alert.actionStatus, equals('PENDING'));
      expect(alert.necessityScore, greaterThanOrEqualTo(0.90));
    });

    test('Human-in-the-Loop decision: User blocks alert -> triggers Shizuku block', () async {
      agent.start();

      final event = SensorAccessEvent(
        eventId: 'test_insta_event_2',
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      sensorService.processEvent(event);
      await Future.delayed(const Duration(milliseconds: 50));

      final alert = alertManager.alerts.first;
      expect(alert.agentRecommendation, equals(AgentRecommendation.block));
      expect(alert.actionStatus, equals('PENDING'));

      // User confirms block:
      final res = await agent.handleUserDecision(
        evaluationId: alert.id,
        decision: AgentRecommendation.block,
        packageName: alert.packageName,
        sensorType: alert.sensorType,
        appName: alert.appName,
      );

      expect(res['success'], isTrue);
      expect(alert.actionStatus, equals('BLOCKED'));
      expect(fakeCollector.blockedCalls.length, equals(1));
      expect(fakeCollector.blockedCalls.first['package'], equals('com.instagram.android'));
      expect(fakeCollector.blockedCalls.first['sensor'], equals('MICROPHONE'));
    });

    test('Autonomous Policy: autoBlockBackgroundMic automatically blocks without human interaction', () async {
      agent.updatePolicyConfig(const AgentPolicyConfig(autoBlockBackgroundMic: true));
      agent.start();

      final event = SensorAccessEvent(
        eventId: 'test_spyware_event_3',
        sensorType: SensorType.microphone,
        state: SensorAccessState.started,
        packageName: 'com.spyware.recorder',
        appName: 'Audio Tool',
        timestamp: DateTime.now(),
        attributionScope: SensorAttributionScope.appLevel,
        confidence: SensorConfidence.verified,
      );

      sensorService.processEvent(event);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(alertManager.alerts, isNotEmpty);
      final alert = alertManager.alerts.first;
      expect(alert.actionStatus, equals('BLOCKED_BY_POLICY'));
      expect(fakeCollector.blockedCalls.length, equals(1));
      expect(fakeCollector.blockedCalls.first['package'], equals('com.spyware.recorder'));
    });
  });
}
