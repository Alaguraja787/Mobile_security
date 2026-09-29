// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/sensor_access_event.dart';
import '../telemetry/collectors/android_collector.dart';
import '../guardian/agent/models/agent_necessity_evaluation.dart';
import 'sensor_access_service.dart';

/// Notification decision outcome for auditability and testing.
enum NotificationDecisionOutcome {
  notified,
  suppressedAlreadyActive,
  suppressedCooldown,
  suppressedStoppedState,
  suppressedUnknownState,
}

/// Result of evaluating a SensorAccessEvent for notification emission.
class NotificationDecision {
  final NotificationDecisionOutcome outcome;
  final String? title;
  final String? body;
  final String reason;
  final String decisionReason;

  NotificationDecision({
    required this.outcome,
    this.title,
    this.body,
    required this.reason,
    this.decisionReason = 'NOTIFICATION_SENT',
  });

  bool get wasNotified => outcome == NotificationDecisionOutcome.notified;
}

/// Service managing real-time notifications for camera and microphone access.
///
/// Strictly enforces:
/// - Cooldown and deduplication (never spam every polling cycle).
/// - Dynamic text formatting strictly from verified event data (no hardcoded apps).
/// - Rule 9: If device-level, body is "Camera activity detected on your device."
/// - Clean separation between sensor detection and notification display.
class PrivacyNotificationService {
  static const String defaultChannelId = 'privacy_sensor_alerts';
  static const String defaultChannelName = 'Privacy Sentinel Sensor Alerts';
  static const String defaultChannelDescription =
      'Real-time alerts when applications access camera or microphone';

  final String channelId;
  final String channelName;
  final String channelDescription;
  final Duration cooldownDuration;

  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final AndroidCollector _collector;
  final Future<void> Function({
    required int id,
    required String title,
    required String body,
  })? customNotificationSender;

  bool _isInitialized = false;

  // Active tracking and cooldown maps
  final Set<String> _activeAlertKeys = {};
  final Map<String, DateTime> _lastNotifiedTimestamps = {};

  PrivacyNotificationService({
    this.channelId = defaultChannelId,
    this.channelName = defaultChannelName,
    this.channelDescription = defaultChannelDescription,
    this.cooldownDuration = const Duration(seconds: 30),
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    AndroidCollector? collector,
    this.customNotificationSender,
  })  : _notificationsPlugin =
            notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _collector = collector ?? AndroidCollector();

  Future<void> init() async {
    if (_isInitialized || customNotificationSender != null) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);

