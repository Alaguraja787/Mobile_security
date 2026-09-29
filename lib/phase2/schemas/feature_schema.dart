import 'feature_definition.dart';

/// Versioned Feature Schema registry for Phase 2 Local Intelligence.
/// 
/// Maintains deterministic ordering and immutable definitions of all features
/// extracted from Phase 1 PrivacyEvent and AppTelemetry.
class FeatureSchema {
  static const String version = '1.0.0';

  final String schemaVersion;
  final List<FeatureDefinition> features;
  final Map<String, int> _nameToIndexMap;

  FeatureSchema._({
    required this.schemaVersion,
    required this.features,
  }) : _nameToIndexMap = {
          for (var f in features) f.name: f.index,
        };

  /// FeatureSchema v1: 32 deterministic, explicit features across 6 categories.
  static final FeatureSchema v1 = FeatureSchema._(
    schemaVersion: version,
    features: List.unmodifiable([
      // Category 1: Application Identity & Installation (Indices 0..4)
      const FeatureDefinition(
        name: 'app_is_system_app',
        index: 0,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Boolean flag from ApplicationInfo.FLAG_SYSTEM. Always VALID for installed packages; 0=user, 1=system.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'app_identity',
        description: 'Whether the application is installed in system image partition.',
      ),
      const FeatureDefinition(
        name: 'app_is_enabled',
        index: 1,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Boolean flag from ApplicationInfo.enabled. Always VALID; 0=disabled, 1=enabled.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'app_identity',
        description: 'Whether the application package is currently enabled by user/system.',
      ),
      const FeatureDefinition(
        name: 'app_target_sdk_version',
        index: 2,
        dataType: FeatureDataType.numeric,
        minExpected: 0.0,
        maxExpected: 36.0,
        missingStrategyDescription: 'Target SDK integer from ApplicationInfo.targetSdkVersion. VALID; range 0..36.',
        normalizationType: NormalizationType.minMax,
        schemaVersion: version,
        category: 'app_identity',
        description: 'Target Android API level compiled by the application.',
      ),
      const FeatureDefinition(
        name: 'app_min_sdk_version',
        index: 3,
        dataType: FeatureDataType.numeric,
        minExpected: 0.0,
        maxExpected: 36.0,
        missingStrategyDescription: 'Minimum SDK integer from ApplicationInfo.minSdkVersion. VALID; range 0..36.',
        normalizationType: NormalizationType.minMax,
        schemaVersion: version,
        category: 'app_identity',
        description: 'Minimum Android API level supported by the application.',
      ),
      const FeatureDefinition(
        name: 'app_age_days',
        index: 4,
        dataType: FeatureDataType.numeric,
        minExpected: 0.0,
        maxExpected: 10000.0,
        missingStrategyDescription: 'Derived age in days from firstInstallTime. If firstInstallTime is 0/unavailable, preserves UNKNOWN status.',
        normalizationType: NormalizationType.standard,
        schemaVersion: version,
        category: 'app_identity',
        description: 'Days since the application was first installed on this device.',
      ),

      // Category 2: Dynamic Permissions & Dangerous Classification (Indices 5..15)
      const FeatureDefinition(
        name: 'app_requested_permissions_count',
        index: 5,
        dataType: FeatureDataType.count,
        minExpected: 0.0,
        maxExpected: 200.0,
        missingStrategyDescription: 'Count of requested permissions from PackageInfo.requestedPermissions. VALID integer count.',
        normalizationType: NormalizationType.standard,
        schemaVersion: version,
        category: 'permissions',
        description: 'Total number of permissions declared in the application manifest.',
      ),
      const FeatureDefinition(
        name: 'app_granted_permissions_count',
        index: 6,
        dataType: FeatureDataType.count,
        minExpected: 0.0,
        maxExpected: 200.0,
        missingStrategyDescription: 'Count of currently granted permissions verified at runtime. VALID integer count.',
        normalizationType: NormalizationType.standard,
        schemaVersion: version,
        category: 'permissions',
        description: 'Total number of permissions actively granted to the application.',
      ),
      const FeatureDefinition(
        name: 'app_denied_permissions_count',
        index: 7,
        dataType: FeatureDataType.count,
        minExpected: 0.0,
        maxExpected: 200.0,
        missingStrategyDescription: 'Count of denied permissions derived from requested - granted. VALID integer count.',
        normalizationType: NormalizationType.standard,
        schemaVersion: version,
        category: 'permissions',
        description: 'Total number of requested permissions not granted or revoked.',
      ),
      const FeatureDefinition(
        name: 'app_dangerous_granted_count',
        index: 8,
        dataType: FeatureDataType.count,
        minExpected: 0.0,
        maxExpected: 50.0,
        missingStrategyDescription: 'Count of PROTECTION_DANGEROUS permissions granted. VALID integer count.',
        normalizationType: NormalizationType.standard,
        schemaVersion: version,
        category: 'permissions',
        description: 'Number of dangerous runtime permissions actively granted.',
      ),
      const FeatureDefinition(
        name: 'app_dangerous_requested_count',
        index: 9,
        dataType: FeatureDataType.count,
        minExpected: 0.0,
        maxExpected: 50.0,
        missingStrategyDescription: 'Count of PROTECTION_DANGEROUS permissions requested in manifest. VALID integer count.',
        normalizationType: NormalizationType.standard,
        schemaVersion: version,
        category: 'permissions',
        description: 'Number of dangerous runtime permissions requested in manifest.',
      ),
      const FeatureDefinition(
        name: 'app_perm_camera_granted',
        index: 10,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Binary check for android.permission.CAMERA in granted permissions. VALID (0 or 1).',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'permissions',
        description: 'Whether CAMERA permission is granted to this app.',
      ),
      const FeatureDefinition(
        name: 'app_perm_record_audio_granted',
        index: 11,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Binary check for android.permission.RECORD_AUDIO in granted permissions. VALID (0 or 1).',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'permissions',
        description: 'Whether RECORD_AUDIO (microphone) permission is granted.',
      ),
      const FeatureDefinition(
        name: 'app_perm_fine_location_granted',
        index: 12,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Binary check for ACCESS_FINE_LOCATION in granted permissions. VALID (0 or 1).',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'permissions',
        description: 'Whether precise ACCESS_FINE_LOCATION permission is granted.',
      ),
      const FeatureDefinition(
        name: 'app_perm_contacts_granted',
        index: 13,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Binary check for READ_CONTACTS in granted permissions. VALID (0 or 1).',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'permissions',
        description: 'Whether READ_CONTACTS permission is granted.',
      ),
      const FeatureDefinition(
        name: 'app_perm_storage_granted',
        index: 14,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Binary check for READ_EXTERNAL_STORAGE / MANAGE_EXTERNAL_STORAGE. VALID (0 or 1).',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'permissions',
        description: 'Whether external storage access permissions are granted.',
      ),
      const FeatureDefinition(
        name: 'app_perm_sms_granted',
        index: 15,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Binary check for READ_SMS / RECEIVE_SMS / SEND_SMS in granted permissions. VALID (0 or 1).',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'permissions',
        description: 'Whether SMS access permissions are granted.',
      ),

      // Category 3: Special Capabilities & AppOps (Indices 16..17)
      const FeatureDefinition(
        name: 'app_has_overlay_op',
        index: 16,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW status. VALID (0=no, 1=has overlay op).',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'app_ops',
        description: 'Whether the app possesses active SYSTEM_ALERT_WINDOW overlay capability.',
      ),
      const FeatureDefinition(
        name: 'app_has_usage_access_op',
        index: 17,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'AppOpsManager.OPSTR_GET_USAGE_STATS status. VALID (0=no, 1=has usage op).',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'app_ops',
        description: 'Whether the app has permission to query package usage stats.',
      ),

      // Category 4: Usage & Foreground Dynamics (Indices 18..21)
      const FeatureDefinition(
        name: 'app_foreground_duration_ms_24h',
        index: 18,
        dataType: FeatureDataType.numeric,
        minExpected: 0.0,
        maxExpected: 86400000.0,
        missingStrategyDescription: 'UsageStatsManager 24h interval duration in ms. Preserves RESTRICTED, UNAVAILABLE, ERROR when usage access is denied or query fails.',
        normalizationType: NormalizationType.logScale,
        schemaVersion: version,
        category: 'usage',
        description: 'Total foreground execution duration in milliseconds over past 24 hours.',
      ),
      const FeatureDefinition(
        name: 'app_foreground_transitions_24h',
        index: 19,
        dataType: FeatureDataType.count,
        minExpected: 0.0,
        maxExpected: 10000.0,
        missingStrategyDescription: 'UsageEvents MOVE_TO_FOREGROUND transition count. Preserves RESTRICTED/UNAVAILABLE/ERROR status when events unavailable.',
        normalizationType: NormalizationType.standard,
        schemaVersion: version,
        category: 'usage',
        description: 'Number of times the application transitioned into the foreground over past 24 hours.',
      ),
      const FeatureDefinition(
        name: 'app_is_currently_foreground',
        index: 20,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Real-time snapshot from latest UsageEvents transition. Preserves RESTRICTED/UNAVAILABLE/ERROR when usage access denied.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'usage',
        description: 'Whether the application is currently visible in foreground.',
      ),
      const FeatureDefinition(
        name: 'app_is_recently_used',
        index: 21,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Derived heuristic (lastTimeUsed within 5 minutes). Preserves RESTRICTED/UNAVAILABLE/ERROR when lastTimeUsed is null.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'usage',
        description: 'Whether the application was active within the past 5 minutes.',
      ),

      // Category 5: Per-Application Network Traffic (Indices 22..23)
      const FeatureDefinition(
        name: 'app_upload_bytes_24h',
        index: 22,
        dataType: FeatureDataType.numeric,
        minExpected: 0.0,
        maxExpected: null,
        missingStrategyDescription: 'NetworkStatsManager per-UID tx bytes. Preserves ZERO_REPORTED for genuine zero, and RESTRICTED/UNAVAILABLE/ERROR/DENIED for query failures.',
        normalizationType: NormalizationType.logScale,
        schemaVersion: version,
        category: 'network',
        description: 'Total transmitted network bytes attributed to app UID in past 24 hours.',
      ),
      const FeatureDefinition(
        name: 'app_download_bytes_24h',
        index: 23,
        dataType: FeatureDataType.numeric,
        minExpected: 0.0,
        maxExpected: null,
        missingStrategyDescription: 'NetworkStatsManager per-UID rx bytes. Preserves ZERO_REPORTED for genuine zero, and RESTRICTED/UNAVAILABLE/ERROR/DENIED for query failures.',
        normalizationType: NormalizationType.logScale,
        schemaVersion: version,
        category: 'network',
        description: 'Total received network bytes attributed to app UID in past 24 hours.',
      ),

      // Category 6: Device Environment & Security Context (Indices 24..31)
      const FeatureDefinition(
        name: 'device_screen_locked',
        index: 24,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'KeyguardManager.isKeyguardLocked state. Preserves UNKNOWN/ERROR if null.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'device_security',
        description: 'Whether the device keyguard lock is currently active.',
      ),
      const FeatureDefinition(
        name: 'device_screen_on',
        index: 25,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'PowerManager.isInteractive state. Preserves UNKNOWN/ERROR if null.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'device_security',
        description: 'Whether the device display is interactive / turned on.',
      ),
      const FeatureDefinition(
        name: 'device_is_secure',
        index: 26,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'KeyguardManager.isDeviceSecure state (PIN/Pattern/Biometrics). Preserves UNKNOWN/ERROR if null.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'device_security',
        description: 'Whether the device has a secure screen lock configured.',
      ),
      const FeatureDefinition(
        name: 'device_vpn_active',
        index: 27,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'ConnectivityManager VPN transport state. Preserves UNKNOWN/ERROR if null.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'device_security',
        description: 'Whether a VPN interface is active on the device.',
      ),
      const FeatureDefinition(
        name: 'device_developer_options_enabled',
        index: 28,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Settings.Global.DEVELOPMENT_SETTINGS_ENABLED. Preserves UNKNOWN/ERROR if null.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'device_security',
        description: 'Whether Developer Options are enabled in device settings.',
      ),
      const FeatureDefinition(
        name: 'device_adb_enabled',
        index: 29,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Settings.Global.ADB_ENABLED. Preserves UNKNOWN/ERROR if null.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'device_security',
        description: 'Whether USB debugging / ADB is enabled on the device.',
      ),
      const FeatureDefinition(
        name: 'device_accessibility_enabled',
        index: 30,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Settings.Secure.ACCESSIBILITY_ENABLED. Preserves UNKNOWN/ERROR if null.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'device_security',
        description: 'Whether accessibility services are active on the device.',
      ),
      const FeatureDefinition(
        name: 'device_root_heuristic_detected',
        index: 31,
        dataType: FeatureDataType.boolean,
        minExpected: 0.0,
        maxExpected: 1.0,
        missingStrategyDescription: 'Root heuristic detection indicator from SecurityContext. VALID boolean flag.',
        normalizationType: NormalizationType.none,
        schemaVersion: version,
        category: 'device_security',
        description: 'Whether heuristic root indicators (su binaries, test-keys) were detected.',
      ),
    ]),
  );

  int get featureCount => features.length;

  List<String> get featureNames => features.map((f) => f.name).toList();

  FeatureDefinition? getFeatureByName(String name) {
    final idx = _nameToIndexMap[name];
    if (idx == null) return null;
    return features[idx];
  }

  FeatureDefinition getFeatureByIndex(int index) {
    if (index < 0 || index >= features.length) {
      throw RangeError.range(index, 0, features.length - 1, 'Feature index out of range');
    }
    return features[index];
  }

  bool hasFeature(String name) => _nameToIndexMap.containsKey(name);

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'featureCount': featureCount,
      'features': features.map((f) => f.toJson()).toList(),
    };
  }
}
