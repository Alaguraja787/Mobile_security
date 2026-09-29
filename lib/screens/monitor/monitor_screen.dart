import 'package:flutter/material.dart';
import '../dashboard/sensor_session_screen.dart';
import '../../models/sensor_access_event.dart';
import '../../services/sensor_access_service.dart';

/// Screen for full hardware sensor privacy monitoring.
///
/// Aliases to [SensorSessionScreen] with camera as default initial sensor.
class MonitorScreen extends StatelessWidget {
  final SensorType initialSensorType;
  final SensorAccessService? sensorService;

  const MonitorScreen({
    super.key,
    this.initialSensorType = SensorType.camera,
    this.sensorService,
  });

  @override
  Widget build(BuildContext context) {
    return SensorSessionScreen(
      initialSensorType: initialSensorType,
      sensorService: sensorService,
    );
  }
}
