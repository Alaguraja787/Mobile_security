/// Strongly-typed sensor access and capability models for real-time privacy monitoring.
enum SensorType {
  camera,
  microphone,
  location,
  photos,
  videos,
  files,
  audioFiles,
  otherSupported;

  static SensorType fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'CAMERA':
        return SensorType.camera;
      case 'MICROPHONE':
        return SensorType.microphone;
      case 'LOCATION':
        return SensorType.location;
      case 'PHOTOS':
        return SensorType.photos;
      case 'VIDEOS':
        return SensorType.videos;
      case 'FILES':
        return SensorType.files;
      case 'AUDIO_FILES':
        return SensorType.audioFiles;
      default:
        return SensorType.otherSupported;
    }
  }

  String get label {
    switch (this) {
      case SensorType.camera:
        return 'Camera';
      case SensorType.microphone:
        return 'Microphone';
      case SensorType.location:
        return 'Location';
      case SensorType.photos:
        return 'Photos';
      case SensorType.videos:
        return 'Videos';
      case SensorType.files:
        return 'Files';
      case SensorType.audioFiles:
        return 'Audio Files';
      case SensorType.otherSupported:
        return 'Sensor';
    }
  }

  String get iconEmoji {
    switch (this) {
      case SensorType.camera:
        return '📷';
      case SensorType.microphone:
        return '🎙️';
      case SensorType.location:
        return '📍';
      case SensorType.photos:
        return '🖼️';
      case SensorType.videos:
        return '🎥';
      case SensorType.files:
        return '📁';
      case SensorType.audioFiles:
        return '🎵';
      case SensorType.otherSupported:
        return '🛡️';
    }
  }

  String toJson() {
    switch (this) {
      case SensorType.camera:
        return 'CAMERA';
      case SensorType.microphone:
        return 'MICROPHONE';
      case SensorType.location:
        return 'LOCATION';
      case SensorType.photos:
        return 'PHOTOS';
      case SensorType.videos:
        return 'VIDEOS';
      case SensorType.files:
        return 'FILES';
      case SensorType.audioFiles:
        return 'AUDIO_FILES';
      case SensorType.otherSupported:
        return 'OTHER_SUPPORTED';
    }
  }
}

enum SensorAccessState {
  started,
  stopped,
  active,
  unknown;

  static SensorAccessState fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'STARTED':
        return SensorAccessState.started;
      case 'STOPPED':
        return SensorAccessState.stopped;
      case 'ACTIVE':
        return SensorAccessState.active;
      default:
        return SensorAccessState.unknown;
    }
  }

  String toJson() {
    switch (this) {
      case SensorAccessState.started:
        return 'STARTED';
      case SensorAccessState.stopped:
        return 'STOPPED';
      case SensorAccessState.active:
        return 'ACTIVE';
      case SensorAccessState.unknown:
        return 'UNKNOWN';
    }
  }
}

enum SensorEventSource {
  appops,
  shizukuAppOps,
  audioManager,
  cameraManager,
  mediaStore,
  systemTelemetry,
  unknown;

  static SensorEventSource fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'APPOPS':
        return SensorEventSource.appops;
      case 'SHIZUKU_APPOPS':
        return SensorEventSource.shizukuAppOps;
      case 'AUDIO_MANAGER':
      case 'AUDIO_MANAGER_FOREGROUND':
        return SensorEventSource.audioManager;
      case 'CAMERA_MANAGER':
      case 'CAMERA_MANAGER_FOREGROUND':
        return SensorEventSource.cameraManager;
      case 'MEDIA_STORE':
        return SensorEventSource.mediaStore;
      case 'SYSTEM_TELEMETRY':
        return SensorEventSource.systemTelemetry;
      default:
        return SensorEventSource.unknown;
    }
  }

  String toJson() {
    switch (this) {
      case SensorEventSource.appops:
        return 'APPOPS';
      case SensorEventSource.shizukuAppOps:
        return 'SHIZUKU_APPOPS';
      case SensorEventSource.audioManager:
        return 'AUDIO_MANAGER';
      case SensorEventSource.cameraManager:
        return 'CAMERA_MANAGER';
      case SensorEventSource.mediaStore:
        return 'MEDIA_STORE';
      case SensorEventSource.systemTelemetry:
        return 'SYSTEM_TELEMETRY';
      case SensorEventSource.unknown:
        return 'UNKNOWN';
    }
  }
}

enum SensorConfidence {
  verified,
  derived,
  unknown;

  static SensorConfidence fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'VERIFIED':
        return SensorConfidence.verified;
      case 'DERIVED':
        return SensorConfidence.derived;
      default:
        return SensorConfidence.unknown;
    }
  }

  String toJson() {
    switch (this) {
      case SensorConfidence.verified:
        return 'VERIFIED';
      case SensorConfidence.derived:
        return 'DERIVED';
      case SensorConfidence.unknown:
        return 'UNKNOWN';
    }
  }
}

enum SensorAttributionScope {
  appLevel,
  deviceLevel,
  unknown;

