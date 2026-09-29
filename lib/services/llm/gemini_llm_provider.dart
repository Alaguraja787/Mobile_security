import 'dart:convert';
import 'package:http/http.dart' as http;
import 'llm_config.dart';
import 'llm_provider.dart';

/// Gemini LLM Provider communicating with official Google Gemini REST API.
class GeminiLlmProvider implements LlmProvider {
  final http.Client _httpClient;

  GeminiLlmProvider({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  @override
  Future<String> generateResponse({required String prompt}) async {
    final String apiKey = LlmConfig.apiKey;
    if (apiKey.trim().isEmpty) {
      throw Exception('GEMINI_API_KEY is missing or unconfigured.');
    }

    final String url =
        'https://generativelanguage.googleapis.com/v1beta/models/${LlmConfig.model}:generateContent?key=$apiKey';

    final Map<String, dynamic> body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'maxOutputTokens': 512,
        'temperature': 0.3,
        'thinkingConfig': {
          'thinkingBudget': 0,
        },
      },
    };

    http.Response? response;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        response = await _httpClient
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(LlmConfig.timeout);
        if (response.statusCode != 503 && response.statusCode != 429) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1500));
      } catch (e) {
        if (attempt == 1) rethrow;
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    if (response == null) {
      throw Exception('Gemini service request failed: No response received.');
    }

    try {

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final firstCandidate = candidates.first;
          final content = firstCandidate['content'];
          if (content is Map && content['parts'] is List) {
            final parts = content['parts'] as List;
            // 1. Prefer non-thought text parts
            for (final part in parts) {
              if (part is Map && part['thought'] != true && part['text'] != null) {
                final text = part['text'].toString().trim();
                if (text.isNotEmpty) {
                  return text;
                }
              }
            }
            // 2. Fallback to any valid text part
            for (final part in parts) {
              if (part is Map && part['text'] != null) {
                final text = part['text'].toString().trim();
                if (text.isNotEmpty) {
                  return text;
                }
              }
            }
          }
        }
        throw Exception('Gemini returned an empty or unparseable response.');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Gemini API authentication failure (${response.statusCode}).');
      } else if (response.statusCode == 429) {
        throw Exception('Gemini API rate limit exceeded (429).');
      } else {
        throw Exception('Gemini API HTTP Error (${response.statusCode}).');
      }
    } catch (e) {
      throw Exception('Gemini service request failed: $e');
    }
  }
}
