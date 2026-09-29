import '../../models/app_telemetry.dart';
import '../../models/privacy_event.dart';
import '../schemas/feature_definition.dart';
import '../schemas/feature_schema.dart';
import 'feature_value.dart';
import 'feature_vector.dart';

/// Pure feature extractor converting Phase 1 PrivacyEvent & AppTelemetry
/// into deterministic, schema-validated FeatureVectors.
/// 
/// Core Invariants:
/// - Fixed feature ordering (0..31 matching FeatureSchema.v1).
/// - Explicit names and data types.
/// - Preserves missing/unavailable information honestly.
/// - Never invents telemetry or random values.
/// - Never uses hardcoded application threat intelligence.
/// - Never makes a security verdict.
class FeatureExtractor {
  final FeatureSchema schema;

  FeatureExtractor({FeatureSchema? schema}) : schema = schema ?? FeatureSchema.v1;

  /// Extracts a validated FeatureVector for a given AppTelemetry snapshot within a PrivacyEvent.
  FeatureVector extract(AppTelemetry app, PrivacyEvent event) {
    final parsedDate = DateTime.tryParse(event.timestamp);
    final int? nowMs = parsedDate?.millisecondsSinceEpoch;

    final values = <FeatureValue>[];

    // 0: app_is_system_app
    values.add(FeatureValue.validBoolean(
      name: 'app_is_system_app',
      index: 0,
      flag: app.isSystemApp,
    ));

    // 1: app_is_enabled
    values.add(FeatureValue.validBoolean(
      name: 'app_is_enabled',
      index: 1,
      flag: app.isEnabled,
    ));

    // 2: app_target_sdk_version
    values.add(FeatureValue.validNumeric(
      name: 'app_target_sdk_version',
      index: 2,
      value: app.targetSdkVersion,
    ));

    // 3: app_min_sdk_version
    values.add(FeatureValue.validNumeric(
      name: 'app_min_sdk_version',
      index: 3,
      value: app.minSdkVersion,
    ));

    // 4: app_age_days
    if (nowMs != null && app.firstInstallTime > 0) {
      final diffMs = (nowMs - app.firstInstallTime).clamp(0, double.maxFinite.toInt());
      final days = diffMs / (1000.0 * 60 * 60 * 24);
      values.add(FeatureValue.validNumeric(
        name: 'app_age_days',
        index: 4,
        value: days,
      ));
    } else {
      values.add(FeatureValue.unknown(
        name: 'app_age_days',
        index: 4,
        dataType: FeatureDataType.numeric,
      ));
    }

    // Dynamic Permissions Extraction
    final grantedUpper = app.grantedPermissions.map((p) => p.toUpperCase()).toSet();

    // 5: app_requested_permissions_count
    values.add(FeatureValue.validCount(
      name: 'app_requested_permissions_count',
      index: 5,
      count: app.requestedPermissions.length,
    ));

    // 6: app_granted_permissions_count
    values.add(FeatureValue.validCount(
      name: 'app_granted_permissions_count',
      index: 6,
      count: app.grantedPermissions.length,
    ));

    // 7: app_denied_permissions_count
    values.add(FeatureValue.validCount(
      name: 'app_denied_permissions_count',
      index: 7,
      count: app.deniedPermissions.length,
    ));

    // 8: app_dangerous_granted_count
    values.add(FeatureValue.validCount(
      name: 'app_dangerous_granted_count',
      index: 8,
      count: app.dangerousGrantedPermissions.length,
    ));

    // 9: app_dangerous_requested_count
    values.add(FeatureValue.validCount(
      name: 'app_dangerous_requested_count',
      index: 9,
      count: app.dangerousRequestedPermissions.length,
    ));

    // 10: app_perm_camera_granted
    values.add(FeatureValue.validBoolean(
      name: 'app_perm_camera_granted',
      index: 10,
      flag: _hasPermission(grantedUpper, ['CAMERA']),
    ));

    // 11: app_perm_record_audio_granted
    values.add(FeatureValue.validBoolean(
      name: 'app_perm_record_audio_granted',
      index: 11,
      flag: _hasPermission(grantedUpper, ['RECORD_AUDIO']),
    ));

    // 12: app_perm_fine_location_granted
    values.add(FeatureValue.validBoolean(
      name: 'app_perm_fine_location_granted',
      index: 12,
      flag: _hasPermission(grantedUpper, ['ACCESS_FINE_LOCATION']),
    ));

    // 13: app_perm_contacts_granted
    values.add(FeatureValue.validBoolean(
      name: 'app_perm_contacts_granted',
      index: 13,
      flag: _hasPermission(grantedUpper, ['READ_CONTACTS', 'WRITE_CONTACTS']),
    ));

    // 14: app_perm_storage_granted
    values.add(FeatureValue.validBoolean(
      name: 'app_perm_storage_granted',
      index: 14,
      flag: _hasPermission(grantedUpper, [
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
        'MANAGE_EXTERNAL_STORAGE',
        'READ_MEDIA_IMAGES',
        'READ_MEDIA_VIDEO',
        'READ_MEDIA_AUDIO',
      ]),
    ));

    // 15: app_perm_sms_granted
    values.add(FeatureValue.validBoolean(
      name: 'app_perm_sms_granted',
      index: 15,
      flag: _hasPermission(grantedUpper, ['READ_SMS', 'RECEIVE_SMS', 'SEND_SMS']),
    ));

    // Special Capabilities & AppOps
    // 16: app_has_overlay_op
    values.add(FeatureValue.validBoolean(
      name: 'app_has_overlay_op',
      index: 16,
      flag: app.hasOverlayOp,
    ));

    // 17: app_has_usage_access_op
    values.add(FeatureValue.validBoolean(
      name: 'app_has_usage_access_op',
      index: 17,
      flag: app.hasUsageAccessOp,
    ));

    // Usage Dynamics (Honest missing handling)
    // 18: app_foreground_duration_ms_24h
    values.add(_extractUsageNumeric(
      name: 'app_foreground_duration_ms_24h',
      index: 18,
      value: app.foregroundDurationMs?.toDouble(),
      availability: app.usageAvailability,
    ));

    // 19: app_foreground_transitions_24h
    values.add(_extractUsageCount(
      name: 'app_foreground_transitions_24h',
      index: 19,
      value: app.foregroundTransitionCount,
      availability: app.usageAvailability,
    ));

    // 20: app_is_currently_foreground
    values.add(_extractUsageBoolean(
      name: 'app_is_currently_foreground',
      index: 20,
      value: app.isCurrentlyForeground,
      availability: app.usageAvailability,
    ));

    // 21: app_is_recently_used
    values.add(_extractUsageBoolean(
      name: 'app_is_recently_used',
      index: 21,
      value: app.isRecentlyUsedDerived,
      availability: app.usageAvailability,
    ));

    // Per-Application Network Traffic (Honest missing handling)
    // 22: app_upload_bytes_24h
    values.add(_extractNetworkNumeric(
      name: 'app_upload_bytes_24h',
      index: 22,
      bytes: app.uploadBytes,
      availability: app.networkUsageAvailability,
    ));

    // 23: app_download_bytes_24h
    values.add(_extractNetworkNumeric(
      name: 'app_download_bytes_24h',
      index: 23,
      bytes: app.downloadBytes,
      availability: app.networkUsageAvailability,
    ));

    // Device Context & Environment
    // 24: device_screen_locked
    values.add(_extractContextBoolean(
      name: 'device_screen_locked',
      index: 24,
      val: event.deviceContext.screenLocked,
    ));

    // 25: device_screen_on
    values.add(_extractContextBoolean(
      name: 'device_screen_on',
      index: 25,
      val: event.deviceContext.screenOn,
    ));

    // 26: device_is_secure
    values.add(_extractContextBoolean(
      name: 'device_is_secure',
      index: 26,
      val: event.deviceContext.isDeviceSecure,
    ));

    // 27: device_vpn_active
    values.add(_extractVpnActive(
      securityVpn: event.securityContext.vpnActive,
      networkVpn: event.network.vpnActive,
    ));

    // 28: device_developer_options_enabled
    values.add(_extractContextBoolean(
      name: 'device_developer_options_enabled',
      index: 28,
      val: event.securityContext.developerOptionsEnabled,
    ));

    // 29: device_adb_enabled
    values.add(_extractContextBoolean(
      name: 'device_adb_enabled',
      index: 29,
      val: event.securityContext.adbEnabled,
    ));

    // 30: device_accessibility_enabled
    values.add(_extractContextBoolean(
      name: 'device_accessibility_enabled',
      index: 30,
      val: event.securityContext.accessibilityEnabled,
    ));

    // 31: device_root_heuristic_detected
    values.add(FeatureValue.validBoolean(
      name: 'device_root_heuristic_detected',
      index: 31,
      flag: event.securityContext.isRootedHeuristic,
    ));

    return FeatureVector(
      schemaVersion: schema.schemaVersion,
      packageName: app.packageName,
      timestamp: event.timestamp,
      values: List.unmodifiable(values),
      schema: schema,
    );
  }

