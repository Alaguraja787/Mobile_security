import '../schemas/feature_schema.dart';

/// Metadata embedded or paired with the local trained ONNX model.
class ModelMetadata {
  final String modelName;
  final String modelVersion;
  final String featureSchemaVersion;
  final String preprocessingSchemaVersion;
  final String inputTensorName;
  final String inputDataType;
  final List<int> inputShape;
  final String outputTensorName;
  final List<int> outputShape;
  final String trainedAt;
  final String architecture;
  final String description;

  const ModelMetadata({
    required this.modelName,
    required this.modelVersion,
    required this.featureSchemaVersion,
    this.preprocessingSchemaVersion = '1.0.0',
    this.inputTensorName = 'float_input',
    this.inputDataType = 'float32',
    required this.inputShape,
    this.outputTensorName = 'probabilities',
    required this.outputShape,
    required this.trainedAt,
    required this.architecture,
    required this.description,
  });

  /// Factory representing the unloaded state before any real trained model is loaded.
  factory ModelMetadata.unloaded() {
    return const ModelMetadata(
      modelName: 'None',
      modelVersion: '0.0.0',
      featureSchemaVersion: '1.0.0',
      preprocessingSchemaVersion: '1.0.0',
      inputTensorName: 'float_input',
      inputDataType: 'float32',
      inputShape: [1, 64],
      outputTensorName: 'probabilities',
      outputShape: [1, 2],
      trainedAt: 'UNAVAILABLE',
      architecture: 'UNDECIDED',
      description: 'Model not yet trained from real Android device telemetry.',
    );
  }

  /// Validates whether this model metadata conforms to Phase 2 contract specifications.
  List<String> validateContract(FeatureSchema schema) {
    final errors = <String>[];

    if (featureSchemaVersion != schema.schemaVersion) {
      errors.add(
        'Feature schema version mismatch: model expects "$featureSchemaVersion", runtime schema is "${schema.schemaVersion}"',
      );
    }
    if (preprocessingSchemaVersion != schema.schemaVersion) {
      errors.add(
        'Preprocessing schema version mismatch: model expects "$preprocessingSchemaVersion", runtime schema is "${schema.schemaVersion}"',
      );
    }

    final expectedFeatures = schema.featureCount * 2; // 32 semantic + 32 missingness = 64
    if (inputShape.length != 2 || inputShape[0] != 1 || inputShape[1] != expectedFeatures) {
      errors.add(
        'Invalid model input shape: expected [1, $expectedFeatures], found $inputShape',
      );
    }

    if (outputShape.isEmpty || outputShape.any((d) => d <= 0)) {
      errors.add('Invalid model output shape: $outputShape');
    }

    if (inputTensorName.trim().isEmpty) {
      errors.add('inputTensorName cannot be empty');
    }
    if (outputTensorName.trim().isEmpty) {
      errors.add('outputTensorName cannot be empty');
    }
    if (trainedAt.isEmpty || trainedAt == 'UNAVAILABLE') {
      errors.add('Model metadata is missing valid trainedAt timestamp');
    }
    if (architecture.isEmpty || architecture == 'UNDECIDED') {
      errors.add('Model metadata is missing valid architecture identifier');
    }

    return errors;
  }

  bool isValidFor(FeatureSchema schema) => validateContract(schema).isEmpty;

  factory ModelMetadata.fromJson(Map<String, dynamic> json) {
    List<int> parseIntList(dynamic list) {
      if (list is List) {
        return list.map((e) => (e as num).toInt()).toList();
      }
      return const [];
    }

    return ModelMetadata(
      modelName: json['modelName']?.toString() ?? '',
      modelVersion: json['modelVersion']?.toString() ?? '',
      featureSchemaVersion: json['featureSchemaVersion']?.toString() ?? '1.0.0',
      preprocessingSchemaVersion: json['preprocessingSchemaVersion']?.toString() ?? '1.0.0',
      inputTensorName: json['inputTensorName']?.toString() ?? 'float_input',
      inputDataType: json['inputDataType']?.toString() ?? 'float32',
      inputShape: parseIntList(json['inputShape']),
      outputTensorName: json['outputTensorName']?.toString() ?? 'probabilities',
      outputShape: parseIntList(json['outputShape']),
      trainedAt: json['trainedAt']?.toString() ?? '',
      architecture: json['architecture']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modelName': modelName,
      'modelVersion': modelVersion,
      'featureSchemaVersion': featureSchemaVersion,
      'preprocessingSchemaVersion': preprocessingSchemaVersion,
      'inputTensorName': inputTensorName,
      'inputDataType': inputDataType,
      'inputShape': inputShape,
      'outputTensorName': outputTensorName,
      'outputShape': outputShape,
      'trainedAt': trainedAt,
      'architecture': architecture,
      'description': description,
    };
  }
}
