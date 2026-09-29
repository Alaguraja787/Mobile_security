/// Model lifecycle and readiness states.
enum ModelStatus {
  notReady,
  loading,
  ready,
  error;

  String toFormattedString() {
    switch (this) {
      case ModelStatus.notReady:
        return 'MODEL_NOT_READY';
      case ModelStatus.loading:
        return 'MODEL_LOADING';
      case ModelStatus.ready:
        return 'MODEL_READY';
      case ModelStatus.error:
        return 'MODEL_ERROR';
    }
  }
}
