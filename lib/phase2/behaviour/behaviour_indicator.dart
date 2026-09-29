/// Structured telemetry observation signal.
/// 
/// Strictly describes factual observations without asserting final security verdicts.
class BehaviourIndicator {
  final String code;
  final String category;
  final String message;
  final Map<String, dynamic> context;

  const BehaviourIndicator({
    required this.code,
    required this.category,
    required this.message,
    this.context = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'category': category,
      'message': message,
      'context': context,
    };
  }
}
