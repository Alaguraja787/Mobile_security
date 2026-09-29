import 'dart:developer' as developer;
import 'model_descriptor.dart';

/// Tracks cooldowns per model and per provider to prevent hammering exhausted endpoints.
///
/// Features bounded exponential backoff per model, failure count tracking,
/// and selective provider cooldown to allow fallback models under the same provider
/// (e.g. Gemini 3.8 -> 3.7 -> 3.6 -> 3.5 -> 3.1) to be attempted.
class ModelCooldownTracker {
  final Map<String, DateTime> _modelCooldowns = {};
  final Map<String, DateTime> _providerCooldowns = {};
  final Map<String, int> _modelFailureCounts = {};

  static const Duration defaultModelCooldown = Duration(seconds: 20);
  static const Duration quotaModelCooldown = Duration(minutes: 10);
  static const Duration maxModelCooldown = Duration(minutes: 15);
  static const Duration defaultProviderQuotaCooldown = Duration(seconds: 45);

  /// Checks whether a specific model is currently available (not in cooldown).
  bool isModelAvailable(String modelId) {
    final expiry = _modelCooldowns[modelId];
    if (expiry == null) return true;
    final available = DateTime.now().isAfter(expiry);
    if (available) {
      _modelCooldowns.remove(modelId);
    }
    return available;
  }

  /// Checks whether a provider is currently available (not in provider-level quota cooldown).
  bool isProviderAvailable(String provider) {
    final expiry = _providerCooldowns[provider];
    if (expiry == null) return true;
    final available = DateTime.now().isAfter(expiry);
    if (available) {
      _providerCooldowns.remove(provider);
    }
    return available;
  }

  /// Records a failure and applies a bounded progressive cooldown window.
  void recordFailure({
    required String modelId,
    required String provider,
    required FailureType failureType,
    Duration? retryAfter,
    bool coolDownProvider = false,
  }) {
    final now = DateTime.now();
    final count = (_modelFailureCounts[modelId] ?? 0) + 1;
    _modelFailureCounts[modelId] = count;

    // Progressive backoff: base * count, capped at maxModelCooldown
    Duration cooldownDuration;
    if (retryAfter != null) {
      cooldownDuration = retryAfter;
    } else if (failureType == FailureType.quotaExceeded || failureType == FailureType.rateLimited) {
      // Rate limited / quota exceeded endpoints should not be retried every few seconds
      cooldownDuration = quotaModelCooldown;
    } else {
      final multiplier = count.clamp(1, 10);
      final computedMs = defaultModelCooldown.inMilliseconds * multiplier;
      cooldownDuration = Duration(
        milliseconds: computedMs > maxModelCooldown.inMilliseconds
            ? maxModelCooldown.inMilliseconds
            : computedMs,
      );
    }

    final until = now.add(cooldownDuration);
    _modelCooldowns[modelId] = until;

    developer.log(
      'MODEL_COOLDOWN_APPLIED: provider=$provider model=$modelId failures=$count until=${until.toIso8601String()} durationSec=${cooldownDuration.inSeconds}',
      name: 'ModelCooldownTracker',
    );

    // Only apply provider-wide cooldown if specifically requested (e.g. invalid provider auth or explicit provider outage)
    if (coolDownProvider) {
      final providerCooldown = retryAfter ?? defaultProviderQuotaCooldown;
      final providerUntil = now.add(providerCooldown);
      _providerCooldowns[provider] = providerUntil;
      developer.log(
        'PROVIDER_COOLDOWN_APPLIED: provider=$provider until=${providerUntil.toIso8601String()}',
        name: 'ModelCooldownTracker',
      );
    }
  }

  /// Records successful execution, clearing any pending cooldowns and failure counts.
  void recordSuccess({required String modelId, required String provider}) {
    _modelCooldowns.remove(modelId);
    _modelFailureCounts.remove(modelId);
    _providerCooldowns.remove(provider);
  }

  /// Clears all recorded cooldowns (e.g. for testing).
  void reset() {
    _modelCooldowns.clear();
    _providerCooldowns.clear();
    _modelFailureCounts.clear();
  }
}
