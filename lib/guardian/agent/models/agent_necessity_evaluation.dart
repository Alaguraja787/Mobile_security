import '../../../models/sensor_access_event.dart';

/// Autonomous Agent Recommendation for human-in-the-loop governance
enum AgentRecommendation {
  allow,
  askUser,
  block,
}

extension AgentRecommendationExt on AgentRecommendation {
  String get label {
    switch (this) {
      case AgentRecommendation.allow:
        return 'ALLOW';
      case AgentRecommendation.askUser:
        return 'ASK_USER';
      case AgentRecommendation.block:
        return 'BLOCK';
    }
  }

  String get humanLabel {
    switch (this) {
      case AgentRecommendation.allow:
        return 'Allow Access';
      case AgentRecommendation.askUser:
        return 'Review & Ask User';
      case AgentRecommendation.block:
        return 'Block Access';
    }
  }
}

/// Truthful, evidence-grounded result of evaluating a live sensor access event
class AgentNecessityEvaluation {
  final String evaluationId;
  final String packageName;
  final String appName;
  final SensorType sensorType;
  final AgentRecommendation recommendation;
  final double necessityScore; // 0.0 (completely unnecessary / suspicious) to 1.0 (vital)
  final String confidence; // VERIFIED, HIGH, MEDIUM, LOW
  final String primaryReason;
  final String detailedExplanation;
  final bool isForeground;
  final bool isScreenLocked;
  final String appCategory;
  final bool isExpectedPattern;
  final DateTime timestamp;
  final List<String> contextFacts;

  const AgentNecessityEvaluation({
    required this.evaluationId,
    required this.packageName,
    required this.appName,
    required this.sensorType,
    required this.recommendation,
    required this.necessityScore,
    required this.confidence,
    required this.primaryReason,
    required this.detailedExplanation,
    required this.isForeground,
    required this.isScreenLocked,
    required this.appCategory,
    required this.isExpectedPattern,
    required this.timestamp,
    this.contextFacts = const [],
  });

  Map<String, dynamic> toMap() => {
        'evaluationId': evaluationId,
        'packageName': packageName,
        'appName': appName,
        'sensorType': sensorType.toJson(),
        'recommendation': recommendation.label,
        'necessityScore': necessityScore,
        'confidence': confidence,
        'primaryReason': primaryReason,
        'detailedExplanation': detailedExplanation,
        'isForeground': isForeground,
        'isScreenLocked': isScreenLocked,
        'appCategory': appCategory,
        'isExpectedPattern': isExpectedPattern,
        'timestamp': timestamp.toIso8601String(),
        'contextFacts': contextFacts,
      };

  factory AgentNecessityEvaluation.fromMap(Map<String, dynamic> map) {
    AgentRecommendation rec = AgentRecommendation.askUser;
    final recStr = map['recommendation']?.toString().toUpperCase();
    if (recStr == 'ALLOW') {
      rec = AgentRecommendation.allow;
    } else if (recStr == 'BLOCK') {
      rec = AgentRecommendation.block;
    }

    return AgentNecessityEvaluation(
      evaluationId: map['evaluationId']?.toString() ?? '',
      packageName: map['packageName']?.toString() ?? '',
      appName: map['appName']?.toString() ?? '',
      sensorType: SensorType.fromString(map['sensorType']?.toString() ?? ''),
      recommendation: rec,
      necessityScore: (map['necessityScore'] as num?)?.toDouble() ?? 0.5,
      confidence: map['confidence']?.toString() ?? 'HIGH',
      primaryReason: map['primaryReason']?.toString() ?? '',
      detailedExplanation: map['detailedExplanation']?.toString() ?? '',
      isForeground: map['isForeground'] == true,
      isScreenLocked: map['isScreenLocked'] == true,
      appCategory: map['appCategory']?.toString() ?? 'UNKNOWN',
      isExpectedPattern: map['isExpectedPattern'] == true,
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      contextFacts: (map['contextFacts'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}
