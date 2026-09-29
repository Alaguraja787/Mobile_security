export 'llm_gateway.dart';

import 'llm_gateway.dart';

/// Backward-compatible subclass of [LlmGateway] for existing callers and test suites.
class ModelRouter extends LlmGateway {
  ModelRouter({
    super.models,
    super.cooldownTracker,
    super.usageTracker,
    super.customRunner,
    super.httpClient,
  });
}