  bool _hasPermission(Set<String> granted, List<String> targets) {
    for (final t in targets) {
      if (granted.contains(t) || granted.any((p) => p.endsWith('.$t') || p.endsWith('_$t'))) {
        return true;
      }
    }
    return false;
  }

  FeatureValue _extractVpnActive({
    required bool? securityVpn,
    required bool networkVpn,
  }) {
    if (securityVpn == true || networkVpn == true) {
      return FeatureValue.validBoolean(
        name: 'device_vpn_active',
        index: 27,
        flag: true,
      );
    }
    if (securityVpn == false) {
      return FeatureValue.validBoolean(
        name: 'device_vpn_active',
        index: 27,
        flag: false,
      );
    }
    return FeatureValue.unknown(
      name: 'device_vpn_active',
      index: 27,
      dataType: FeatureDataType.boolean,
    );
  }

  FeatureValue _extractUsageNumeric({
    required String name,
    required int index,
    required double? value,
    required String availability,
  }) {
    switch (availability.toUpperCase()) {
      case 'VALID':
        if (value == null) {
          return FeatureValue.error(name: name, index: index, dataType: FeatureDataType.numeric);
        }
        return FeatureValue.validNumeric(name: name, index: index, value: value);
      case 'ZERO_REPORTED':
        return FeatureValue.zeroReported(name: name, index: index, dataType: FeatureDataType.numeric);
      case 'RESTRICTED':
        return FeatureValue.restricted(name: name, index: index, dataType: FeatureDataType.numeric);
      case 'UNAVAILABLE':
        return FeatureValue.unavailable(name: name, index: index, dataType: FeatureDataType.numeric);
      case 'ERROR':
        return FeatureValue.error(name: name, index: index, dataType: FeatureDataType.numeric);
      default:
        return value != null
            ? FeatureValue.validNumeric(name: name, index: index, value: value)
            : FeatureValue.unknown(name: name, index: index, dataType: FeatureDataType.numeric);
    }
  }

