/// Preprocessor readiness states.
enum PreprocessorStatus {
  notReady,
  ready,
  error;

  String toFormattedString() {
    switch (this) {
      case PreprocessorStatus.notReady:
        return 'PREPROCESSOR_NOT_READY';
      case PreprocessorStatus.ready:
        return 'PREPROCESSOR_READY';
      case PreprocessorStatus.error:
        return 'PREPROCESSOR_ERROR';
    }
  }
}
