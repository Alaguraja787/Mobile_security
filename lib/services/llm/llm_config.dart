import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/services.dart' show rootBundle;
import 'model_descriptor.dart';

/// Status of the LLM connection/reasoner
enum LlmStatus {
  active,
  fallback,
  unavailable,
}

/// Centralized configuration for LLM models, API credentials, and default fallback chains.
class LlmConfig {
  static String _apiKey = '';
  static String _groqApiKey = '';
  static String _otariApiKey = '';
  static String _otariApiUrl = 'https://api.otari.ai/v1/chat/completions';

  static String model = 'gemini-3.8-flash';
  static String thinkingLevel = 'none';
  static int maxOutputTokens = 512;
  static Duration timeout = const Duration(seconds: 10);

  static void _ensureLoaded() {
    if (_apiKey.isNotEmpty) return;
    try {
      final envFile = File('.env');
      if (envFile.existsSync()) {
        final content = envFile.readAsStringSync();
        _parseEnv(content);
        if (_apiKey.isNotEmpty) return;
      }
    } catch (_) {}
    try {
      final parentEnv = File('../.env');
      if (parentEnv.existsSync()) {
        final content = parentEnv.readAsStringSync();
        _parseEnv(content);
      }
    } catch (_) {}
  }

  static String get apiKey {
    _ensureLoaded();
    return _apiKey;
  }

  static bool get hasApiKey {
    _ensureLoaded();
    return _apiKey.trim().isNotEmpty;
  }

  static void setApiKey(String key) => _apiKey = key;

  static String get groqApiKey => _groqApiKey;
  static void setGroqApiKey(String key) => _groqApiKey = key;

  static String get otariApiKey => _otariApiKey;
  static void setOtariApiKey(String key) => _otariApiKey = key;

  static String get otariApiUrl => _otariApiUrl;
  static void setOtariApiUrl(String url) => _otariApiUrl = url;

  /// Default 8-stage text model fallback chain:
  /// Gemini 3.8 -> 3.7 -> 3.6 -> 3.5 -> 3.1 -> Groq -> Otari -> Rule-Based Reasoner
  static List<ModelDescriptor> get defaultTextModels => const [
        ModelDescriptor(
          modelId: 'gemini-3.8-flash',
          provider: 'Google',
          displayName: 'Gemini 3.8 Flash',
          capabilities: {ModelCapability.text, ModelCapability.toolCalling},
          priority: 1,
        ),
        ModelDescriptor(
          modelId: 'gemini-3.7-flash',
          provider: 'Google',
          displayName: 'Gemini 3.7 Flash',
          capabilities: {ModelCapability.text, ModelCapability.toolCalling},
          priority: 2,
        ),
        ModelDescriptor(
          modelId: 'gemini-3.6-flash',
          provider: 'Google',
          displayName: 'Gemini 3.6 Flash',
          capabilities: {ModelCapability.text, ModelCapability.toolCalling},
          priority: 3,
        ),
        ModelDescriptor(
          modelId: 'gemini-3.5-flash',
          provider: 'Google',
          displayName: 'Gemini 3.5 Flash',
          capabilities: {ModelCapability.text, ModelCapability.toolCalling},
          priority: 4,
        ),
        ModelDescriptor(
          modelId: 'gemini-3.1-flash-lite',
          provider: 'Google',
          displayName: 'Gemini 3.1 Flash Lite',
          capabilities: {ModelCapability.text, ModelCapability.toolCalling},
          priority: 5,
        ),
        ModelDescriptor(
          modelId: 'llama-3.3-70b-versatile',
          provider: 'Groq',
          displayName: 'Groq Llama 3.3 70B',
          capabilities: {ModelCapability.text, ModelCapability.toolCalling},
          priority: 6,
        ),
        ModelDescriptor(
          modelId: 'otari-large',
          provider: 'Otari',
          displayName: 'Otari Large',
          capabilities: {ModelCapability.text, ModelCapability.toolCalling},
          priority: 7,
        ),
        ModelDescriptor(
          modelId: 'rule-based-reasoner',
          provider: 'Rule-Based Reasoner',
          displayName: 'Rule-Based Reasoner',
          capabilities: {ModelCapability.text, ModelCapability.toolCalling},
          priority: 8,
        ),
      ];

  /// Initializes LLM credentials from .env file or environment variables
  static Future<void> initialize() async {
    // 1. Try reading from working directory .env
    try {
      final envFile = File('.env');
      if (await envFile.exists()) {
        final content = await envFile.readAsString();
        _parseEnv(content);
        if (hasApiKey) {
          developer.log('LlmConfig initialized from local .env', name: 'LlmConfig');
          return;
        }
      }
    } catch (_) {}

    // 2. Try reading from rootBundle (assets/.env or .env)
    try {
      final content = await rootBundle.loadString('.env');
      _parseEnv(content);
      if (hasApiKey) {
        developer.log('LlmConfig initialized from asset .env', name: 'LlmConfig');
        return;
      }
    } catch (_) {}

    // 3. Fallback to platform environment
    final envKey = Platform.environment['GEMINI_API_KEY'];
    if (envKey != null && envKey.isNotEmpty) {
      _apiKey = envKey;
    }
  }

  static void _parseEnv(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eqIdx = trimmed.indexOf('=');
      if (eqIdx <= 0) continue;
      final key = trimmed.substring(0, eqIdx).trim();
      var value = trimmed.substring(eqIdx + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }

      if (key == 'GEMINI_API_KEY') {
        _apiKey = value;
      } else if (key == 'GROQ_API_KEY') {
        _groqApiKey = value;
      } else if (key == 'OTARI_API_KEY') {
        _otariApiKey = value;
      } else if (key == 'OTARI_API_URL') {
        _otariApiUrl = value;
      }
    }
  }

  // Static constructor to immediately parse local .env on desktop / test runner
  static final bool _autoLoaded = () {
    try {
      final envFile = File('.env');
      if (envFile.existsSync()) {
        final content = envFile.readAsStringSync();
        _parseEnv(content);
      }
    } catch (_) {}
    return true;
  }();
  static bool get isAutoLoaded => _autoLoaded;
}