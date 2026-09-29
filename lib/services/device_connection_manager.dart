import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../telemetry/collectors/android_collector.dart';

enum DeviceConnectionStatus {
  noDevice,
  connecting,
  connected,
  connectionError,
}

class ConnectedDeviceInfo {
  final String deviceName;
  final String model;
  final String manufacturer;
  final String androidVersion;
  final int sdkVersion;
  final String connectionMethod; // e.g. "Native IPC Binder", "Local Bridge", "USB/ADB Debug"
  final DateTime lastSync;
  final bool isRooted;
  final Map<String, dynamic> rawContext;

  ConnectedDeviceInfo({
    required this.deviceName,
    required this.model,
    required this.manufacturer,
    required this.androidVersion,
    required this.sdkVersion,
    required this.connectionMethod,
    required this.lastSync,
    this.isRooted = false,
    this.rawContext = const {},
  });

  factory ConnectedDeviceInfo.defaultUnknown() {
    return ConnectedDeviceInfo(
      deviceName: 'Unknown Android Device',
      model: 'Android Device',
      manufacturer: 'Generic',
      androidVersion: 'Android OS',
      sdkVersion: 0,
      connectionMethod: 'Local Service',
      lastSync: DateTime.now(),
    );
  }
}

/// Device Connection Manager orchestrating real-time connection status
/// and fetching actual device hardware metadata without hardcoded models.
class DeviceConnectionManager extends ChangeNotifier {
  final AndroidCollector _collector;
  final DeviceInfoPlugin _deviceInfoPlugin;

  DeviceConnectionStatus _status = DeviceConnectionStatus.connecting;
  ConnectedDeviceInfo? _deviceInfo;
  String? _errorMessage;
  Timer? _heartbeatTimer;

  DeviceConnectionStatus get status => _status;
  ConnectedDeviceInfo? get deviceInfo => _deviceInfo;
  String? get errorMessage => _errorMessage;

  DeviceConnectionManager({
    AndroidCollector? collector,
    DeviceInfoPlugin? deviceInfoPlugin,
  })  : _collector = collector ?? AndroidCollector(),
        _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  /// Initializes device discovery and starts periodic liveness checks.
  Future<void> initialize() async {
    await discoverDevice();
    _startHeartbeat();
  }

  /// Discovers connected device specs and real-time native health
  Future<void> discoverDevice() async {
    _status = DeviceConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await _deviceInfoPlugin.androidInfo;
        final Map<String, dynamic> nativeContext = await _collector.getDeviceContext();
        final Map<String, dynamic> securityInfo = await _collector.getDeviceSecurity();

        final String name = androidInfo.model.isNotEmpty
            ? '${androidInfo.manufacturer} ${androidInfo.model}'
            : 'Android Device';

        final bool isRooted = securityInfo['isRooted'] == true;

        _deviceInfo = ConnectedDeviceInfo(
          deviceName: name,
          model: androidInfo.model,
          manufacturer: androidInfo.manufacturer,
          androidVersion: androidInfo.version.release,
          sdkVersion: androidInfo.version.sdkInt,
          connectionMethod: 'Native Binder IPC Channel',
          lastSync: DateTime.now(),
          isRooted: isRooted,
          rawContext: nativeContext,
        );

        _status = DeviceConnectionStatus.connected;
      } else {
        // Desktop / Web / Simulator fallback environment
        _deviceInfo = ConnectedDeviceInfo(
          deviceName: 'Privacy Sentinel Virtual Host (${Platform.operatingSystem})',
          model: Platform.operatingSystem,
          manufacturer: 'Host Platform',
          androidVersion: Platform.operatingSystemVersion,
          sdkVersion: 34,
          connectionMethod: 'Host System Bridge',
          lastSync: DateTime.now(),
          isRooted: false,
        );
        _status = DeviceConnectionStatus.connected;
      }
    } catch (e) {
      _status = DeviceConnectionStatus.connectionError;
      _errorMessage = 'Device discovery error: $e';
    }

    notifyListeners();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_status == DeviceConnectionStatus.connected) {
        try {
          final health = await _collector.getTelemetryHealth();
          if (health.containsKey('error')) {
            _status = DeviceConnectionStatus.connectionError;
            _errorMessage = health['error']?.toString();
          } else if (_deviceInfo != null) {
            _deviceInfo = ConnectedDeviceInfo(
              deviceName: _deviceInfo!.deviceName,
              model: _deviceInfo!.model,
              manufacturer: _deviceInfo!.manufacturer,
              androidVersion: _deviceInfo!.androidVersion,
              sdkVersion: _deviceInfo!.sdkVersion,
              connectionMethod: _deviceInfo!.connectionMethod,
              lastSync: DateTime.now(),
              isRooted: _deviceInfo!.isRooted,
              rawContext: _deviceInfo!.rawContext,
            );
          }
        } catch (e) {
          _status = DeviceConnectionStatus.connectionError;
          _errorMessage = e.toString();
        }
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
