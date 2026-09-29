import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../model/local_model.dart';
import '../model/model_metadata.dart';
import '../model/model_status.dart';
import '../preprocessing/preprocessed_tensor.dart';
import '../schemas/feature_schema.dart';
import 'onnx_tensor_adapter.dart';

/// Robust ONNX Runtime implementation of LocalModel.
/// 
/// Handles model discovery, loading, tensor execution, memory management, and error transitions.
/// Strictly reports MODEL_NOT_READY when no valid trained ONNX model exists.
class OnnxModelRunner implements LocalModel {
  final String? modelAssetPath;
  final FeatureSchema schema;
  OrtSession? _session;
  ModelStatus _status = ModelStatus.notReady;
  final ModelMetadata? _metadata;
  String _lastErrorMessage = '';

  OnnxModelRunner({
    this.modelAssetPath,
    ModelMetadata? initialMetadata,
    FeatureSchema? schema,
  })  : _metadata = initialMetadata,
        schema = schema ?? FeatureSchema.v1;

  @override
  ModelStatus get status => _status;

  @override
  bool get isReady => _status == ModelStatus.ready && _session != null;

  @override
  ModelMetadata? get metadata => _metadata;

  String get lastErrorMessage => _lastErrorMessage;

  @override
  Future<void> load() async {
    if (modelAssetPath == null || modelAssetPath!.isEmpty) {
      _status = ModelStatus.notReady;
      return;
    }

    if (_status == ModelStatus.ready && _session != null) {
      return;
    }

    _status = ModelStatus.loading;

    try {
      OrtEnv.instance.init();

      ByteData rawAsset;
      try {
        rawAsset = await rootBundle.load(modelAssetPath!);
      } catch (e) {
        // Asset not present -> MODEL_NOT_READY (intentional before real training)
        _status = ModelStatus.notReady;
        _lastErrorMessage = 'ONNX model asset not found: $modelAssetPath';
        return;
      }

      final bytes = rawAsset.buffer.asUint8List();
      if (bytes.isEmpty) {
        _status = ModelStatus.notReady;
        _lastErrorMessage = 'ONNX model asset is empty';
        return;
      }

      // Validate metadata existence and contract
      if (_metadata == null) {
        _status = ModelStatus.error;
        _lastErrorMessage = 'MODEL_ERROR: Model asset loaded but required ModelMetadata is null.';
        return;
      }

      final contractErrors = _metadata.validateContract(schema);
      if (contractErrors.isNotEmpty) {
        _status = ModelStatus.error;
        _lastErrorMessage = 'MODEL_ERROR: Incompatible ONNX model contract: ${contractErrors.join("; ")}';
        return;
      }

      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, sessionOptions);
      _status = ModelStatus.ready;
    } catch (e) {
      _status = ModelStatus.error;
      _lastErrorMessage = e.toString();
    }
  }

  @override
  Future<ModelInferenceResult> predict(PreprocessedTensor input) async {
    if (!isReady || _session == null || _metadata == null) {
      return ModelInferenceResult.notReady(
        _status == ModelStatus.error
            ? 'MODEL_ERROR: $_lastErrorMessage'
            : 'MODEL_NOT_READY: Local ONNX model is not available or uncalibrated.',
      );
    }

    // Validate input tensor contract
    if (input.shape.length != _metadata.inputShape.length ||
        input.shape[0] != _metadata.inputShape[0] ||
        input.shape[1] != _metadata.inputShape[1]) {
      return ModelInferenceResult.error(
        'Input tensor shape mismatch: expected ${_metadata.inputShape}, received ${input.shape}',
      );
    }

    OrtValueTensor? inputTensor;
    List<OrtValue?>? outputs;

    try {
      inputTensor = OnnxTensorAdapter.createInputTensor(input);

      final runOptions = OrtRunOptions();
      outputs = _session!.run(
        runOptions,
        {_metadata.inputTensorName: inputTensor},
      );

      if (outputs.isEmpty || outputs[0] == null) {
        return ModelInferenceResult.error('ONNX model returned empty output tensor');
      }

      final rawValue = outputs[0]!.value;
      List<double> rawOutputs = [];

      if (rawValue is List) {
        rawOutputs = rawValue
            .expand((e) => e is List ? e : [e])
            .map((e) => (e as num).toDouble())
            .toList();
      }

      if (rawOutputs.isEmpty) {
        return ModelInferenceResult.error('Failed to parse float values from ONNX output tensor');
      }

      // Check all values are finite
      for (final v in rawOutputs) {
        if (!v.isFinite) {
          return ModelInferenceResult.error('Non-finite value ($v) in ONNX output tensor');
        }
      }

      final expectedElements = _metadata.outputShape.isNotEmpty
          ? _metadata.outputShape.reduce((a, b) => a * b)
          : 0;
      if (expectedElements > 0 && rawOutputs.length != expectedElements) {
        return ModelInferenceResult.error(
          'Output tensor dimension mismatch: expected $expectedElements elements for shape ${_metadata.outputShape}, received ${rawOutputs.length}',
        );
      }

      final anomalyScore = rawOutputs[0];
      final confidence = rawOutputs.length > 1 ? rawOutputs[1] : 1.0;

      if (anomalyScore < 0.0 || anomalyScore > 1.0) {
        return ModelInferenceResult.error('Anomaly score ($anomalyScore) outside valid [0.0, 1.0] range');
      }
      if (confidence < 0.0 || confidence > 1.0) {
        return ModelInferenceResult.error('Confidence score ($confidence) outside valid [0.0, 1.0] range');
      }

      return ModelInferenceResult.ready(
        anomalyScore: anomalyScore,
        confidence: confidence,
        rawOutputs: rawOutputs,
      );
    } catch (e) {
      return ModelInferenceResult.error(e.toString());
    } finally {
      OnnxTensorAdapter.safeRelease(inputTensor);
      OnnxTensorAdapter.safeReleaseOutputs(outputs);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      _session?.release();
    } catch (_) {}
    _session = null;
    _status = ModelStatus.notReady;
  }
}
