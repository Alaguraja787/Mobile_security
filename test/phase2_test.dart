import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_privacy_security_project/models/app_telemetry.dart';
import 'package:mobile_privacy_security_project/models/privacy_event.dart';
import 'package:mobile_privacy_security_project/phase2/behaviour/behaviour_analyzer.dart';
import 'package:mobile_privacy_security_project/phase2/config/phase2_config.dart';
import 'package:mobile_privacy_security_project/phase2/dataset/dataset_collector.dart';
import 'package:mobile_privacy_security_project/phase2/dataset/dataset_record.dart';
import 'package:mobile_privacy_security_project/phase2/dataset/dataset_validator.dart';
import 'package:mobile_privacy_security_project/phase2/feature_engineering/feature_extractor.dart';
import 'package:mobile_privacy_security_project/phase2/feature_engineering/feature_value.dart';
import 'package:mobile_privacy_security_project/phase2/feature_engineering/feature_vector.dart';
import 'package:mobile_privacy_security_project/phase2/model/model_metadata.dart';
import 'package:mobile_privacy_security_project/phase2/model/model_status.dart';
import 'package:mobile_privacy_security_project/phase2/onnx/onnx_model_runner.dart';
import 'package:mobile_privacy_security_project/phase2/phase2_pipeline.dart';
import 'package:mobile_privacy_security_project/phase2/preprocessing/feature_preprocessor.dart';
import 'package:mobile_privacy_security_project/phase2/preprocessing/normalization_parameters.dart';
import 'package:mobile_privacy_security_project/phase2/preprocessing/preprocessed_tensor.dart';
import 'package:mobile_privacy_security_project/phase2/preprocessing/preprocessor_status.dart';
import 'package:mobile_privacy_security_project/phase2/schemas/feature_definition.dart';
import 'package:mobile_privacy_security_project/phase2/schemas/feature_schema.dart';

