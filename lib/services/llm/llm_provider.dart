import 'dart:async';

/// Abstract contract for pluggable LLM Providers.
abstract class LlmProvider {
  Future<String> generateResponse({
    required String prompt,
  });
}
