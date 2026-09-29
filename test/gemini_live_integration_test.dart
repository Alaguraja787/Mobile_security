import 'dart:developer' as developer;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/services/llm/llm_config.dart';
import 'package:mobile_privacy_security_project/services/llm/gemini_llm_provider.dart';
import 'package:mobile_privacy_security_project/services/guardian_service.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';

void main() {
  test('LIVE REAL GEMINI API NETWORK TEST', () async {
    expect(LlmConfig.hasApiKey, isTrue, reason: 'GEMINI_API_KEY must be loaded from .env');
    expect(LlmConfig.model, equals('gemini-3.8-flash'));

    final provider = GeminiLlmProvider();
    final prompt = '''
SYSTEM ROLE:
You are Privacy Sentinel Guardian, an expert Android mobile security & privacy intelligence assistant.

OBSERVED FACTS:
Application Name: Snapchat
Package Name: com.snapchat.android
Declared Facts: [{"category": "PERMISSION", "description": "CAMERA permission is GRANTED"}]

USER QUESTION:
"Why does Snapchat need camera permission?"

RESPONSE REQUIREMENTS:
- Explain clearly and concisely in 2 sentences.
- Be objective and accurate.
''';

    developer.log('=== INITIATING LIVE GEMINI API REQUEST ===');
    developer.log('Model: ${LlmConfig.model}');
    
    try {
      final response = await provider.generateResponse(prompt: prompt);
      developer.log('=== REAL GEMINI API RESPONSE RECEIVED ===');
      developer.log(response);

      expect(response, isNotNull);
      expect(response.isNotEmpty, isTrue);
    } catch (e) {
      if (e.toString().contains('429') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        developer.log('Live Gemini endpoint unreachable or rate limited, skipping assertion: $e');
      } else {
        rethrow;
      }
    }
  });

  test('LIVE GUARDIAN SERVICE CHAT PIPELINE TEST', () async {
    final guardianService = GuardianService();
    guardianService.updateTelemetryContext([
      AppTelemetry(
        packageName: 'com.snapchat.android',
        appName: 'Snapchat',
        isSystemApp: false,
        grantedPermissions: ['CAMERA', 'MICROPHONE'],
      )
    ]);

    final chatMessage = await guardianService.askGuardian('Why does Snapchat need camera permission?');

    developer.log('=== GUARDIAN SERVICE CHAT RESPONSE ===');
    developer.log('ID: ${chatMessage.id}');
    developer.log('Text: ${chatMessage.text}');

    expect(chatMessage.text.isNotEmpty, isTrue);
    expect(chatMessage.isUser, isFalse);
  });
}