  static SensorAttributionScope fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'APP_LEVEL':
        return SensorAttributionScope.appLevel;
      case 'DEVICE_LEVEL':
      case 'DEVICE_LEVEL_ONLY':
        return SensorAttributionScope.deviceLevel;
      default:
        return SensorAttributionScope.unknown;
    }
  }

  String toJson() {
    switch (this) {
      case SensorAttributionScope.appLevel:
        return 'APP_LEVEL';
      case SensorAttributionScope.deviceLevel:
        return 'DEVICE_LEVEL';
      case SensorAttributionScope.unknown:
        return 'UNKNOWN';
    }
  }
}

enum SensorCapabilityLevel {
  full,
  limited,
  unavailable;

  static SensorCapabilityLevel fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'FULL':
        return SensorCapabilityLevel.full;
      case 'LIMITED':
        return SensorCapabilityLevel.limited;
      default:
        return SensorCapabilityLevel.unavailable;
    }
  }

  String toJson() {
    switch (this) {
      case SensorCapabilityLevel.full:
        return 'FULL';
      case SensorCapabilityLevel.limited:
        return 'LIMITED';
      case SensorCapabilityLevel.unavailable:
        return 'UNAVAILABLE';
    }
  }
}

/// Represents an individual observed sensor access event.
class SensorAccessEvent {
  final SensorType sensorType;
  final SensorAccessState state;
  final String? packageName;
  final String? appName;
  final DateTime timestamp;
  final SensorEventSource source;
  final SensorConfidence confidence;
  final SensorAttributionScope attributionScope;
  final SensorCapabilityLevel availability;
  final String? reason;
  final String? eventId;
  final String? permissionState;
  final bool blockedState;
  final DateTime? stopTime;
  final Duration? duration;
  final String? fileName;
  final String? mimeType;
  final bool isScreenLocked;
  final String? humanExplanation;

  SensorAccessEvent({
    required this.sensorType,
    required this.state,
    this.packageName,
    this.appName,
    required this.timestamp,
    this.source = SensorEventSource.unknown,
    this.confidence = SensorConfidence.unknown,
    this.attributionScope = SensorAttributionScope.deviceLevel,
    this.availability = SensorCapabilityLevel.limited,
    this.reason,
    this.eventId,
    this.permissionState,
    this.blockedState = false,
    this.stopTime,
    this.duration,
    this.fileName,
    this.mimeType,
    this.isScreenLocked = false,
    this.humanExplanation,
  });

  bool get isAppAttributed =>
      attributionScope == SensorAttributionScope.appLevel &&
      confidence == SensorConfidence.verified &&
      packageName != null &&
      packageName!.isNotEmpty;

  bool get isStarted => state == SensorAccessState.started || state == SensorAccessState.active;
  bool get isStopped => state == SensorAccessState.stopped;

  SensorAccessEvent copyWith({
    SensorType? sensorType,
    SensorAccessState? state,
    String? packageName,
    String? appName,
    DateTime? timestamp,
    SensorEventSource? source,
    SensorConfidence? confidence,
    SensorAttributionScope? attributionScope,
    SensorCapabilityLevel? availability,
    String? reason,
    String? eventId,
    String? permissionState,
    bool? blockedState,
    DateTime? stopTime,
    Duration? duration,
    String? fileName,
    String? mimeType,
    bool? isScreenLocked,
    String? humanExplanation,
  }) {
    return SensorAccessEvent(
      sensorType: sensorType ?? this.sensorType,
      state: state ?? this.state,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      attributionScope: attributionScope ?? this.attributionScope,
      availability: availability ?? this.availability,
      reason: reason ?? this.reason,
      eventId: eventId ?? this.eventId,
      permissionState: permissionState ?? this.permissionState,
      blockedState: blockedState ?? this.blockedState,
      stopTime: stopTime ?? this.stopTime,
      duration: duration ?? this.duration,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      isScreenLocked: isScreenLocked ?? this.isScreenLocked,
      humanExplanation: humanExplanation ?? this.humanExplanation,
    );
  }

  factory SensorAccessEvent.fromMap(Map<dynamic, dynamic> map) {
    DateTime parseTime(dynamic raw) {
      if (raw is String) {
        return DateTime.tryParse(raw) ?? DateTime.now();
      } else if (raw is int) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      }
      return DateTime.now();
    }

