import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_connection_manager.dart';

class DeviceStatusScreen extends StatelessWidget {
  const DeviceStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceManager = Provider.of<DeviceConnectionManager>(context);
    final info = deviceManager.deviceInfo;
    final isConnected = deviceManager.status == DeviceConnectionStatus.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected Device Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => deviceManager.discoverDevice(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Connection Status Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isConnected ? AppColors.statusNormal : AppColors.statusAttention,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.check_circle : Icons.error,
                  color: isConnected ? AppColors.statusNormal : AppColors.statusAttention,
                  size: 36,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected ? 'DEVICE CONNECTED' : 'CONNECTION ERROR',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isConnected ? AppColors.statusNormal : AppColors.statusAttention,
                        ),
                      ),
                      Text(
                        info?.deviceName ?? 'No device active',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => deviceManager.discoverDevice(),
                  child: const Text('Re-Sync'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Hardware & OS Details
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hardware & Platform Context', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Divider(height: 20, color: AppColors.surfaceBorder),
                _buildRow('Manufacturer', info?.manufacturer ?? 'Unknown'),
                _buildRow('Model', info?.model ?? 'Unknown'),
                _buildRow('Android Release', info?.androidVersion ?? 'Unknown'),
                _buildRow('SDK API Level', info != null ? '${info.sdkVersion}' : 'Unknown'),
                _buildRow('Bridge Method', info?.connectionMethod ?? 'Unknown'),
                _buildRow('Root Privilege Signal', info?.isRooted == true ? 'DETECTED' : 'CLEAN / NONE'),
                _buildRow('Last Sync Timestamp', info != null ? info.lastSync.toIso8601String() : 'Never'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String title, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              val,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
