import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../services/device_connection_manager.dart';
import '../services/privacy_alert_manager.dart';
import '../services/guardian_service.dart';
import '../services/voice_guardian_service.dart';
import '../telemetry/telemetry_service.dart';
import '../telemetry/app_telemetry_builder.dart';
import '../models/privacy_event.dart';

import '../services/sensor_access_service.dart';
import '../services/privacy_notification_service.dart';
import '../guardian/agent/privacy_guardian_agent.dart';

import 'dashboard/dashboard_screen.dart';
import 'apps/apps_inventory_screen.dart';
import 'alerts/alerts_center_screen.dart';
import 'guardian/guardian_assistant_screen.dart';
import 'device/device_status_screen.dart';
import 'settings/telemetry_diagnostics_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final TelemetryService telemetryService;
  final DeviceConnectionManager deviceManager;
  final PrivacyAlertManager alertManager;
  final GuardianService guardianService;
  final VoiceGuardianService voiceService;
  final SensorAccessService? sensorAccessService;
  final PrivacyNotificationService? privacyNotificationService;
  final PrivacyGuardianAgent? privacyGuardianAgent;

  const MainNavigationScreen({
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
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final AppTelemetryBuilder _builder = AppTelemetryBuilder();
  late final SensorAccessService _sensorAccessService;
  late final PrivacyNotificationService _privacyNotificationService;
  late final PrivacyGuardianAgent _privacyGuardianAgent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sensorAccessService = widget.sensorAccessService ?? SensorAccessService();
    _privacyNotificationService = widget.privacyNotificationService ?? PrivacyNotificationService();
    _privacyGuardianAgent = widget.privacyGuardianAgent ??
        PrivacyGuardianAgent(
          sensorAccessService: _sensorAccessService,
          telemetryService: widget.telemetryService,
          alertManager: widget.alertManager,
          notificationService: _privacyNotificationService,
          guardianService: widget.guardianService,
        );
    _initServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _privacyGuardianAgent.stop();
    if (widget.sensorAccessService == null) {
      _sensorAccessService.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Auto-refresh telemetry when user returns from Android Settings or switches apps
      widget.telemetryService.refreshOnce(forceRefresh: true);
    }
  }

  void _initServices() {
    widget.deviceManager.initialize();
    widget.voiceService.initialize();
    widget.telemetryService.start();
    _sensorAccessService.start();
    _privacyNotificationService.init();
    _privacyGuardianAgent.start();

    _sensorAccessService.eventStream.listen((event) {
      // If event has no attributed package (pure device hardware level),
      // dispatch device-level alert and notification.
      // Attributed app events are autonomously evaluated by PrivacyGuardianAgent.
      if (event.packageName == null || event.packageName!.isEmpty) {
        _privacyNotificationService.handleSensorAccessEvent(event);
        widget.alertManager.processSensorAccessEvent(event);
      }
    });

    // Auto-prompt POST_NOTIFICATIONS permission on Android 13+ if not yet requested
    widget.telemetryService.collector.checkNotificationPermission().then((status) {
      if (status == 'NOT_REQUESTED') {
        widget.telemetryService.collector.requestNotificationPermission();
      }
    });

    // Reset Guardian device context on device disconnection or reconnect
    widget.deviceManager.addListener(() {
      if (widget.deviceManager.status != DeviceConnectionStatus.connected) {
        widget.guardianService.resetDeviceContext();
      }
    });

    widget.telemetryService.stream.listen((PrivacyEvent event) {
      final apps = _builder.build(event);
      widget.alertManager.processTelemetryBatch(apps);
      widget.guardianService.updateTelemetryContext(apps);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.deviceManager),
        ChangeNotifierProvider.value(value: widget.alertManager),
        ChangeNotifierProvider.value(value: widget.voiceService),
        Provider.value(value: widget.telemetryService),
        Provider.value(value: widget.guardianService),
        ChangeNotifierProvider.value(value: _sensorAccessService),
        Provider.value(value: _privacyNotificationService),
        ChangeNotifierProvider.value(value: _privacyGuardianAgent),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWideScreen = constraints.maxWidth >= 900;

          final screens = [
            DashboardScreen(
              telemetryService: widget.telemetryService,
              sensorAccessService: _sensorAccessService,
              onNavigateToApps: () => setState(() => _selectedIndex = 1),
              onNavigateToAlerts: () => setState(() => _selectedIndex = 2),
              onNavigateToGuardian: () => setState(() => _selectedIndex = 3),
            ),
            AppsInventoryScreen(telemetryService: widget.telemetryService),
            AlertsCenterScreen(onNavigateToGuardian: () => setState(() => _selectedIndex = 3)),
            const GuardianAssistantScreen(),
            const DeviceStatusScreen(),
            const TelemetryDiagnosticsScreen(),
          ];

          return Scaffold(
            body: Row(
              children: [
                if (isWideScreen) _buildNavigationRail(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: screens[_selectedIndex.clamp(0, screens.length - 1)],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: isWideScreen ? null : _buildBottomNavigationBar(),
          );
        },
      ),
    );
  }

  Widget _buildNavigationRail() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: NavigationRail(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        extended: true,
        minExtendedWidth: 200,
        backgroundColor: AppColors.surface,
        leading: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PRIVACY SENTINEL',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'SECURITY DASHBOARD',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: Text('Dashboard'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: Text('Apps'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active),
            label: Text('Alerts'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: Text('Guardian AI'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.phone_android_outlined),
            selectedIcon: Icon(Icons.phone_android),
            label: Text('Device'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: Text('Diagnostics'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.apps_outlined),
          activeIcon: Icon(Icons.apps),
          label: 'Apps',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.notifications_active_outlined),
          activeIcon: Icon(Icons.notifications_active),
          label: 'Alerts',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.record_voice_over_outlined),
          activeIcon: Icon(Icons.record_voice_over),
          label: 'Guardian',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.phone_android_outlined),
          activeIcon: Icon(Icons.phone_android),
          label: 'Device',
        ),
      ],
    );
  }
}
