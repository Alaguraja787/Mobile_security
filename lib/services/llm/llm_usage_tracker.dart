import 'dart:developer' as developer;

/// Immutable record capturing token usage and latency for an LLM invocation.
class LlmUsageRecord {
  final String model;
  final String provider;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int latencyMs;
  final bool isSuccess;
  final String? failureReason;
  final DateTime timestamp;

  const LlmUsageRecord({
    required this.model,
    required this.provider,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    required this.latencyMs,
    required this.isSuccess,
    this.failureReason,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'model': model,
        'provider': provider,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'totalTokens': totalTokens,
        'latencyMs': latencyMs,
        'isSuccess': isSuccess,
        'failureReason': failureReason,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  String toString() =>
      'LlmUsageRecord($provider/$model: tokens=$totalTokens latency=${latencyMs}ms success=$isSuccess)';
}

/// Central in-memory ledger tracking LLM calls, tokens, latency, and success/failure rates.
class LlmUsageTracker {
  static final LlmUsageTracker instance = LlmUsageTracker();

  final List<LlmUsageRecord> _records = [];

  LlmUsageTracker();

  /// Records an LLM call execution.
  void record({
    required String model,
    required String provider,
    int promptTokens = 0,
    int completionTokens = 0,
    int? totalTokens,
    required int latencyMs,
    required bool isSuccess,
    String? failureReason,
    DateTime? timestamp,
  }) {
    final computedTotal = totalTokens ?? (promptTokens + completionTokens);
    final rec = LlmUsageRecord(
      model: model,
      provider: provider,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: computedTotal,
      latencyMs: latencyMs,
      isSuccess: isSuccess,
      failureReason: failureReason,
      timestamp: timestamp ?? DateTime.now(),
    );

    _records.add(rec);

    developer.log(
      'LLM_USAGE_RECORDED: provider=$provider model=$model tokens=$computedTotal latencyMs=$latencyMs success=$isSuccess',
      name: 'LlmUsageTracker',
    );
  }

  /// All recorded usage entries.
  List<LlmUsageRecord> get records => List.unmodifiable(_records);

  /// Total calls attempted.
  int get totalCalls => _records.length;

  /// Total successful model executions.
  int get successfulCalls => _records.where((r) => r.isSuccess).length;

  /// Total failed model calls.
  int get failedCalls => _records.where((r) => !r.isSuccess).length;

  /// Aggregate tokens consumed across all providers and models.
  int get totalTokensUsed => _records.fold(0, (sum, r) => sum + r.totalTokens);

  /// Average latency of successful calls in milliseconds.
  double get averageLatencyMs {
    final successList = _records.where((r) => r.isSuccess).toList();
    if (successList.isEmpty) return 0.0;
    final total = successList.fold(0, (sum, r) => sum + r.latencyMs);
    return total / successList.length;
  }

  /// Returns aggregated breakdown by provider and model.
  Map<String, dynamic> getUsageStats() {
    final Map<String, int> providerTokens = {};
    final Map<String, int> modelCalls = {};

    for (final r in _records) {
      providerTokens[r.provider] = (providerTokens[r.provider] ?? 0) + r.totalTokens;
      modelCalls[r.model] = (modelCalls[r.model] ?? 0) + 1;
    }

    return {
      'totalCalls': totalCalls,
      'successfulCalls': successfulCalls,
      'failedCalls': failedCalls,
      'totalTokensUsed': totalTokensUsed,
      'averageLatencyMs': averageLatencyMs,
      'providerTokens': providerTokens,
      'modelCalls': modelCalls,
    };
  }

  /// Clears records (useful for test resets).
  void clear() {
    _records.clear();
  }
}
