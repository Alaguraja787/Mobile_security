/// Lifecycle states for dataset collection sessions
enum CollectionState {
  notCollecting,
  collecting,
  stopping,
  stopped,
  error;

  String toFormattedString() {
    switch (this) {
      case CollectionState.notCollecting:
        return 'NOT_COLLECTING';
      case CollectionState.collecting:
        return 'COLLECTING';
      case CollectionState.stopping:
        return 'STOPPING';
      case CollectionState.stopped:
        return 'STOPPED';
      case CollectionState.error:
        return 'ERROR';
    }
  }

  static CollectionState fromString(String status) {
    switch (status.toUpperCase()) {
      case 'COLLECTING':
        return CollectionState.collecting;
      case 'STOPPING':
        return CollectionState.stopping;
      case 'STOPPED':
        return CollectionState.stopped;
      case 'ERROR':
        return CollectionState.error;
      default:
        return CollectionState.notCollecting;
    }
  }
}

/// Metadata and state for a discrete telemetry collection session
class CollectionSession {
  final String sessionId;
  final String sessionName;
  final String startTime;
  final String? stopTime;
  final int recordCount;
  final int storageSizeBytes;
  final CollectionState state;
  final String? errorMessage;

  const CollectionSession({
    required this.sessionId,
    required this.sessionName,
    required this.startTime,
    this.stopTime,
    this.recordCount = 0,
    this.storageSizeBytes = 0,
    this.state = CollectionState.notCollecting,
    this.errorMessage,
  });

  CollectionSession copyWith({
    String? sessionId,
    String? sessionName,
    String? startTime,
    String? stopTime,
    int? recordCount,
    int? storageSizeBytes,
    CollectionState? state,
    String? errorMessage,
  }) {
    return CollectionSession(
      sessionId: sessionId ?? this.sessionId,
      sessionName: sessionName ?? this.sessionName,
      startTime: startTime ?? this.startTime,
      stopTime: stopTime ?? this.stopTime,
      recordCount: recordCount ?? this.recordCount,
      storageSizeBytes: storageSizeBytes ?? this.storageSizeBytes,
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'sessionName': sessionName,
      'startTime': startTime,
      'stopTime': stopTime,
      'recordCount': recordCount,
      'storageSizeBytes': storageSizeBytes,
      'state': state.toFormattedString(),
      'errorMessage': errorMessage,
    };
  }

  factory CollectionSession.fromJson(Map<String, dynamic> json) {
    return CollectionSession(
      sessionId: json['sessionId']?.toString() ?? '',
      sessionName: json['sessionName']?.toString() ?? 'Default Session',
      startTime: json['startTime']?.toString() ?? '',
      stopTime: json['stopTime']?.toString(),
      recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
      storageSizeBytes: (json['storageSizeBytes'] as num?)?.toInt() ?? 0,
      state: CollectionState.fromString(json['state']?.toString() ?? 'NOT_COLLECTING'),
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}
