/// Capabilities supported by AI models in Privacy Sentinel.
enum ModelCapability {
  text,
  voice,
  toolCalling,
  streaming,
  vision,
}

/// Categorized failure types for accurate failover decisions.
enum FailureType {
  none,
  quotaExceeded,
  rateLimited,
  serviceUnavailable,
  temporaryOverload,
  timeout,
  authFailure,
  invalidRequest,
  outputLimitReached,
  unknown,
}

extension FailureTypeExtension on FailureType {
  String get code {
    switch (this) {
      case FailureType.none:
        return 'NONE';
      case FailureType.quotaExceeded:
        return 'QUOTA_EXCEEDED';
      case FailureType.rateLimited:
        return 'RATE_LIMITED';
      case FailureType.serviceUnavailable:
        return 'SERVICE_UNAVAILABLE';
      case FailureType.temporaryOverload:
        return 'TEMPORARY_OVERLOAD';
      case FailureType.timeout:
        return 'TIMEOUT';
      case FailureType.authFailure:
        return 'AUTH_FAILURE';
      case FailureType.invalidRequest:
        return 'INVALID_REQUEST';
      case FailureType.outputLimitReached:
        return 'OUTPUT_LIMIT_REACHED';
      case FailureType.unknown:
        return 'UNKNOWN_ERROR';
    }
  }
}

/// Immutable configuration descriptor for an AI model candidate.
class ModelDescriptor {
  final String modelId;
  final String provider; // e.g. 'Google', 'Anthropic', 'OpenAI'
  final String displayName;
  final Set<ModelCapability> capabilities;
  final int priority; // 1 = highest priority
  final bool isEnabled;

  const ModelDescriptor({
    required this.modelId,
    required this.provider,
    required this.displayName,
    required this.capabilities,
    required this.priority,
    this.isEnabled = true,
  });

  bool supports(Set<ModelCapability> requiredCapabilities) {
    return capabilities.containsAll(requiredCapabilities);
  }

  @override
  String toString() => '$provider/$modelId (Priority: $priority)';
}
