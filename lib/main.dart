import 'package:flutter/material.dart';
import 'core/theme/sentinel_theme.dart';
import 'screens/main_navigation_screen.dart';
import 'services/device_connection_manager.dart';
import 'services/guardian_service.dart';
import 'services/privacy_alert_manager.dart';
import 'services/storage_service.dart';
import 'services/voice_guardian_service.dart';
import 'services/sensor_access_service.dart';
import 'services/privacy_notification_service.dart';
import 'guardian/agent/privacy_guardian_agent.dart';
import 'telemetry/telemetry_service.dart';
import 'phase2/dataset/dataset_collector.dart';

import 'services/llm/llm_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LlmConfig.initialize();

  final storage = StorageService();
  await storage.initialize();

  final datasetCollector = DatasetCollector(storageService: storage);
  final telemetryService = TelemetryService(datasetCollector: datasetCollector);
  final deviceManager = DeviceConnectionManager();
  final alertManager = PrivacyAlertManager();
  final guardianService = GuardianService();
  final voiceService = VoiceGuardianService(guardianService: guardianService);
  final sensorAccessService = SensorAccessService.shared;
  final privacyNotificationService = PrivacyNotificationService();
  final privacyGuardianAgent = PrivacyGuardianAgent(
    sensorAccessService: sensorAccessService,
    telemetryService: telemetryService,
    alertManager: alertManager,
    notificationService: privacyNotificationService,
    guardianService: guardianService,
  );

  runApp(PrivacySentinelApp(
    telemetryService: telemetryService,
    deviceManager: deviceManager,
    alertManager: alertManager,
    guardianService: guardianService,
    voiceService: voiceService,
    sensorAccessService: sensorAccessService,
    privacyNotificationService: privacyNotificationService,
    privacyGuardianAgent: privacyGuardianAgent,
  ));
}

class PrivacySentinelApp extends StatelessWidget {
  final TelemetryService telemetryService;
  final DeviceConnectionManager deviceManager;
  final PrivacyAlertManager alertManager;
  final GuardianService guardianService;
  final VoiceGuardianService voiceService;
  final SensorAccessService? sensorAccessService;
  final PrivacyNotificationService? privacyNotificationService;
  final PrivacyGuardianAgent? privacyGuardianAgent;

  const PrivacySentinelApp({
    super.key,
    required this.telemetryService,
    required this.deviceManager,
    required this.alertManager,
    required this.guardianService,
    required this.voiceService,
    this.sensorAccessService,
    this.privacyNotificationService,
    this.privacyGuardianAgent,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Privacy Sentinel AI',
      theme: SentinelTheme.darkTheme,
      home: MainNavigationScreen(
        telemetryService: telemetryService,
        deviceManager: deviceManager,
        alertManager: alertManager,
        guardianService: guardianService,
        voiceService: voiceService,
        sensorAccessService: sensorAccessService,
        privacyNotificationService: privacyNotificationService,
        privacyGuardianAgent: privacyGuardianAgent,
      ),
    );
  }
}