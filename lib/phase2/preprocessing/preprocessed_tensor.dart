import 'dart:typed_data';

/// Encapsulates a float tensor prepared for local tensor runtime execution.
class PreprocessedTensor {
  final Float32List data;
  final List<int> shape;
  final String schemaVersion;

  PreprocessedTensor({
    required this.data,
    required this.shape,
    required this.schemaVersion,
  }) {
    if (shape.isNotEmpty) {
      final expectedCount = shape.reduce((a, b) => a * b);
      if (data.length != expectedCount) {
        throw ArgumentError(
          'PreprocessedTensor dimension mismatch: shape $shape implies $expectedCount elements, but data has ${data.length}',
        );
      }
    }
  }

  int get totalElements => data.length;

  Map<String, dynamic> toJson() {
    return {
      'shape': shape,
      'schemaVersion': schemaVersion,
      'elementCount': data.length,
    };
  }
}
