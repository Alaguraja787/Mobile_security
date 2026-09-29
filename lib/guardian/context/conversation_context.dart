import 'device_inventory_context.dart';

/// Represents a single recorded turn in a conversational dialogue with the Guardian.
class ConversationTurn {
  final String userMessage;
  final String assistantResponse;
  final QueryIntent intent;
  final String? resolvedAppName;
  final String? resolvedPackageName;
  final String? resolvedPermission;
  final String? evidenceSummary;
  final DateTime timestamp;

  const ConversationTurn({
    required this.userMessage,
    required this.assistantResponse,
    required this.intent,
    this.resolvedAppName,
    this.resolvedPackageName,
    this.resolvedPermission,
    this.evidenceSummary,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'userMessage': userMessage,
        'assistantResponse': assistantResponse,
        'intent': intent.name,
        'resolvedAppName': resolvedAppName,
        'resolvedPackageName': resolvedPackageName,
        'resolvedPermission': resolvedPermission,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Bounded conversation context tracker.
///
/// Retains recent conversation turns to resolve omitted subjects, pronouns,
/// and follow-up inquiries generically without hardcoded phrase rules.
class ConversationContext {
  static const int defaultMaxTurns = 5;
  final int maxTurns;
  final List<ConversationTurn> _turns = [];

  String? activeTopic;
  String? activeAppName;
  String? activePackageName;
  String? activePermission;

  ConversationContext({this.maxTurns = defaultMaxTurns});

  List<ConversationTurn> get recentTurns => List.unmodifiable(_turns);

  ConversationTurn? get lastTurn => _turns.isNotEmpty ? _turns.last : null;

  bool get hasActiveSubject => activePackageName != null || activeAppName != null;

  /// Records a completed conversational turn and updates active subjects.
  void recordTurn({
    required String userMessage,
    required String assistantResponse,
    required QueryIntent intent,
    String? resolvedAppName,
    String? resolvedPackageName,
    String? resolvedPermission,
    String? evidenceSummary,
  }) {
    final turn = ConversationTurn(
      userMessage: userMessage,
      assistantResponse: assistantResponse,
      intent: intent,
      resolvedAppName: resolvedAppName ?? activeAppName,
      resolvedPackageName: resolvedPackageName ?? activePackageName,
      resolvedPermission: resolvedPermission ?? activePermission,
      evidenceSummary: evidenceSummary,
      timestamp: DateTime.now(),
    );

    _turns.add(turn);
    if (_turns.length > maxTurns) {
      _turns.removeAt(0);
    }

    // Update active subjects when resolved
    if (resolvedPackageName != null || resolvedAppName != null) {
      activeAppName = resolvedAppName;
      activePackageName = resolvedPackageName;
      activeTopic = resolvedAppName;
    }
    if (resolvedPermission != null) {
      activePermission = resolvedPermission;
    }
  }

  /// Explicitly updates the active topic/entity.
  void updateActiveSubject({
    String? appName,
    String? packageName,
    String? permission,
    String? topic,
  }) {
    if (appName != null || packageName != null) {
      activeAppName = appName;
      activePackageName = packageName;
      activeTopic = topic ?? appName;
    }
    if (permission != null) {
      activePermission = permission;
    }
  }

  /// Clears active application/permission subject (e.g. for global queries or topic switches).
  void clearSubject() {
    activeTopic = null;
    activeAppName = null;
    activePackageName = null;
    activePermission = null;
  }

  /// Clears entire conversation history and active state.
  void reset() {
    _turns.clear();
    clearSubject();
  }
}