    final rawSensor = map['sensor'] ?? map['sensorType'];
    return SensorAccessEvent(
      sensorType: SensorType.fromString(rawSensor?.toString()),
      state: SensorAccessState.fromString(map['state']?.toString()),
      packageName: map['packageName']?.toString(),
      appName: map['appName']?.toString(),
      timestamp: parseTime(map['timestamp']),
      source: SensorEventSource.fromString(map['source']?.toString()),
      confidence: SensorConfidence.fromString(map['confidence']?.toString()),
      attributionScope:
          SensorAttributionScope.fromString(map['attributionScope']?.toString()),
      availability:
          SensorCapabilityLevel.fromString(map['availability']?.toString()),
      reason: map['reason']?.toString(),
      eventId: map['eventId']?.toString(),
      permissionState: map['permissionState']?.toString(),
      blockedState: map['blockedState'] == true,
      stopTime: map['stopTime'] != null ? parseTime(map['stopTime']) : null,
      duration: map['durationMs'] != null ? Duration(milliseconds: (map['durationMs'] as num).toInt()) : null,
      fileName: map['fileName']?.toString(),
      mimeType: map['mimeType']?.toString(),
      isScreenLocked: map['isScreenLocked'] == true,
      humanExplanation: map['humanExplanation']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': 'sensor_access',
      'sensor': sensorType.toJson(),
      'state': state.toJson(),
      'packageName': packageName,
      'appName': appName,
      'timestamp': timestamp.toIso8601String(),
      'source': source.toJson(),
      'confidence': confidence.toJson(),
      'attributionScope': attributionScope.toJson(),
      'availability': availability.toJson(),
      'reason': reason,
      'eventId': eventId,
      'permissionState': permissionState,
      'blockedState': blockedState,
      'stopTime': stopTime?.toIso8601String(),
      'durationMs': duration?.inMilliseconds,
      'fileName': fileName,
      'mimeType': mimeType,
      'isScreenLocked': isScreenLocked,
      'humanExplanation': humanExplanation,
    };
  }

  @override
  String toString() {
    return 'SensorAccessEvent(${sensorType.toJson()}, state: ${state.toJson()}, pkg: $packageName, scope: ${attributionScope.toJson()}, conf: ${confidence.toJson()}, perm: $permissionState, blocked: $blockedState)';
  }
}

/// Dynamic capability status for a specific sensor.
class SingleSensorCapability {
  final SensorCapabilityLevel activeMonitoring;
  final SensorCapabilityLevel appAttribution;
  final SensorCapabilityLevel recentHistory;
  final String? reason;

  SingleSensorCapability({
    required this.activeMonitoring,
    required this.appAttribution,
    required this.recentHistory,
    this.reason,
  });

  factory SingleSensorCapability.fromMap(Map<dynamic, dynamic> map) {
    return SingleSensorCapability(
      activeMonitoring: SensorCapabilityLevel.fromString(
          map['activeMonitoring']?.toString()),
      appAttribution:
          SensorCapabilityLevel.fromString(map['appAttribution']?.toString()),
      recentHistory:
          SensorCapabilityLevel.fromString(map['recentHistory']?.toString()),
      reason: map['reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activeMonitoring': activeMonitoring.toJson(),
      'appAttribution': appAttribution.toJson(),
      'recentHistory': recentHistory.toJson(),
      'reason': reason,
    };
  }
}

/// Comprehensive report of device runtime sensor monitoring capabilities.
class SensorMonitoringCapabilities {
  final SingleSensorCapability camera;
  final SingleSensorCapability microphone;
  final int platformSdkInt;
  final bool isCameraWatcherRegistered;
  final bool isAudioWatcherRegistered;
  final bool isAppOpsWatcherRegistered;

  SensorMonitoringCapabilities({
    required this.camera,
    required this.microphone,
    this.platformSdkInt = 0,
    this.isCameraWatcherRegistered = false,
    this.isAudioWatcherRegistered = false,
    this.isAppOpsWatcherRegistered = false,
  });

  factory SensorMonitoringCapabilities.fromMap(Map<dynamic, dynamic> map) {
    final camMap = map['camera'] is Map ? map['camera'] as Map : {};
    final micMap = map['microphone'] is Map ? map['microphone'] as Map : {};

    return SensorMonitoringCapabilities(
      camera: SingleSensorCapability.fromMap(camMap),
      microphone: SingleSensorCapability.fromMap(micMap),
      platformSdkInt: (map['platformSdkInt'] as num?)?.toInt() ?? 0,
      isCameraWatcherRegistered: map['isCameraWatcherRegistered'] == true,
      isAudioWatcherRegistered: map['isAudioWatcherRegistered'] == true,
      isAppOpsWatcherRegistered: map['isAppOpsWatcherRegistered'] == true,
    );
  }

  factory SensorMonitoringCapabilities.defaultUnknown() {
    return SensorMonitoringCapabilities(
      camera: SingleSensorCapability(
        activeMonitoring: SensorCapabilityLevel.unavailable,
        appAttribution: SensorCapabilityLevel.unavailable,
        recentHistory: SensorCapabilityLevel.unavailable,
      ),
      microphone: SingleSensorCapability(
        activeMonitoring: SensorCapabilityLevel.unavailable,
        appAttribution: SensorCapabilityLevel.unavailable,
        recentHistory: SensorCapabilityLevel.unavailable,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'camera': camera.toJson(),
      'microphone': microphone.toJson(),
      'platformSdkInt': platformSdkInt,
      'isCameraWatcherRegistered': isCameraWatcherRegistered,
      'isAudioWatcherRegistered': isAudioWatcherRegistered,
      'isAppOpsWatcherRegistered': isAppOpsWatcherRegistered,
    };
  }
}
