import 'dart:async';
import 'dart:io';
import 'model_descriptor.dart';

/// Structured exception representing a model execution failure.
class ModelFailureException implements Exception {
  final String modelId;
  final String provider;
  final FailureType failureType;
  final int? httpStatus;
  final String message;
  final Duration? retryAfter;

  ModelFailureException({
    required this.modelId,
    required this.provider,
    required this.failureType,
    this.httpStatus,
    required this.message,
    this.retryAfter,
  });

  /// Retryable failures warrant automatic failover to the next configured model.
  bool get isRetryable =>
      failureType == FailureType.quotaExceeded ||
      failureType == FailureType.rateLimited ||
      failureType == FailureType.serviceUnavailable ||
      failureType == FailureType.temporaryOverload ||
      failureType == FailureType.timeout;

  /// Authentication failures must fail fast to report configuration/key issues.
  bool get isAuthFailure => failureType == FailureType.authFailure;

  /// Malformed request or programming error must not rotate blindly.
  bool get isMalformedRequest => failureType == FailureType.invalidRequest;

  @override
  String toString() =>
      'ModelFailureException(provider: $provider, model: $modelId, type: ${failureType.code}, status: $httpStatus, message: $message)';
}

/// Truthful classifier distinguishing retryable capacity/quota failures
/// from non-retryable authentication/contract failures.
class FailureClassifier {
  FailureClassifier._();

  static ModelFailureException classify({
    required String modelId,
    required String provider,
    required Object error,
    int? httpStatus,
    String? responseBody,
  }) {
    if (error is ModelFailureException) {
      return error;
    }

    // 1. Classify by HTTP Status Code if explicitly provided
    if (httpStatus != null) {
      if (httpStatus == 429) {
        final isQuota = responseBody?.toLowerCase().contains('quota') ?? true;
        return ModelFailureException(
          modelId: modelId,
          provider: provider,
          failureType: isQuota ? FailureType.quotaExceeded : FailureType.rateLimited,
          httpStatus: httpStatus,
          message: responseBody ?? 'Rate limit / quota exceeded (HTTP 429)',
          retryAfter: _extractRetryAfter(responseBody),
        );
      }

      if (httpStatus == 503 || httpStatus == 502 || httpStatus == 504) {
        return ModelFailureException(
          modelId: modelId,
          provider: provider,
          failureType: FailureType.serviceUnavailable,
          httpStatus: httpStatus,
          message: responseBody ?? 'Service temporarily unavailable / capacity limit (HTTP $httpStatus)',
          retryAfter: const Duration(seconds: 15),
        );
      }

      if (httpStatus == 401 || httpStatus == 403) {
        return ModelFailureException(
          modelId: modelId,
          provider: provider,
          failureType: FailureType.authFailure,
          httpStatus: httpStatus,
          message: responseBody ?? 'Authentication / Authorization failure (HTTP $httpStatus)',
        );
      }

      if (httpStatus == 404) {
        return ModelFailureException(
          modelId: modelId,
          provider: provider,
          failureType: FailureType.serviceUnavailable,
          httpStatus: httpStatus,
          message: responseBody ?? 'Model not found or unavailable endpoint (HTTP 404)',
          retryAfter: const Duration(minutes: 10),
        );
      }

      if (httpStatus == 400) {
        return ModelFailureException(
          modelId: modelId,
          provider: provider,
          failureType: FailureType.invalidRequest,
          httpStatus: httpStatus,
          message: responseBody ?? 'Invalid request / bad argument (HTTP 400)',
        );
      }
    }

    // 2. Classify by exception type
    if (error is TimeoutException || error is SocketException) {
      return ModelFailureException(
        modelId: modelId,
        provider: provider,
        failureType: FailureType.timeout,
        message: 'Network connection timeout: $error',
        retryAfter: const Duration(seconds: 10),
      );
    }

    // 3. Classify by error message string content
    final errStr = error.toString().toLowerCase();

    // Check Output Limit Reached (NOT a quota failure)
    if (errStr.contains('output limit reached') ||
        errStr.contains('max_tokens') ||
        errStr.contains('finishreason: length')) {
      return ModelFailureException(
        modelId: modelId,
        provider: provider,
        failureType: FailureType.outputLimitReached,
        message: 'Model reached configured maximum output tokens limit naturally.',
      );
    }

    // Check Authentication / Key failure
    if (errStr.contains('401') ||
        errStr.contains('403') ||
        errStr.contains('authentication') ||
        errStr.contains('unauthorized') ||
        errStr.contains('forbidden') ||
        errStr.contains('api_key') ||
        errStr.contains('api key is missing') ||
        errStr.contains('invalid api key')) {
      return ModelFailureException(
        modelId: modelId,
        provider: provider,
        failureType: FailureType.authFailure,
        httpStatus: errStr.contains('401') ? 401 : (errStr.contains('403') ? 403 : null),
        message: 'Authentication failure: $error',
      );
    }

    // Check Quota / Rate limit
    if (errStr.contains('429') ||
        errStr.contains('quota') ||
        errStr.contains('rate limit') ||
        errStr.contains('resource_exhausted')) {
      return ModelFailureException(
        modelId: modelId,
        provider: provider,
        failureType: errStr.contains('quota') ? FailureType.quotaExceeded : FailureType.rateLimited,
        httpStatus: 429,
        message: 'Model quota / rate limit exceeded: $error',
        retryAfter: _extractRetryAfter(errStr),
      );
    }

    // Check Service Unavailable / Capacity Overload
    if (errStr.contains('503') ||
        errStr.contains('502') ||
        errStr.contains('504') ||
        errStr.contains('overloaded') ||
        errStr.contains('capacity') ||
        errStr.contains('service unavailable') ||
        errStr.contains('temporarily unavailable')) {
      return ModelFailureException(
        modelId: modelId,
        provider: provider,
        failureType: FailureType.serviceUnavailable,
        httpStatus: errStr.contains('503') ? 503 : (errStr.contains('502') ? 502 : 504),
        message: 'Provider service unavailable or capacity overload: $error',
        retryAfter: const Duration(seconds: 15),
      );
    }

    // Check Timeout
    if (errStr.contains('timeout') || errStr.contains('timed out') || errStr.contains('deadline exceeded')) {
      return ModelFailureException(
        modelId: modelId,
        provider: provider,
        failureType: FailureType.timeout,
        message: 'Request timed out: $error',
        retryAfter: const Duration(seconds: 10),
      );
    }

    // Check Malformed Request
    if (errStr.contains('400') || errStr.contains('bad request') || errStr.contains('invalid argument')) {
      return ModelFailureException(
        modelId: modelId,
        provider: provider,
        failureType: FailureType.invalidRequest,
        httpStatus: 400,
        message: 'Malformed request: $error',
      );
    }

    // Fallback unknown
    return ModelFailureException(
      modelId: modelId,
      provider: provider,
      failureType: FailureType.unknown,
      message: 'Unknown error during model execution: $error',
    );
  }

  static Duration? _extractRetryAfter(String? text) {
    if (text == null) return null;
    final match = RegExp(r'retry[_\-\s]*after[:=\s]*(\d+)', caseSensitive: false).firstMatch(text);
    if (match != null) {
      final seconds = int.tryParse(match.group(1) ?? '');
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
    }
    return null;
  }
}