  FeatureValue _extractUsageCount({
    required String name,
    required int index,
    required int? value,
    required String availability,
  }) {
    switch (availability.toUpperCase()) {
      case 'VALID':
        if (value == null) {
          return FeatureValue.error(name: name, index: index, dataType: FeatureDataType.count);
        }
        return FeatureValue.validCount(name: name, index: index, count: value);
      case 'ZERO_REPORTED':
        return FeatureValue.zeroReported(name: name, index: index, dataType: FeatureDataType.count);
      case 'RESTRICTED':
        return FeatureValue.restricted(name: name, index: index, dataType: FeatureDataType.count);
      case 'UNAVAILABLE':
        return FeatureValue.unavailable(name: name, index: index, dataType: FeatureDataType.count);
      case 'ERROR':
        return FeatureValue.error(name: name, index: index, dataType: FeatureDataType.count);
      default:
        return value != null
            ? FeatureValue.validCount(name: name, index: index, count: value)
            : FeatureValue.unknown(name: name, index: index, dataType: FeatureDataType.count);
    }
  }

  FeatureValue _extractUsageBoolean({
    required String name,
    required int index,
    required bool? value,
    required String availability,
  }) {
    switch (availability.toUpperCase()) {
      case 'VALID':
        if (value == null) {
          return FeatureValue.error(name: name, index: index, dataType: FeatureDataType.boolean);
        }
        return FeatureValue.validBoolean(name: name, index: index, flag: value);
      case 'ZERO_REPORTED':
        return FeatureValue.zeroReported(name: name, index: index, dataType: FeatureDataType.boolean);
      case 'RESTRICTED':
        return FeatureValue.restricted(name: name, index: index, dataType: FeatureDataType.boolean);
      case 'UNAVAILABLE':
        return FeatureValue.unavailable(name: name, index: index, dataType: FeatureDataType.boolean);
      case 'ERROR':
        return FeatureValue.error(name: name, index: index, dataType: FeatureDataType.boolean);
      default:
        return value != null
            ? FeatureValue.validBoolean(name: name, index: index, flag: value)
            : FeatureValue.unknown(name: name, index: index, dataType: FeatureDataType.boolean);
    }
  }

  FeatureValue _extractNetworkNumeric({
    required String name,
    required int index,
    required int? bytes,
    required String availability,
  }) {
    switch (availability.toUpperCase()) {
      case 'VALID':
        if (bytes == null) {
          return FeatureValue.error(name: name, index: index, dataType: FeatureDataType.numeric);
        }
        return FeatureValue.validNumeric(name: name, index: index, value: bytes.toDouble());
      case 'ZERO_REPORTED':
        return FeatureValue.zeroReported(name: name, index: index, dataType: FeatureDataType.numeric);
      case 'DENIED':
        return FeatureValue.denied(name: name, index: index, dataType: FeatureDataType.numeric);
      case 'RESTRICTED':
        return FeatureValue.restricted(name: name, index: index, dataType: FeatureDataType.numeric);
      case 'UNAVAILABLE':
        return FeatureValue.unavailable(name: name, index: index, dataType: FeatureDataType.numeric);
      case 'ERROR':
        return FeatureValue.error(name: name, index: index, dataType: FeatureDataType.numeric);
      default:
        return bytes != null
            ? FeatureValue.validNumeric(name: name, index: index, value: bytes.toDouble())
            : FeatureValue.unknown(name: name, index: index, dataType: FeatureDataType.numeric);
    }
  }

  FeatureValue _extractContextBoolean({
    required String name,
    required int index,
    required bool? val,
  }) {
    if (val != null) {
      return FeatureValue.validBoolean(name: name, index: index, flag: val);
    }
    return FeatureValue.unknown(name: name, index: index, dataType: FeatureDataType.boolean);
  }
}
