import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/guardian/decision/guardian_engine.dart';
import 'package:mobile_privacy_security_project/guardian/reasoning/llm_reasoner.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';
import 'package:mobile_privacy_security_project/services/llm/llm_config.dart';
import 'package:mobile_privacy_security_project/services/llm/llm_provider.dart';

/// Fake LLM Provider for deterministic unit testing without real network API calls
class FakeLlmProvider implements LlmProvider {
  final String? mockResponse;
  final bool shouldThrow;
  final Exception? customException;

  FakeLlmProvider({
    this.mockResponse,
    this.shouldThrow = false,
    this.customException,
  });

  @override
  Future<String> generateResponse({required String prompt}) async {
    if (shouldThrow) {
      throw customException ?? Exception('Fake LLM Provider Network Failure');
    }
    return mockResponse ?? 'Fake Gemini LLM Response: Permission CAMERA is granted for taking photos.';
  }
}

void main() {
  group('Gemini LLM Provider & Reasoning Pipeline Tests', () {
    test('0. LlmConfig centralizes model, thinkingLevel, timeout and tokens', () {
      expect(LlmConfig.model, equals('gemini-3.8-flash'));
      expect(LlmConfig.thinkingLevel, equals('low'));
      expect(LlmConfig.maxOutputTokens, equals(1024));
      expect(LlmConfig.timeout, equals(const Duration(seconds: 15)));
    });

    test('1. Provider success returns LLM text response', () async {
      final provider = FakeLlmProvider(mockResponse: 'Snapchat has camera permission for snapping photos.');
      final response = await provider.generateResponse(prompt: 'Why Snapchat camera?');

      expect(response, contains('Snapchat has camera permission'));
    });

    test('2. Provider failure throws clean exception', () async {
      final provider = FakeLlmProvider(shouldThrow: true);

      expect(
        () async => await provider.generateResponse(prompt: 'Test prompt'),
        throwsA(isA<Exception>()),
      );
    });

    test('3. Missing API key triggers LLMReasoner fallback automatically', () async {
      LlmConfig.setApiKey(''); // Clear API key for test

      final provider = FakeLlmProvider(mockResponse: 'Should not be called');
      final reasoner = LLMReasoner(provider: provider);
      final engine = GuardianEngine(reasoner: reasoner);

      final app = AppTelemetry(
        appName: 'TestApp',
        packageName: 'com.test.app',
        grantedPermissions: ['android.permission.CAMERA'],
      );

      final event = PrivacyEvent.fromMap({
        'timestamp': DateTime.now().toIso8601String(),
        'apps': [app.toJson()],
      });

      final decision = await engine.evaluate(app: app, event: event);

      expect(reasoner.lastStatus, equals(LlmStatus.fallback));
      expect(decision.userFacingExplanation, isNotEmpty);
      expect(decision.reasoning, contains('Fallback'));
    });

    test('4 & 5. Provider timeout or empty response falls back to RuleBasedReasoner', () async {
      LlmConfig.setApiKey('test_fake_api_key_12345');

      final emptyProvider = FakeLlmProvider(mockResponse: '   ');
      final reasoner = LLMReasoner(provider: emptyProvider);
      final engine = GuardianEngine(reasoner: reasoner);

      final app = AppTelemetry(
        appName: 'CalcApp',
        packageName: 'com.calc.app',
        grantedPermissions: ['android.permission.RECORD_AUDIO'],
      );

      final event = PrivacyEvent.fromMap({
        'timestamp': DateTime.now().toIso8601String(),
        'apps': [app.toJson()],
      });

      final decision = await engine.evaluate(app: app, event: event);

      expect(reasoner.lastStatus, equals(LlmStatus.fallback));
      expect(decision.userFacingExplanation, isNotEmpty);
    });

    test('6 & 7. LLMReasoner and GuardianEngine active reasoning pipeline with FakeLlmProvider', () async {
      LlmConfig.setApiKey('test_fake_api_key_12345');

      final activeProvider = FakeLlmProvider(
        mockResponse: 'Snapchat requires camera permission for capturing snaps. Granted state does not mean active camera stream.',
      );

      final reasoner = LLMReasoner(provider: activeProvider);
      final engine = GuardianEngine(reasoner: reasoner);

      final app = AppTelemetry(
        appName: 'Snapchat',
        packageName: 'com.snapchat.android',
        grantedPermissions: ['android.permission.CAMERA'],
      );

      final event = PrivacyEvent.fromMap({
        'timestamp': DateTime.now().toIso8601String(),
        'apps': [app.toJson()],
      });

      final decision = await engine.evaluate(app: app, event: event);

      expect(reasoner.lastStatus, equals(LlmStatus.active));
      expect(decision.userFacingExplanation, contains('Snapchat requires camera permission'));
      expect(decision.reasoning, contains(LlmConfig.model));
    });

    test('8 & 9. GuardianService and Chat integration with FakeLlmProvider', () async {
      LlmConfig.setApiKey('test_fake_api_key_12345');

      final chatProvider = FakeLlmProvider(
        mockResponse: 'Guardian AI: WhatsApp uses microphone permission for voice notes and call features.',
      );

      final service = GuardianService(provider: chatProvider);

      final appList = [
        AppTelemetry(
          appName: 'WhatsApp',
          packageName: 'com.whatsapp',
          grantedPermissions: ['android.permission.RECORD_AUDIO'],
        )
      ];

      service.updateTelemetryContext(appList);

      final chatMessage = await service.askGuardian('Why does WhatsApp need microphone permission?');

      expect(chatMessage.isUser, isFalse);
      expect(chatMessage.text, contains('WhatsApp uses microphone permission'));
    });
  });
}