    // Create dedicated notification channel for Android 8.0+
    final androidChannel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);
    await androidPlugin?.requestNotificationsPermission();

    _isInitialized = true;
  }

  /// Evaluates an incoming SensorAccessEvent, enforces deduplication/cooldown,
  /// and displays a notification if justified by the evidence.
  Future<NotificationDecision> handleSensorAccessEvent(
    SensorAccessEvent event, {
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final key = _keyFor(event);
    print('NOTIFICATION_RECEIVED: sensor=${event.sensorType.toJson()} state=${event.state.toJson()} scope=${event.attributionScope.toJson()}');

    // 0. Ensure service is initialized
    if (!_isInitialized && customNotificationSender == null) {
      try {
        await init();
      } catch (e) {
        print('NOTIFICATION_DECISION: SERVICE_NOT_INITIALIZED (error: $e)');
        return NotificationDecision(
          outcome: NotificationDecisionOutcome.suppressedUnknownState,
          reason: 'Notification service initialization failed: $e',
          decisionReason: 'SERVICE_NOT_INITIALIZED',
        );
      }
    }

    final deviceKey = '${event.sensorType.toJson()}_DEVICE_LEVEL';

    // 1. If sensor stopped: clear active state so future started events can notify
    if (event.state == SensorAccessState.stopped) {
      if (event.packageName != null) {
        _activeAlertKeys.remove(key);
      } else {
        // Clear all active alert keys for this sensor type when hardware stops
        _activeAlertKeys.removeWhere((k) => k.startsWith('${event.sensorType.toJson()}_'));
      }
      print('NOTIFICATION_DECISION: UNKNOWN_EVENT_IGNORED (Sensor stopped event; active state cleared)');
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.suppressedStoppedState,
        reason: 'Sensor stopped event; active alert state cleared.',
        decisionReason: 'UNKNOWN_EVENT_IGNORED',
      );
    }

    // 2. Only STARTED or ACTIVE states trigger notifications
    if (event.state != SensorAccessState.started &&
        event.state != SensorAccessState.active) {
      print('NOTIFICATION_DECISION: UNKNOWN_EVENT_IGNORED (state ${event.state.toJson()} does not trigger notifications)');
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.suppressedUnknownState,
        reason: 'Event state (${event.state.toJson()}) does not trigger notifications.',
        decisionReason: 'UNKNOWN_EVENT_IGNORED',
      );
    }

    // Check for invalid event
    if (event.sensorType == SensorType.otherSupported && event.state == SensorAccessState.unknown) {
      print('NOTIFICATION_DECISION: INVALID_EVENT (sensor=${event.sensorType.toJson()})');
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.suppressedUnknownState,
        reason: 'Invalid or unsupported sensor event.',
        decisionReason: 'INVALID_EVENT',
      );
    }

    // 3. Priority check: If this is a generic DEVICE_LEVEL event, but an app-level alert is ALREADY active for this sensor:
    if (!event.isAppAttributed && event.attributionScope == SensorAttributionScope.deviceLevel) {
      final hasActiveAppAlert = _activeAlertKeys.any((k) =>
          k.startsWith('${event.sensorType.toJson()}_') && k != deviceKey);
      if (hasActiveAppAlert) {
        print('NOTIFICATION_DECISION: DUPLICATE_SUPPRESSED (verified app alert already active for ${event.sensorType.toJson()})');
        return NotificationDecision(
          outcome: NotificationDecisionOutcome.suppressedAlreadyActive,
          reason: 'Verified app alert already active for this sensor; generic alert suppressed.',
          decisionReason: 'APP_LEVEL_ACTIVE_SUPPRESSED',
        );
      }
    }

    // 4. Upgrade check: If this is a verified APP_LEVEL event and a DEVICE_LEVEL notification was previously shown:
    final bool isUpgradingDeviceLevel = event.isAppAttributed && _activeAlertKeys.contains(deviceKey);
    if (isUpgradingDeviceLevel) {
      print('NOTIFICATION_UPGRADE: Replacing device-level notification with verified app notification for ${event.sensorType.toJson()}');
      _activeAlertKeys.remove(deviceKey);
    }

    // 5. Deduplication: if sensor already flagged as active for this app/device, suppress
    if (_activeAlertKeys.contains(key)) {
      print('NOTIFICATION_DECISION: DUPLICATE_SUPPRESSED (sensor is already active for $key)');
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.suppressedAlreadyActive,
        reason: 'Sensor is already active; repeated notification suppressed.',
        decisionReason: 'DUPLICATE_SUPPRESSED',
      );
    }

    // 6. Cooldown: if notified recently within cooldown window (unless upgrading from device-level), suppress
    if (!isUpgradingDeviceLevel) {
      final lastNotified = _lastNotifiedTimestamps[key];
      if (lastNotified != null &&
          currentTime.difference(lastNotified) < cooldownDuration) {
        print('NOTIFICATION_DECISION: COOLDOWN_SUPPRESSED (cooldown active for $key)');
        return NotificationDecision(
          outcome: NotificationDecisionOutcome.suppressedCooldown,
          reason: 'Notification suppressed due to active cooldown period.',
          decisionReason: 'COOLDOWN_SUPPRESSED',
        );
      }
    }

    // 7. Check platform notification permission and channel when running on device
    if (customNotificationSender == null) {
      final isEnabled = await _collector.isNotificationsEnabled();
      if (!isEnabled) {
        print('NOTIFICATION_DECISION: USER_DISABLED (alert notifications turned off in settings)');
        return NotificationDecision(
          outcome: NotificationDecisionOutcome.suppressedUnknownState,
          reason: 'Alert notifications turned off by user in settings.',
          decisionReason: 'USER_DISABLED',
        );
      }

      final permStatus = await _collector.checkNotificationPermission();
      if (permStatus != 'GRANTED') {
        print('NOTIFICATION_DECISION: PERMISSION_DENIED (POST_NOTIFICATIONS status: $permStatus)');
        return NotificationDecision(
          outcome: NotificationDecisionOutcome.suppressedUnknownState,
          reason: 'Notification permission not granted ($permStatus).',
          decisionReason: 'PERMISSION_DENIED',
        );
      }

      final channelCheck = await _collector.checkNotificationChannel(channelId);
      if (channelCheck['disabled'] == true) {
        print('NOTIFICATION_DECISION: CHANNEL_DISABLED (channel $channelId disabled or missing: $channelCheck)');
        return NotificationDecision(
          outcome: NotificationDecisionOutcome.suppressedUnknownState,
          reason: 'Notification channel disabled or missing.',
          decisionReason: 'CHANNEL_DISABLED',
        );
      }
    }

    // 6. Construct dynamic title & body strictly from genuine event data in simple human language
    final appIdentifier = (event.appName != null && event.appName!.isNotEmpty)
        ? event.appName!
        : (event.packageName != null && event.packageName!.isNotEmpty
            ? event.packageName!
            : null);

    final String title;
    final String body;

    if (event.isScreenLocked) {
      // CASE 1: LOCKED SCREEN BACKGROUND ACTIVITY
      switch (event.sensorType) {
        case SensorType.microphone:
          title = '🚨 Screen Locked: Microphone Alert';
          body = appIdentifier != null
              ? '$appIdentifier accessed your microphone in the background while your screen was locked!'
              : 'Microphone accessed in the background while your screen was locked!';
          break;
        case SensorType.camera:
          title = '🚨 Screen Locked: Camera Alert';
          body = appIdentifier != null
              ? '$appIdentifier accessed your camera in the background while your screen was locked!'
              : 'Camera accessed in the background while your screen was locked!';
          break;
        case SensorType.location:
          title = '🚨 Screen Locked: Location Alert';
          body = appIdentifier != null
              ? '$appIdentifier accessed your location in the background while your screen was locked!'
              : 'Location accessed in the background while your screen was locked!';
          break;
        case SensorType.photos:
          title = '🚨 Screen Locked: Photo Access Alert';
          final fileDesc = event.fileName != null ? '"${event.fileName}"' : 'your photos';
          body = appIdentifier != null
              ? '$appIdentifier accessed $fileDesc in the background while your screen was locked!'
              : 'An app accessed $fileDesc in the background while your screen was locked!';
          break;
        case SensorType.videos:
        case SensorType.files:
        case SensorType.audioFiles:
          title = '📁 Screen Locked: File Access Alert';
          final fileDesc = event.fileName != null ? '"${event.fileName}"' : event.sensorType.label.toLowerCase();
          body = appIdentifier != null
              ? '$appIdentifier accessed $fileDesc in the background while your screen was locked!'
              : 'An app accessed $fileDesc in the background while your screen was locked!';
          break;
        default:
          title = '🚨 Screen Locked: Privacy Alert';
          body = appIdentifier != null
              ? '$appIdentifier accessed background resources while your screen was locked!'
              : 'Background sensor activity detected while your screen was locked!';
      }
    } else {
      // CASE 2: SCREEN UNLOCKED ACTIVE USAGE
      switch (event.sensorType) {
        case SensorType.microphone:
          title = '🎙️ Microphone access';
          body = appIdentifier != null
              ? '$appIdentifier is using your microphone.'
              : 'Microphone activity detected on your device.';
          break;
        case SensorType.camera:
          title = '📷 Camera access';
          body = appIdentifier != null
              ? '$appIdentifier is using your camera.'
              : 'Camera activity detected on your device.';
          break;
        case SensorType.location:
          title = '📍 Location access';
          body = appIdentifier != null
              ? '$appIdentifier is using your location.'
              : 'Location activity detected on your device.';
          break;
        case SensorType.photos:
          title = '🖼️ Photos access';
          final fileDesc = event.fileName != null ? 'photo "${event.fileName}"' : 'your photos';
          body = appIdentifier != null
              ? '$appIdentifier accessed $fileDesc.'
              : 'Photos accessed: $fileDesc.';
          break;
        case SensorType.videos:
          title = '🎥 Videos access';
          final fileDesc = event.fileName != null ? '"${event.fileName}"' : 'your videos';
          body = appIdentifier != null
              ? '$appIdentifier accessed $fileDesc.'
              : 'Videos accessed: $fileDesc.';
          break;
        case SensorType.files:
          title = '📁 Files access';
          final fileDesc = event.fileName != null ? '"${event.fileName}"' : 'a file';
          body = appIdentifier != null
              ? '$appIdentifier accessed $fileDesc.'
              : 'File accessed: $fileDesc.';
          break;
        case SensorType.audioFiles:
          title = '🎵 Audio files access';
          final fileDesc = event.fileName != null ? '"${event.fileName}"' : 'audio files';
          body = appIdentifier != null
              ? '$appIdentifier accessed $fileDesc.'
              : 'Audio files accessed: $fileDesc.';
          break;
        default:
          title = '${event.sensorType.iconEmoji} ${event.sensorType.label} access';
          body = appIdentifier != null
              ? '$appIdentifier is using your ${event.sensorType.label.toLowerCase()}.'
              : '${event.sensorType.label} activity detected on your device.';
      }
    }

    // 7. Record state
    _activeAlertKeys.add(key);
    _lastNotifiedTimestamps[key] = currentTime;

    // For point-in-time accesses (photos, files, videos, audioFiles, location),
    // clear from _activeAlertKeys after a 10s cooldown so future discrete accesses notify
    if (event.sensorType == SensorType.photos ||
        event.sensorType == SensorType.videos ||
        event.sensorType == SensorType.files ||
        event.sensorType == SensorType.audioFiles ||
        event.sensorType == SensorType.location) {
      Timer(const Duration(seconds: 10), () {
        _activeAlertKeys.remove(key);
      });
    }

    // 8. Dispatch notification: if device-level or upgrading from device-level, use baseSensorId to seamlessly replace
    final int baseSensorId = event.sensorType == SensorType.camera
        ? 10001
        : (event.sensorType == SensorType.microphone
            ? 10002
            : (event.sensorType == SensorType.location ? 10003 : 10004));
    final int notificationId = (event.attributionScope == SensorAttributionScope.deviceLevel || isUpgradingDeviceLevel)
        ? baseSensorId
        : (key.hashCode.abs() % 100000);
    try {
      await _sendNotification(
        id: notificationId,
        title: title,
        body: body,
        payload: event.packageName,
      );

      print('NOTIFICATION_DECISION: NOTIFICATION_SENT (title="$title", body="$body")');
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.notified,
        title: title,
        body: body,
        reason: 'Verified active sensor access notification emitted.',
        decisionReason: 'NOTIFICATION_SENT',
      );
    } catch (e) {
      print('NOTIFICATION_DECISION: OTHER_ERROR (error: $e)');
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.suppressedUnknownState,
        reason: 'Failed to dispatch notification: $e',
        decisionReason: 'OTHER_ERROR',
      );
    }
  }

  /// Dispatches an actionable Agent notification containing the AI recommendation,
  /// contextual reason, and human-in-the-loop governance choices.
  Future<NotificationDecision> handleAgentEvaluation(
    AgentNecessityEvaluation evaluation, {
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final key = '${evaluation.sensorType.toJson()}_${evaluation.packageName}_AGENT';

    // Deduplication cooldown check
    final lastTime = _lastNotifiedTimestamps[key];
    if (lastTime != null && currentTime.difference(lastTime) < cooldownDuration) {
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.suppressedCooldown,
        reason: 'Agent alert within cooldown duration.',
        decisionReason: 'AGENT_COOLDOWN_SUPPRESSED',
      );
    }

    if (customNotificationSender == null) {
      final isEnabled = await _collector.isNotificationsEnabled();
      if (!isEnabled) {
        return NotificationDecision(
          outcome: NotificationDecisionOutcome.suppressedUnknownState,
          reason: 'Alert notifications turned off by user in settings.',
          decisionReason: 'USER_DISABLED',
        );
      }
    }

    final String title;
    switch (evaluation.recommendation) {
      case AgentRecommendation.block:
        title = '🚨 Privacy Alert: Block Recommended';
        break;
      case AgentRecommendation.askUser:
        title = '⚠️ Privacy Alert: Review ${evaluation.appName}';
        break;
      case AgentRecommendation.allow:
        title = '🛡️ Sensor Access: ${evaluation.appName}';
        break;
    }

    final String body =
        '${evaluation.appName} accessed ${evaluation.sensorType.label.toLowerCase()}.\n'
        'AI Recommendation: ${evaluation.recommendation.humanLabel}\n'
        'Reason: ${evaluation.primaryReason}\n\n'
        '${evaluation.detailedExplanation}\n'
        '[Allow]  [Block]  [Ask Guardian]';

    final int notificationId = key.hashCode.abs() % 100000;
    _lastNotifiedTimestamps[key] = currentTime;

    try {
      await _sendNotification(
        id: notificationId,
        title: title,
        body: body,
        payload: evaluation.packageName,
      );

      print('AGENT_NOTIFICATION_DISPATCHED: id=$notificationId title="$title"');
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.notified,
        title: title,
        body: body,
        reason: 'Actionable Agent notification emitted.',
        decisionReason: 'AGENT_NOTIFICATION_SENT',
      );
    } catch (e) {
      return NotificationDecision(
        outcome: NotificationDecisionOutcome.suppressedUnknownState,
        reason: 'Failed to dispatch agent notification: $e',
        decisionReason: 'NOTIFICATION_ERROR',
      );
    }
  }

  /// Builds a notification body for historical/recent sensor access without hardcoded names.
  static String buildRecentAccessBody({
    required SensorAccessEvent event,
    DateTime? now,
  }) {
    final appIdentifier = event.appName ?? event.packageName ?? 'An application';
    final elapsed = SensorAccessService.formatRelativeTime(event.timestamp, now);
    return '$appIdentifier used your ${event.sensorType.label.toLowerCase()} $elapsed.';
  }

  Future<void> _sendNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (customNotificationSender != null) {
      await customNotificationSender!(id: id, title: title, body: body);
      return;
    }

    await init();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      styleInformation: BigTextStyleInformation(body),
    );

    final details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(id, title, body, details, payload: payload);
  }

  String _keyFor(SensorAccessEvent event) {
    final pkg = event.packageName ?? 'DEVICE_LEVEL';
    final lockTag = event.isScreenLocked ? '_LOCKED' : '';
    if (event.fileName != null) {
      return '${event.sensorType.toJson()}_${pkg}_${event.fileName}$lockTag';
    }
    return '${event.sensorType.toJson()}_$pkg$lockTag';
  }

  /// Resets internal cooldown and active state maps (useful for testing and session resets).
  void resetState() {
    _activeAlertKeys.clear();
    _lastNotifiedTimestamps.clear();
  }
}