void main() {
  group('Phase 2 — A & B: Feature Schema Consistency & 32 Semantic Features', () {
    test('FeatureSchema v1 has exactly 32 features with deterministic ordering', () {
      final schema = FeatureSchema.v1;
      expect(schema.featureCount, equals(32));
      expect(schema.schemaVersion, equals('1.0.0'));

      for (int i = 0; i < 32; i++) {
        final def = schema.getFeatureByIndex(i);
        expect(def.index, equals(i));
        expect(schema.hasFeature(def.name), isTrue);
        expect(schema.getFeatureByName(def.name)?.index, equals(i));
      }
    });

    test('Every feature has explicit data type, missing strategy description, and normalization rule', () {
      final schema = FeatureSchema.v1;
      for (final def in schema.features) {
        expect(def.name, isNotEmpty);
        expect(def.missingStrategyDescription, isNotEmpty);
        expect(def.category, isNotEmpty);
        expect(def.description, isNotEmpty);
        expect(def.schemaVersion, equals('1.0.0'));
      }
    });
  });

  group('Phase 2 — C & D: Deterministic Feature Extraction & Timestamp Handling', () {
    late FeatureExtractor extractor;

    setUp(() {
      extractor = FeatureExtractor(schema: FeatureSchema.v1);
    });

    test('Feature extraction is strictly deterministic across multiple runs with identical input', () {
      final app = AppTelemetry(
        appName: 'Test Camera App',
        packageName: 'com.example.camera',
        uid: 10045,
        isSystemApp: false,
        isEnabled: true,
        targetSdkVersion: 34,
        minSdkVersion: 26,
        firstInstallTime: 1700000000000,
        requestedPermissions: ['android.permission.CAMERA', 'android.permission.INTERNET'],
        grantedPermissions: ['android.permission.CAMERA'],
        deniedPermissions: ['android.permission.INTERNET'],
        dangerousGrantedPermissions: ['android.permission.CAMERA'],
        dangerousRequestedPermissions: ['android.permission.CAMERA'],
        hasOverlayOp: true,
        hasUsageAccessOp: false,
        foregroundDurationMs: 120000,
        foregroundTransitionCount: 5,
        isCurrentlyForeground: true,
        isRecentlyUsedDerived: true,
        usageAvailability: 'VALID',
        uploadBytes: 500000,
        downloadBytes: 1500000,
        networkUsageAvailability: 'VALID',
      );

      final event = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(
          screenLocked: false,
          screenOn: true,
          isDeviceSecure: true,
          androidVersion: '14',
          sdkInt: 34,
        ),
        securityContext: SecurityContext(
          selfCanDrawOverlays: true,
          accessibilityEnabled: false,
          vpnActive: false,
          developerOptionsEnabled: false,
          adbEnabled: false,
          isRootedHeuristic: false,
        ),
        network: NetworkTelemetry(isConnected: true, transport: 'WIFI'),
        sensorTelemetry: SensorPrivacyTelemetry(cameraHardwareInUse: true),
        usageSummary: UsageSummary(usageAccessGranted: true, availability: 'VALID'),
        apps: [app.toJson()],
      );

      final vec1 = extractor.extract(app, event);
      final vec2 = extractor.extract(app, event);

      expect(vec1.length, equals(32));
      expect(vec2.length, equals(32));

      for (int i = 0; i < 32; i++) {
        expect(vec1.getValueByIndex(i).numericValue, equals(vec2.getValueByIndex(i).numericValue));
        expect(vec1.getValueByIndex(i).status, equals(vec2.getValueByIndex(i).status));
        expect(vec1.getValueByIndex(i).featureName, equals(vec2.getValueByIndex(i).featureName));
      }
    });

    test('Invalid event timestamp does not use DateTime.now() and sets app_age_days to UNKNOWN', () {
      final app = AppTelemetry(
        appName: 'Test Age App',
        packageName: 'com.example.age',
        firstInstallTime: 1700000000000,
      );

      final eventWithInvalidTimestamp = PrivacyEvent(
        timestamp: 'INVALID_TIMESTAMP_STRING',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );

      final vec = extractor.extract(app, eventWithInvalidTimestamp);
      final ageVal = vec.getValueByName('app_age_days');

      expect(ageVal.status, equals(FeatureAvailabilityStatus.unknown));
      expect(ageVal.numericValue, isNull);
      expect(ageVal.isMissing, isTrue);
    });

    test('App firstInstallTime <= 0 sets app_age_days to UNKNOWN', () {
      final app = AppTelemetry(
        appName: 'Zero Install App',
        packageName: 'com.example.zeroinstall',
        firstInstallTime: 0,
      );

      final event = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );

      final vec = extractor.extract(app, event);
      final ageVal = vec.getValueByName('app_age_days');

      expect(ageVal.status, equals(FeatureAvailabilityStatus.unknown));
      expect(ageVal.numericValue, isNull);
      expect(ageVal.isMissing, isTrue);
    });
  });

  group('Phase 2 — E & F: Honest Missing Telemetry & 32-Element Missingness Mask', () {
    late FeatureExtractor extractor;

    setUp(() {
      extractor = FeatureExtractor(schema: FeatureSchema.v1);
    });

    test('VPN feature preserves UNKNOWN when unconfirmed, and reports true/false when confirmed', () {
      final app = AppTelemetry(appName: 'VPN Test App', packageName: 'com.example.vpn');

      // 1. Confirmed active via SecurityContext
      final eventVpnActive = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(vpnActive: true),
        network: NetworkTelemetry(vpnActive: false),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );
      final vecActive = extractor.extract(app, eventVpnActive);
      expect(vecActive.getValueByName('device_vpn_active').numericValue, equals(1.0));
      expect(vecActive.getValueByName('device_vpn_active').isPresent, isTrue);

      // 2. Confirmed inactive via SecurityContext
      final eventVpnInactive = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(vpnActive: false),
        network: NetworkTelemetry(vpnActive: false),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );
      final vecInactive = extractor.extract(app, eventVpnInactive);
      expect(vecInactive.getValueByName('device_vpn_active').numericValue, equals(0.0));
      expect(vecInactive.getValueByName('device_vpn_active').isPresent, isTrue);

      // 3. Unconfirmed / null -> UNKNOWN (Missingness indicator = 1.0)
      final eventVpnUnknown = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(vpnActive: null),
        network: NetworkTelemetry(vpnActive: false),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );
      final vecUnknown = extractor.extract(app, eventVpnUnknown);
      final vpnFeature = vecUnknown.getValueByName('device_vpn_active');
      expect(vpnFeature.status, equals(FeatureAvailabilityStatus.unknown));
      expect(vpnFeature.numericValue, isNull);
      expect(vpnFeature.isMissing, isTrue);
    });

    test('Inconsistent telemetry (VALID status but null value) reports ERROR rather than converting to 0', () {
      final app = AppTelemetry(
        appName: 'Inconsistent App',
        packageName: 'com.example.inconsistent',
        uploadBytes: null,
        downloadBytes: null,
        networkUsageAvailability: 'VALID',
        foregroundDurationMs: null,
        usageAvailability: 'VALID',
      );

      final event = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );

      final vec = extractor.extract(app, event);
      expect(vec.getValueByName('app_upload_bytes_24h').status, equals(FeatureAvailabilityStatus.error));
      expect(vec.getValueByName('app_upload_bytes_24h').isMissing, isTrue);
      expect(vec.getValueByName('app_foreground_duration_ms_24h').status, equals(FeatureAvailabilityStatus.error));
      expect(vec.getValueByName('app_foreground_duration_ms_24h').isMissing, isTrue);
    });

    test('Missingness mask produces exactly 32 binary indicators (0.0 = present, 1.0 = missing)', () {
      final app = AppTelemetry(
        appName: 'Mask App',
        packageName: 'com.example.mask',
        uploadBytes: null,
        networkUsageAvailability: 'UNAVAILABLE',
      );

      final event = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );

      final vec = extractor.extract(app, event);
      final mask = vec.toMissingMask();

      expect(mask.length, equals(32));
      for (final m in mask) {
        expect(m == 0.0 || m == 1.0, isTrue);
      }
      expect(mask[22], equals(1.0)); // app_upload_bytes_24h at index 22 is missing
    });
  });

  group('Phase 2 — G, H, I, J: Preprocessor Contract (64 Elements) & Parameter Validation', () {
    test('FeaturePreprocessor reports PREPROCESSOR_NOT_READY when unfitted', () {
      final preprocessor = FeaturePreprocessor(
        normalizationParameters: NormalizationParameters.unfitted(),
      );

      expect(preprocessor.status, equals(PreprocessorStatus.notReady));

      final vector = createDummyFeatureVector();
      final result = preprocessor.process(vector);

      expect(result.status, equals(PreprocessorStatus.notReady));
      expect(result.tensor, isNull);
      expect(result.message, contains('PREPROCESSOR_NOT_READY'));
    });

    test('Incomplete parameters (missing std, negative IQR, or missing imputation) fails readiness check', () {
      final incompleteParams = NormalizationParameters(
        schemaVersion: '1.0.0',
        isFitted: true,
        means: {'app_target_sdk_version': 30.0},
        // Missing stds, mins, maxs, medians, iqrs, and imputationValues
      );

      final preprocessor = FeaturePreprocessor(
        normalizationParameters: incompleteParams,
      );

      expect(preprocessor.status, equals(PreprocessorStatus.notReady));
      final vector = createDummyFeatureVector();
      final result = preprocessor.process(vector);

      expect(result.status, equals(PreprocessorStatus.notReady));
      expect(result.tensor, isNull);
    });

    test('Schema version mismatch between Preprocessor and NormalizationParameters returns PREPROCESSOR_ERROR', () {
      final fittedParams = createCompleteFittedParameters(version: '2.0.0');

      final preprocessor = FeaturePreprocessor(
        schema: FeatureSchema.v1, // v1.0.0
        normalizationParameters: fittedParams,
      );

      expect(preprocessor.status, equals(PreprocessorStatus.error));
      final vector = createDummyFeatureVector();
      final result = preprocessor.process(vector);

      expect(result.status, equals(PreprocessorStatus.error));
      expect(result.message, contains('Schema version mismatch'));
    });

    test('FeatureVector constructor rejects schema version mismatch', () {
      expect(
        () => FeatureVector(
          schemaVersion: '2.0.0',
          packageName: 'com.example.mismatch',
          timestamp: '2026-08-17T12:00:00.000Z',
          values: createDummyFeatureValues(),
          schema: FeatureSchema.v1,
        ),
        throwsArgumentError,
      );
    });

    test('FeatureVector constructor rejects duplicate indices or names', () {
      final badValues = createDummyFeatureValues();
      // Introduce duplicate index at 1
      badValues[1] = FeatureValue.validBoolean(name: 'app_is_system_app', index: 0, flag: true);

      expect(
        () => FeatureVector(
          schemaVersion: '1.0.0',
          packageName: 'com.example.dup',
          timestamp: '2026-08-17T12:00:00.000Z',
          values: badValues,
          schema: FeatureSchema.v1,
        ),
        throwsArgumentError,
      );
    });

    test('FeaturePreprocessor produces exact [1, 64] tensor (32 semantic + 32 missingness mask) when fully calibrated', () {
      final fittedParams = createCompleteFittedParameters();
      final preprocessor = FeaturePreprocessor(
        normalizationParameters: fittedParams,
      );

      expect(preprocessor.status, equals(PreprocessorStatus.ready));

      final vector = createDummyFeatureVector();
      final result = preprocessor.process(vector);

      expect(result.status, equals(PreprocessorStatus.ready));
      expect(result.tensor, isNotNull);
      expect(result.tensor!.shape, equals([1, 64]));
      expect(result.tensor!.data.length, equals(64));

      // First 32 are semantic features, next 32 are missingness indicators
      for (int i = 32; i < 64; i++) {
        expect(result.tensor!.data[i] == 0.0 || result.tensor!.data[i] == 1.0, isTrue);
      }
    });
  });

  group('Phase 2 — K, L, M: Model Readiness, ONNX Contract & Output Validation', () {
    test('OnnxModelRunner reports MODEL_NOT_READY when model asset path is null or unloaded', () async {
      final runner = OnnxModelRunner(modelAssetPath: null);
      expect(runner.status, equals(ModelStatus.notReady));
      expect(runner.isReady, isFalse);

      await runner.load();
      expect(runner.status, equals(ModelStatus.notReady));

      final dummyTensor = preprocessed64Tensor();
      final result = await runner.predict(dummyTensor);

      expect(result.status, equals(ModelStatus.notReady));
      expect(result.anomalyScore, isNull);
      expect(result.confidence, isNull);
      expect(result.message, contains('MODEL_NOT_READY'));
    });

    test('ModelMetadata contract validation rejects input shape other than [1, 64]', () {
      const invalidMetadata = ModelMetadata(
        modelName: 'old_model',
        modelVersion: '1.0.0',
        featureSchemaVersion: '1.0.0',
        inputShape: [1, 32], // Old invalid shape!
        outputShape: [1, 2],
        trainedAt: '2026-08-17T12:00:00Z',
        architecture: 'RandomForest',
        description: 'Old model',
      );

      final errors = invalidMetadata.validateContract(FeatureSchema.v1);
      expect(errors, isNotEmpty);
      expect(errors.first, contains('expected [1, 64]'));
    });

    test('ModelMetadata contract validation accepts valid [1, 64] contract', () {
      const validMetadata = ModelMetadata(
        modelName: 'valid_onnx_model',
        modelVersion: '1.0.0',
        featureSchemaVersion: '1.0.0',
        inputShape: [1, 64],
        outputShape: [1, 2],
        trainedAt: '2026-08-17T12:00:00Z',
        architecture: 'IsolationForest',
        description: 'Trained from real physical device telemetry',
      );

      final errors = validMetadata.validateContract(FeatureSchema.v1);
      expect(errors, isEmpty);
      expect(validMetadata.isValidFor(FeatureSchema.v1), isTrue);
    });
  });

  group('Phase 2 — N & O: Dataset Validation & Buffer Limit Enforcement', () {
    test('DatasetValidator rejects NaN and Infinite values', () {
      final validator = DatasetValidator();
      final badValues = createDummyFeatureValues();
      badValues[2] = const FeatureValue(
        featureName: 'app_target_sdk_version',
        featureIndex: 2,
        dataType: FeatureDataType.numeric,
        rawValue: double.nan,
        numericValue: double.nan,
        status: FeatureAvailabilityStatus.valid,
      );

      final badVector = FeatureVector(
        schemaVersion: '1.0.0',
        packageName: 'com.example.nan',
        timestamp: '2026-08-17T12:00:00.000Z',
        values: badValues,
      );

      final record = DatasetRecord(
        recordId: 'rec_nan',
        deviceIdHash: 'dev123',
        androidVersion: '14',
        sdkInt: 34,
        timestamp: '2026-08-17T12:00:00.000Z',
        packageName: 'com.example.nan',
        collectorHealthStatus: 'HEALTHY',
        rawTelemetry: {},
        featureVector: badVector,
      );

      final errors = validator.validateRecord(record);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('NaN')), isTrue);
    });

    test('DatasetCollector enforces maxBufferSize with deterministic FIFO eviction', () {
      final collector = DatasetCollector(maxBufferSize: 3, requireExplicitSession: false);

      final app = AppTelemetry(
        appName: 'Buffer App',
        packageName: 'com.example.buf',
        uid: 1001,
      );

      for (int i = 0; i < 5; i++) {
        final event = PrivacyEvent(
          timestamp: '2026-08-17T12:0$i:00.000Z',
          deviceContext: DeviceContext(brand: 'Google', model: 'Pixel 8', board: 'shiba', sdkInt: 34),
          securityContext: SecurityContext(),
          network: NetworkTelemetry(),
          sensorTelemetry: SensorPrivacyTelemetry(),
          usageSummary: UsageSummary(),
          apps: [],
        );
        collector.captureRecord(app: app, event: event);
      }

      expect(collector.recordCount, equals(3));
      // First 2 evicted; remaining should be timestamps for i=2, 3, 4
      expect(collector.records.first.timestamp, equals('2026-08-17T12:02:00.000Z'));
      expect(collector.records.last.timestamp, equals('2026-08-17T12:04:00.000Z'));
    });
  });

  group('Phase 2 — P & Q: Phase2Config Switches & Pipeline Execution Without Model', () {
    test('Phase2Config enableOnnxRuntime: false skips ONNX inference', () async {
      final pipeline = Phase2Pipeline(
        config: const Phase2Config(enableOnnxRuntime: false),
      );
      await pipeline.initialize();

      final app = AppTelemetry(appName: 'Config Test App', packageName: 'com.example.test');
      final event = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );

      final result = await pipeline.analyzeApp(app: app, event: event);
      expect(result.modelStatus, equals(ModelStatus.notReady));
      expect(result.message, contains('ONNX runtime disabled by configuration'));
    });

    test('Phase2Config enableObservationAnalysis: false returns empty behaviour indicators', () async {
      final pipeline = Phase2Pipeline(
        config: const Phase2Config(enableObservationAnalysis: false),
      );
      await pipeline.initialize();

      final app = AppTelemetry(
        appName: 'Overlay Test App',
        packageName: 'com.example.test',
        hasOverlayOp: true, // would normally trigger observation
      );
      final event = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [],
      );

      final result = await pipeline.analyzeApp(app: app, event: event);
      expect(result.behaviourIndicators, isEmpty);
    });

    test('BehaviourAnalyzer extracts purely factual observations without security verdicts', () {
      const analyzer = BehaviourAnalyzer();
      final app = AppTelemetry(
        appName: 'Factual App',
        packageName: 'com.example.factual',
        hasOverlayOp: true,
        hasUsageAccessOp: true,
        dangerousGrantedPermissions: ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO', 'android.permission.READ_CONTACTS', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.READ_SMS'],
        grantedPermissions: ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO'],
        uploadBytes: 10 * 1024 * 1024,
        networkUsageAvailability: 'VALID',
      );

      final event = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(screenLocked: true),
        securityContext: SecurityContext(isRootedHeuristic: true, accessibilityEnabled: true),
        network: NetworkTelemetry(),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [app.toJson()],
      );

      final extractor = FeatureExtractor();
      final vector = extractor.extract(app, event);
      final observations = analyzer.analyzeObservations(vector);

      expect(observations, isNotEmpty);
      final codes = observations.map((o) => o.code).toSet();
      expect(codes.contains('SCREEN_LOCKED_HEAVY_UPLOAD'), isTrue);
      expect(codes.contains('OVERLAY_CAPABILITY_ENABLED'), isTrue);
      expect(codes.contains('USAGE_ACCESS_CAPABILITY_ENABLED'), isTrue);
      expect(codes.contains('CAMERA_AND_MIC_GRANTED'), isTrue);
      expect(codes.contains('HIGH_DANGEROUS_PERMISSIONS_COUNT'), isTrue);
      expect(codes.contains('ROOT_HEURISTIC_PRESENT'), isTrue);
      expect(codes.contains('ACCESSIBILITY_ACTIVE'), isTrue);

      for (final obs in observations) {
        expect(obs.message.toLowerCase().contains('malicious'), isFalse);
        expect(obs.message.toLowerCase().contains('high risk'), isFalse);
      }
    });

    test('End-to-end Phase2Pipeline produces Phase2Result with honest MODEL_NOT_READY and PREPROCESSOR_NOT_READY', () async {
      final pipeline = Phase2Pipeline();
      await pipeline.initialize();

      final app = AppTelemetry(
        appName: 'Live Test App',
        packageName: 'com.example.live',
        uid: 10099,
        uploadBytes: 1024,
        downloadBytes: 2048,
        networkUsageAvailability: 'VALID',
      );

      final event = PrivacyEvent(
        timestamp: '2026-08-17T12:00:00.000Z',
        deviceContext: DeviceContext(),
        securityContext: SecurityContext(),
        network: NetworkTelemetry(),
        sensorTelemetry: SensorPrivacyTelemetry(),
        usageSummary: UsageSummary(),
        apps: [app.toJson()],
      );

      final result = await pipeline.analyzeApp(app: app, event: event);

      expect(result.packageName, equals('com.example.live'));
      expect(result.modelStatus, equals(ModelStatus.notReady));
      expect(result.preprocessorStatus, equals(PreprocessorStatus.notReady));
      expect(result.featureSchemaVersion, equals('1.0.0'));
      expect(result.anomalyScore, isNull);
      expect(result.confidence, isNull);
      expect(result.isModelInferenceAvailable, isFalse);
      expect(result.evidence, isNotEmpty);
      expect(result.evidence.length, equals(32));
    });
  });
}

