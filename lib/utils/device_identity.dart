import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Utility to generate and persist a single, stable, pseudonymous installation UUID.
/// 
/// Invariants:
/// - Generated exactly once per app installation.
/// - Not derived from IMEI, MAC address, serial number, or sensitive hardware attributes.
/// - Persisted in application-private local storage.
/// - Reused across all collection sessions for consistent device identification.
class DeviceIdentity {
  static String? _cachedDeviceId;

  /// Returns the persistent installation-scoped pseudonymous UUID.
  static Future<String> getOrCreateDeviceId({File? customFile}) async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    try {
      File identityFile;
      if (customFile != null) {
        identityFile = customFile;
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        identityFile = File(p.join(docsDir.path, '.device_identity_uuid'));
      }

      if (await identityFile.exists()) {
        final content = (await identityFile.readAsString()).trim();
        if (content.isNotEmpty) {
          _cachedDeviceId = content;
          return _cachedDeviceId!;
        }
      }

      final newUuid = _generateRandomUuid();
      await identityFile.writeAsString(newUuid, flush: true);
      _cachedDeviceId = newUuid;
      return _cachedDeviceId!;
    } catch (e) {
      // Safe fallback if filesystem access fails
      _cachedDeviceId ??= _generateRandomUuid();
      return _cachedDeviceId!;
    }
  }

  /// Synchronous fallback when async initialization has completed
  static String get syncDeviceId => _cachedDeviceId ?? 'anon_device_uuid';

  /// Generates a RFC 4122 v4 UUID using cryptographically secure random bytes
  static String _generateRandomUuid() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    
    // Set version to 4 (0100)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to IETF (10xx)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
