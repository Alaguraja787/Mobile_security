// ignore_for_file: constant_identifier_names

enum GuardianSeverity {
  LOW,
  MEDIUM,
  HIGH,
  CRITICAL,
}

extension GuardianSeverityExtension on GuardianSeverity {
  String get name {
    switch (this) {
      case GuardianSeverity.LOW:
        return 'LOW';
      case GuardianSeverity.MEDIUM:
        return 'MEDIUM';
      case GuardianSeverity.HIGH:
        return 'HIGH';
      case GuardianSeverity.CRITICAL:
        return 'CRITICAL';
    }
  }

  static GuardianSeverity fromString(String val) {
    switch (val.toUpperCase()) {
      case 'CRITICAL':
        return GuardianSeverity.CRITICAL;
      case 'HIGH':
        return GuardianSeverity.HIGH;
      case 'MEDIUM':
        return GuardianSeverity.MEDIUM;
      case 'LOW':
      default:
        return GuardianSeverity.LOW;
    }
  }
}

/// Represents the confidence score of a decision, considering telemetry availability.
class GuardianConfidence {
  final double score; // 0.0 to 1.0
  final String justification;
  final List<String> availabilityImpacts;

  GuardianConfidence({
    required this.score,
    required this.justification,
    this.availabilityImpacts = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'justification': justification,
      'availabilityImpacts': availabilityImpacts,
    };
  }

  factory GuardianConfidence.fromJson(Map<String, dynamic> json) {
    return GuardianConfidence(
      score: (json['score'] as num?)?.toDouble() ?? 0.5,
      justification: json['justification']?.toString() ?? '',
      availabilityImpacts: (json['availabilityImpacts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