PreprocessedTensor preprocessed64Tensor() {
  return PreprocessedTensor(
    data: Float32List(64),
    shape: const [1, 64],
    schemaVersion: '1.0.0',
  );
}

List<FeatureValue> createDummyFeatureValues() {
  final schema = FeatureSchema.v1;
  return List.generate(
    32,
    (i) {
      final def = schema.getFeatureByIndex(i);
      return FeatureValue.validNumeric(name: def.name, index: i, value: 1.0);
    },
  );
}

FeatureVector createDummyFeatureVector({String version = '1.0.0'}) {
  return FeatureVector(
    schemaVersion: version,
    packageName: 'com.example.dummy',
    timestamp: '2026-08-17T12:00:00.000Z',
    values: createDummyFeatureValues(),
    schema: FeatureSchema.v1,
  );
}

NormalizationParameters createCompleteFittedParameters({String version = '1.0.0'}) {
  final schema = FeatureSchema.v1;
  final means = <String, double>{};
  final stds = <String, double>{};
  final mins = <String, double>{};
  final maxs = <String, double>{};
  final medians = <String, double>{};
  final iqrs = <String, double>{};
  final imp = <String, double>{};

  for (final f in schema.features) {
    imp[f.name] = 0.0;
    switch (f.normalizationType) {
      case NormalizationType.standard:
        means[f.name] = 10.0;
        stds[f.name] = 2.0;
        break;
      case NormalizationType.minMax:
        mins[f.name] = f.minExpected ?? 0.0;
        maxs[f.name] = f.maxExpected ?? 100.0;
        break;
      case NormalizationType.robust:
        medians[f.name] = 5.0;
        iqrs[f.name] = 2.5;
        break;
      case NormalizationType.none:
      case NormalizationType.logScale:
        break;
    }
  }

  return NormalizationParameters(
    schemaVersion: version,
    isFitted: true,
    means: means,
    stds: stds,
    mins: mins,
    maxs: maxs,
    medians: medians,
    iqrs: iqrs,
    imputationValues: imp,
  );
}
