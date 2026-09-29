/// Represents a concrete, observed telemetry fact.
class ObservedFact {
  final String id;
  final String category; // e.g. "NETWORK", "USAGE", "PERMISSION", "SENSOR", "DEVICE"
  final String description;
  final String availabilityState; // e.g. "VALID", "RESTRICTED", "UNAVAILABLE", "DENIED"
  final dynamic rawValue;

  ObservedFact({
    required this.id,
    required this.category,
    required this.description,
    this.availabilityState = "VALID",
    this.rawValue,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'description': description,
        'availabilityState': availabilityState,
        'rawValue': rawValue?.toString(),
      };

  factory ObservedFact.fromJson(Map<String, dynamic> json) => ObservedFact(
        id: json['id']?.toString() ?? '',
        category: json['category']?.toString() ?? 'GENERAL',
        description: json['description']?.toString() ?? '',
        availabilityState: json['availabilityState']?.toString() ?? 'VALID',
        rawValue: json['rawValue'],
      );
}

/// Represents a reasoned inference drawn from observed facts.
class Inference {
  final String id;
  final String statement;
  final List<String> supportingFactIds;
  final String reasoningCategory;

  Inference({
    required this.id,
    required this.statement,
    required this.supportingFactIds,
    this.reasoningCategory = "BEHAVIORAL",
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'statement': statement,
        'supportingFactIds': supportingFactIds,
        'reasoningCategory': reasoningCategory,
      };

  factory Inference.fromJson(Map<String, dynamic> json) => Inference(
        id: json['id']?.toString() ?? '',
        statement: json['statement']?.toString() ?? '',
        supportingFactIds: (json['supportingFactIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        reasoningCategory: json['reasoningCategory']?.toString() ?? 'BEHAVIORAL',
      );
}

/// Represents a known limitation, missing signal, or restricted telemetry state.
class Uncertainty {
  final String affectedSignal;
  final String reason;
  final String impactOnDecision;

  Uncertainty({
    required this.affectedSignal,
    required this.reason,
    required this.impactOnDecision,
  });

  Map<String, dynamic> toJson() => {
        'affectedSignal': affectedSignal,
        'reason': reason,
        'impactOnDecision': impactOnDecision,
      };

  factory Uncertainty.fromJson(Map<String, dynamic> json) => Uncertainty(
        affectedSignal: json['affectedSignal']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        impactOnDecision: json['impactOnDecision']?.toString() ?? '',
      );
}

/// Represents a non-destructive actionable recommendation for the user.
class GuardianRecommendation {
  final String id;
  final String title;
  final String description;
  final String priority; // e.g. "LOW", "MEDIUM", "HIGH"
  final String? suggestedSettingsPath;

  GuardianRecommendation({
    required this.id,
    required this.title,
    required this.description,
    this.priority = "MEDIUM",
    this.suggestedSettingsPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority,
        'suggestedSettingsPath': suggestedSettingsPath,
      };

  factory GuardianRecommendation.fromJson(Map<String, dynamic> json) =>
      GuardianRecommendation(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        priority: json['priority']?.toString() ?? 'MEDIUM',
        suggestedSettingsPath: json['suggestedSettingsPath']?.toString(),
      );
}
