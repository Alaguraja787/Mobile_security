import '../../models/app_telemetry.dart';
import '../../models/privacy_event.dart';
import '../interfaces/phase2_intelligence_provider.dart';

/// Structured input model for the Guardian intelligence layer.
class GuardianInput {
  final String? recordId;
  final String? sessionId;
  final DateTime timestamp;
  final AppTelemetry? targetApp;
  final PrivacyEvent event;
  final Phase2IntelligenceSnapshot intelligenceSnapshot;
  final Map<String, dynamic>? historyContext;

  GuardianInput({
    this.recordId,
    this.sessionId,
    DateTime? timestamp,
    this.targetApp,
    required this.event,
    required this.intelligenceSnapshot,
    this.historyContext,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'sessionId': sessionId,
        'timestamp': timestamp.toIso8601String(),
        'targetApp': targetApp?.toJson(),
        'event': event.toJson(),
        'intelligenceSnapshot': intelligenceSnapshot.toJson(),
        'historyContext': historyContext,
      };
}
