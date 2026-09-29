import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';
import '../preprocessing/preprocessed_tensor.dart';

/// Memory and lifecycle manager for ONNX Runtime tensors.
class OnnxTensorAdapter {
  /// Creates an OrtValueTensor from a PreprocessedTensor.
  /// The caller is responsible for calling release() on the returned tensor.
  static OrtValueTensor createInputTensor(PreprocessedTensor tensor) {
    return OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(tensor.data),
      tensor.shape,
    );
  }

  /// Safely releases an OrtValueTensor without throwing if already released.
  static void safeRelease(OrtValueTensor? tensor) {
    try {
      tensor?.release();
    } catch (_) {
      // Ignored: already freed
    }
  }

  /// Safely releases a list of OrtValue outputs.
  static void safeReleaseOutputs(List<OrtValue?>? outputs) {
    if (outputs == null) return;
    for (final out in outputs) {
      try {
        out?.release();
      } catch (_) {
        // Ignored
      }
    }
  }
}
