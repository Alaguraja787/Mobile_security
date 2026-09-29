# Privacy Sentinel AI — Technical Project Audit & Architecture Review

**Document Version:** 1.0.0  
**Project:** `mobile_privacy_security_project` (Privacy Sentinel AI)  
**Target Environment:** Android API 26 (Android 8.0 Oreo) through API 36 (Android 16 Baklava) / Flutter 3.x / Kotlin 1.9+ / JVM 17  
**Audit Scope:** End-to-End Codebase Inspection, Mobile Device Layer Verification, Data Flow Analysis, ML/Edge AI Pipeline, and Phase-1 Completion Assessment.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Complete Project Architecture](#2-complete-project-architecture)
3. [Repository Folder Structure & File Map](#3-repository-folder-structure--file-map)
4. [Phase-Wise Architecture & Project Roadmap](#4-phase-wise-architecture--project-roadmap)
5. [Mobile Device Layer Deep Dive](#5-mobile-device-layer-deep-dive)
6. [Detailed File-by-File Technical Audit (15-Point Criteria)](#6-detailed-file-by-file-technical-audit-15-point-criteria)
   - 6.1 [Kotlin Native Layer](#61-kotlin-native-layer)
   - 6.2 [Flutter Telemetry & Collector Pipeline](#62-flutter-telemetry--collector-pipeline)
   - 6.3 [Data Models & Diagnostics](#63-data-models--diagnostics)
   - 6.4 [AI / ML Edge Pipeline & Agents](#64-ai--ml-edge-pipeline--agents)
   - 6.5 [Services, Core, UI & Widgets](#65-services-core-ui--widgets)
7. [End-to-End Data Flow Trace (Hardware → Local Edge AI)](#7-end-to-end-data-flow-trace-hardware--local-edge-ai)
8. [MethodChannel Communication Specification](#8-methodchannel-communication-specification)
9. [Telemetry Classification & Scoping Matrix](#9-telemetry-classification--scoping-matrix)
   - 9.1 Device-Level vs. App-Level Telemetry
   - 9.2 Real-Time vs. Periodic vs. Event-Driven vs. Historical
   - 9.3 Real Ground-Truth Data vs. Derived Heuristic Signals
10. [Android System Permissions, API Restrictions & Platform Boundaries](#10-android-system-permissions-api-restrictions--platform-boundaries)
11. [Codebase Anomalies & Critical Audit Findings](#11-codebase-anomalies--critical-audit-findings)
    - 11.1 Hardcoded Values & Magic Numbers
    - 11.2 Incorrect Implementations & Architectural Mismatches
    - 11.3 Duplicate / Redundant Code & Dead Code
    - 11.4 Empty / Stubbed Files (Zero-Byte Files)
    - 11.5 The ONNX Model & Feature Dimension Mismatch
12. [Phase 1 Completion Assessment & Component Scoring](#12-phase-1-completion-assessment--component-scoring)
13. [Actionable Recommendations & Roadmap](#13-actionable-recommendations--roadmap)

---

## 1. Executive Summary

Privacy Sentinel AI is an on-device mobile privacy and security monitoring system built with **Flutter (Dart)** for the application layer and **Kotlin** for the native Android device interface. The core objective of the project is to collect legitimate device-level and application-level telemetry, detect privacy anomalies and risk postures, and execute on-device local edge AI inference via an ONNX Runtime model (`privacy_guardian.onnx`).

### Key Findings:
- **Mobile Device Native Layer (Kotlin):** The Android native layer is **exceptionally robust and well-engineered**. It implements 8 dedicated Kotlin collectors that interface directly with Android system services (`PackageManager`, `UsageStatsManager`, `UsageEvents`, `NetworkStatsManager`, `TrafficStats`, `CameraManager`, `AudioManager`, `PowerManager`, `KeyguardManager`, `Settings`, and `AppOpsManager`). It rigorously separates device context from app-specific telemetry, avoids fabricating sandbox-violating data (e.g. unprivileged per-app camera attribution), handles API version branches up to Android 15/16 (API 36), and runs a dataSync foreground service.
- **Flutter Telemetry Pipeline:** The Dart bridge (`AndroidCollector`, `TelemetryService`, `PrivacyEvent`, `AppTelemetryBuilder`, `AppTelemetry`) cleanly consumes the normalized JSON map from the native layer and converts it into strongly typed Dart domain objects.
- **Telemetry Diagnostics UI:** A comprehensive development tool (`TelemetryDiagnosticsScreen`) exists to inspect live hardware, security, network, sensor, and app usage metrics with verification metadata.
- **Critical Architectural Gaps:**
  1. **Edge AI Feature Mismatch:** The ONNX model was trained in Python (`train_model.py`) expecting a vector of **196 features** (`float_input` shape `[None, 196]`). The Dart `FeatureEncoder` only produces **11 features**, and `ModelRunner` pads indices 11..195 with zeroes before running inference. Furthermore, `ModelRunner` falls back to a manual arithmetic sum if the output contains `"1"`.
  2. **Empty Stub Files (Zero-Byte Files):** 15 Dart files in `lib/` are completely empty (0 bytes), including key UI screens (`alerts_screen.dart`, `app_details_screen.dart`, `monitor_screen.dart`, `settings_screen.dart`, `splash_screen.dart`), services (`cloud_ai_service.dart`, `storage_service.dart`), and utils (`date_formatter.dart`, `logger.dart`, `permission_helper.dart`, `risk_calculator.dart`).
  3. **Disconnected Multi-Agent Architecture:** Several agent files (`BehaviorAgent`, `ContextAgent`, `DecisionAgent`, `LocalTriageEngine`, `PermissionRiskAgent`, `MemoryAgent`) exist as isolated, standalone classes and are not connected to the main telemetry stream in `DashboardScreen`.

---

## 2. Complete Project Architecture

```
+---------------------------------------------------------------------------------------------------+
|                                      ANDROID DEVICE HARDWARE                                      |
|    Camera Hardware  |  Microphone / Audio DSP  |  Network Interfaces (Wi-Fi, LTE, 5G)  |  Battery   |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
|                                        ANDROID OS SYSTEM APIs                                     |
|  PackageManager  |  UsageStatsManager  |  NetworkStatsManager  |  TrafficStats  |  CameraManager  |
|  AudioManager    |  PowerManager       |  KeyguardManager      |  Settings      |  AppOpsManager  |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
|                                 NATIVE KOTLIN TELEMETRY LAYER                                     |
|  - PermissionMonitor.kt          : Package inventory, dynamic dangerous flags, AppOps              |
|  - AppUsageMonitor.kt            : UsageEvents foreground transitions, daily duration             |
|  - NetworkMonitor.kt             : TrafficStats totals, per-UID NetworkStatsManager Wi-Fi/Cell    |
|  - DeviceContextCollector.kt     : Hardware static info, battery broadcast, screen/lock/power     |
|  - DeviceSecurityMonitor.kt      : Overlay/Doze/Install ops, Dev/ADB, Accessibility, Root heuristic|
|  - SensorPrivacyMonitor.kt       : Camera AvailabilityCallback, Audio active recordings           |
|  - TelemetryForegroundService.kt : 30s background periodic collector (dataSync foreground service)|
|                                                 │                                                 |
|                        AndroidTelemetryCollector.kt (Aggregator & Joins)                          |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
|                        MethodChannel ("privacy_sentinel") in MainActivity.kt                     |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
|                                   FLUTTER / DART TELEMETRY PIPELINE                               |
|  AndroidCollector (android_collector.dart)                                                        |
|     │                                                                                             |
|     ├──> TelemetryService (telemetry_service.dart)  [Periodic Timer / Broadcast Stream]           |
|     │       │                                                                                     |
|     │       ▼                                                                                     |
|     └──> PrivacyEvent (models/privacy_event.dart)   [Unified Snapshot Model]                      |
|             │                                                                                     |
|             ▼                                                                                     |
|          AppTelemetryBuilder (telemetry/app_telemetry_builder.dart)                               |
|             │                                                                                     |
|             ▼                                                                                     |
|          List<AppTelemetry> (models/app_telemetry.dart)                                           |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
|                                      EDGE AI & AGENT ENGINE                                       |
|  RiskAgent (agents/risk_agent.dart)                                                               |
|     ├──> FeatureEncoder (ml/feature_encoder.dart)   [11 extracted features]                       |
|     └──> ModelRunner (ml/model_runner.dart)         [ONNX Runtime Session: privacy_guardian.onnx] |
|                                                                                                   |
|  * Standalone / Unconnected Agents:                                                               |
|    - LocalTriageEngine.dart   (Rule-based heuristic scorer)                                       |
|    - BehaviorAgent.dart       (Event-level anomaly detector)                                      |
|    - ContextAgent.dart        (Permission context checker)                                        |
|    - DecisionAgent.dart       (Action classifier: BLOCK / WARN / ALLOW)                            |
|    - PermissionRiskAgent.dart (Static weight calculator)                                          |
|    - MemoryAgent.dart         (SharedPreferences behavior cache)                                  |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
|                                        PRESENTATION / UI LAYER                                    |
|  - DashboardScreen (screens/dashboard/dashboard_screen.dart)                                      |
|  - TelemetryDiagnosticsScreen (screens/settings/telemetry_diagnostics_screen.dart)                 |
|  - RiskCard (widgets/risk_card.dart)                                                              |
|  * 15 Empty Screens / Widgets (alerts_screen, app_details, monitor, settings, splash, etc.)       |
+---------------------------------------------------------------------------------------------------+
```

---

## 3. Repository Folder Structure & File Map

```
mobile_privacy_security_project/
├── ai_training/
│   ├── fix_onnx.py                     # Script adjusting ONNX IR version to 9
│   ├── privacy_dataset.csv             # 54.8 MB tabular dataset (196 feature columns + Class)
│   ├── privacy_guardian.onnx           # Exported ONNX model (35.1 MB, RandomForest, 196 features)
│   ├── privacy_guardian_v9.onnx        # Exported ONNX model v9 (35.1 MB)
│   ├── requirements.txt                # Python dependencies (pandas, scikit-learn, skl2onnx, onnx)
│   └── train_model.py                  # Model training script (RandomForestClassifier, 200 trees)
├── android/
│   ├── app/
│   │   ├── build.gradle.kts            # compileSdk=36, minSdk=26, Java 17, coreLibraryDesugaring
│   │   └── src/main/
│   │       ├── AndroidManifest.xml     # Permissions, foregroundServiceType="dataSync", queries
│   │       └── kotlin/com/example/mobile_privacy_security_project/
│   │           ├── AndroidTelemetryCollector.kt   # Central aggregator & per-UID joiner
│   │           ├── AppUsageMonitor.kt             # UsageStatsManager & UsageEvents collector
│   │           ├── DeviceContextCollector.kt      # Hardware info, battery, screen, power state
│   │           ├── DeviceSecurityMonitor.kt       # Overlay, accessibility, dev options, root
│   │           ├── DeviceStateMonitor.kt          # Facade delegating to DeviceContextCollector
│   │           ├── MainActivity.kt                # MethodChannel ("privacy_sentinel") handler
│   │           ├── NetworkMonitor.kt              # TrafficStats & per-UID NetworkStatsManager
│   │           ├── PermissionMonitor.kt           # PackageManager, dynamic dangerous flags, AppOps
│   │           ├── SensorPrivacyMonitor.kt        # Camera availability & audio recording checks
│   │           └── TelemetryForegroundService.kt  # Android Foreground Service for periodic polling
│   ├── build.gradle.kts                # Root Android build configuration
│   └── settings.gradle.kts             # Gradle plugin repositories
├── assets/
│   └── models/
│       ├── privacy_guardian.onnx       # Asset bundled ONNX model (35.1 MB)
│       └── privacy_guardian copy.onnx  # Duplicate model backup (35.1 MB)
├── lib/
│   ├── agents/
│   │   ├── behavior_agent.dart         # Device-level behavior heuristic analyzer
│   │   ├── context_agent.dart          # Permission vs category heuristic
│   │   ├── decision_agent.dart         # Risk score to BLOCK/WARN/ALLOW decision
│   │   ├── local_triage_engine.dart    # Rule-based base risk calculator
│   │   ├── memory_agent.dart           # SharedPreferences behavior store
│   │   ├── permission_risk_agent.dart  # Static permission weight risk scorer
│   │   └── risk_agent.dart             # ML pipeline coordinator (FeatureEncoder -> ModelRunner)
│   ├── core/
│   │   ├── api_client.dart             # HTTP client for POST /analyze to FastAPI backend
│   │   ├── app_config.dart             # Backend URL configuration (http://10.0.2.2:8000)
│   │   └── constants.dart              # Duplicate definition of AIResponse (Defect)
│   ├── ml/
│   │   ├── feature_encoder.dart        # Encodes AppTelemetry into 11-element feature list
│   │   └── model_runner.dart           # ONNX runtime inference runner (Pads 11 -> 196)
│   ├── models/
│   │   ├── ai_response.dart            # Model for backend AI response (risk, message, action)
│   │   ├── app_info.dart               # Basic package permission model
│   │   ├── app_telemetry.dart          # Full app-level telemetry model with usage & network
│   │   ├── behavior_report.dart        # Findings and suspicious flag model
│   │   ├── privacy_event.dart          # Comprehensive unified telemetry event model
│   │   ├── risk_assessment.dart        # Risk score, level, and reason model
│   │   ├── telemetry_diagnostics.dart  # Telemetry item diagnostic verification model
│   │   ├── threat.dart                 # Threat container model
│   │   └── threat_type.dart            # Threat category enumeration
│   ├── screens/
│   │   ├── alerts/
│   │   │   └── alerts_screen.dart      # [EMPTY FILE - 0 BYTES]
│   │   ├── dashboard/
│   │   │   └── dashboard_screen.dart   # Main UI screen displaying app risk cards
│   │   ├── details/
│   │   │   └── app_details_screen.dart # [EMPTY FILE - 0 BYTES]
│   │   ├── monitor/
│   │   │   └── monitor_screen.dart     # [EMPTY FILE - 0 BYTES]
│   │   ├── settings/
│   │   │   ├── settings_screen.dart    # [EMPTY FILE - 0 BYTES]
│   │   │   └── telemetry_diagnostics_screen.dart # Complete live telemetry inspector UI
│   │   └── splash_screen.dart          # [EMPTY FILE - 0 BYTES]
│   ├── services/
│   │   ├── app_usage_service.dart      # Facade delegating to AndroidCollector
│   │   ├── cloud_ai_service.dart       # [EMPTY FILE - 0 BYTES]
│   │   ├── notification_service.dart   # FlutterLocalNotifications wrapper
│   │   └── storage_service.dart        # [EMPTY FILE - 0 BYTES]
│   ├── telemetry/
│   │   ├── collectors/
│   │   │   ├── android_collector.dart  # Dart MethodChannel client for native collectors
│   │   │   └── ios_collector.dart      # iOS stub returning unsupported platform status
│   │   ├── trackers/
│   │   │   ├── device_context_tracker.dart # Tracker wrapper for device context
│   │   │   ├── network_tracker.dart    # Tracker wrapper for network telemetry
│   │   │   └── permission_tracker.dart # Tracker wrapper for permission telemetry
│   │   ├── app_telemetry_builder.dart  # Maps PrivacyEvent apps into AppTelemetry list
│   │   └── telemetry_service.dart      # Polling service emitting Stream<PrivacyEvent>
│   ├── utils/
│   │   ├── date_formatter.dart         # [EMPTY FILE - 0 BYTES]
│   │   ├── logger.dart                 # [EMPTY FILE - 0 BYTES]
│   │   ├── permission_helper.dart      # [EMPTY FILE - 0 BYTES]
│   │   └── risk_calculator.dart        # [EMPTY FILE - 0 BYTES]
│   ├── widgets/
│   │   ├── alert_card.dart             # [EMPTY FILE - 0 BYTES]
│   │   ├── app_tile.dart               # [EMPTY FILE - 0 BYTES]
│   │   ├── permission_tile.dart        # [EMPTY FILE - 0 BYTES]
│   │   ├── risk_card.dart              # UI Card component displaying app risk score
│   │   └── score_meter.dart            # [EMPTY FILE - 0 BYTES]
│   └── main.dart                       # App entry point, sets Dark Theme, runs DashboardScreen
├── pubspec.yaml                        # Dependencies (onnxruntime, sqflite, provider, http, etc.)
└── README.md                           # Basic project description
```

---

## 4. Phase-Wise Architecture & Project Roadmap

| Phase | Description | Key Deliverables | Status |
|---|---|---|---|
| **Phase 1** | **Mobile Device Layer & Real Telemetry Pipeline** | Native Android Collectors (Kotlin), MethodChannel bridge, `PrivacyEvent` / `AppTelemetry` models, Foreground Service, Diagnostics verification UI, Local Edge AI inference stub. | **85% Complete** (Native Layer: 100%, Dart Models/Pipeline: 95%, Diagnostics UI: 100%, Core App UI: 40%) |
| **Phase 2** | **Edge Multi-Agent System & Local Triage** | Coordinated execution of `BehaviorAgent`, `ContextAgent`, `DecisionAgent`, `LocalTriageEngine`, feature vector normalization, retraining ONNX for actual telemetry schema. | **20% Complete** (Agent classes written as isolated stubs; not chained) |
| **Phase 3** | **Cloud Brain & Deep Threat Analysis** | FastAPI backend integration, Cloud AI Service, LLM explanation engine, threat intelligence feed, deep network packet inspection. | **10% Complete** (`ApiClient` written with single endpoint; backend not connected) |
| **Phase 4** | **Automated Privacy Mitigation & Enforcement** | Automated permission revocation prompts, AppOps toggling, background data restriction intents, Doze mode management, historical SQLite telemetry storage. | **5% Complete** (`NotificationService` implemented; `storage_service` is empty) |

---

## 5. Mobile Device Layer Deep Dive

The Mobile Device Layer is the foundational data-gathering tier of the project. It runs entirely on the host Android operating system and interfaces with Android Framework services via the `android.*` Java/Kotlin APIs.

```
+---------------------------------------------------------------------------------------------------+
|                                     MOBILE DEVICE LAYER (KOTLIN)                                  |
|                                                                                                   |
|  +--------------------------+  +--------------------------+  +---------------------------------+  |
|  |     PermissionMonitor    |  |      AppUsageMonitor     |  |          NetworkMonitor         |  |
|  | - PackageManager         |  | - UsageStatsManager      |  | - TrafficStats (Device Totals)  |  |
|  | - Dynamic Dangerous     |  | - UsageEvents (Interval) |  | - NetworkStatsManager (Per-UID) |  |
|  | - AppOps (Overlay/Usage) |  | - Transition Counting    |  | - ConnectivityManager (Transp.) |  |
|  +--------------------------+  +--------------------------+  +---------------------------------+  |
|               │                             │                                │                    |
|               └──────────────────────┐      │      ┌─────────────────────────┘                    |
|                                      ▼      ▼      ▼                                              |
|  +---------------------------------------------------------------------------------------------+  |
|  |                                  AndroidTelemetryCollector                                  |  |
|  |  - Aggregates package metadata, usage stats, and per-UID Wi-Fi/Cellular network bytes       |  |
|  |  - Separates Device Context from App-Specific Telemetry                                     |  |
|  |  - Emits Telemetry Diagnostic items for live inspection                                     |  |
|  +---------------------------------------------------------------------------------------------+  |
|                                      ▲      ▲      ▲                                              |
|               ┌──────────────────────┘      │      └─────────────────────────┐                    |
|               │                             │                                │                    |
|  +--------------------------+  +--------------------------+  +---------------------------------+  |
|  |  DeviceContextCollector  |  |   DeviceSecurityMonitor  |  |       SensorPrivacyMonitor      |  |
|  | - Static Hardware (Build)|  | - Overlay/Doze/Install   |  | - Camera AvailabilityCallback   |  |
|  | - Battery (StickyIntent) |  | - DevOptions & ADB State |  | - AudioManager Active Record    |  |
|  | - PowerManager / Keyguard|  | - Multi-probe Root Check |  | - Attribution Scope: Device-Only|  |
|  +--------------------------+  +--------------------------+  +---------------------------------+  |
|                                                                                                   |
|  +---------------------------------------------------------------------------------------------+  |
|  |                        TelemetryForegroundService (dataSync Foreground)                     |  |
|  |  - Periodic background collection (30s interval)                                            |  |
|  |  - Persistent Ongoing Notification (Channel: "privacy_monitor_channel")                     |  |
|  +---------------------------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------------------------+
```

---

## 6. Detailed File-by-File Technical Audit (15-Point Criteria)

### 6.1 Kotlin Native Layer

---

#### 1. `MainActivity.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/MainActivity.kt`
- **Purpose:** Host FlutterActivity setting up the native binary messenger handler for MethodChannel `"privacy_sentinel"`.
- **Important Classes/Functions:** `MainActivity`, `configureFlutterEngine()`, `onDestroy()`, method call dispatcher (`when(call.method)`).
- **Android API Used:** `io.flutter.embedding.android.FlutterActivity`, `io.flutter.plugin.common.MethodChannel`, `android.content.Intent`, `android.provider.Settings`, `androidx.core.content.ContextCompat.startForegroundService`.
- **Data Collected:** None directly; dispatches method calls to `AndroidTelemetryCollector` and manages system settings intents and service lifecycles.
- **Real or Derived:** Real (system event handling).
- **Device-level or App-level:** Boundary layer (both).
- **Real-time, Periodic, Event-driven, or Historical:** Event-driven (invoked upon Dart MethodChannel calls).
- **Required Permissions:** None for basic dispatch.
- **Android Limitations:** Handlers must run asynchronously or return fast to avoid blocking Flutter UI thread.
- **Problems / Incorrect Assumptions:** Uses synchronous blocking calls inside the method handler (`result.success(telemetryCollector.collectTelemetry())`), which performs Binder IPC queries across PackageManager, UsageStats, and NetworkStatsManager on the main thread. While acceptable for small queries, on devices with 300+ apps this may cause momentary UI jank.
- **Hardcoded Values:** Channel name `"privacy_sentinel"`, error code `"TELEMETRY_ERROR"`.
- **Duplicate Logic:** None.
- **Missing Functionality:** Missing asynchronous thread dispatch (e.g. Kotlin Coroutines `withContext(Dispatchers.IO)`) for heavy telemetry gathering.
- **Production-Ready:** **Yes** (Functional and stable, but should offload heavy IPC to background dispatchers).

---

#### 2. `AndroidTelemetryCollector.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/AndroidTelemetryCollector.kt`
- **Purpose:** Central native aggregator that executes modular collectors, joins app-specific usage/network data by package name and UID, compiles diagnostic items, and returns a unified telemetry dictionary.
- **Important Classes/Functions:** `AndroidTelemetryCollector`, `collectTelemetry()`, `generateDiagnostics()`, individual delegate getters (`getInstalledApps()`, `getUsageStats()`, etc.).
- **Android API Used:** `java.time.Instant`, `java.time.format.DateTimeFormatter`. Interacts with all native collector modules.
- **Data Collected:** Unified payload containing `timestamp`, `deviceContext`, `deviceSecurity`, `network`, `sensorTelemetry`, `usageSummary`, `apps` (list of enriched app maps), `diagnostics`, and top-level backward compatibility keys.
- **Real or Derived:** Real ground-truth telemetry enriched with derived signals (`isRecentlyUsedDerived`).
- **Device-level or App-level:** Both (strictly demarcated).
- **Real-time, Periodic, Event-driven, or Historical:** Snapshot combining real-time hardware states with historical 24-hour usage/traffic aggregations.
- **Required Permissions:** `QUERY_ALL_PACKAGES`, `PACKAGE_USAGE_STATS`.
- **Android Limitations:** App network stats and usage events depend on user granting Special App Access (`PACKAGE_USAGE_STATS`).
- **Problems / Incorrect Assumptions:** Emits duplicate top-level keys (`screenLocked`, `screenOn`, `uploadBytes`, `downloadBytes`, `rootDetected`, etc.) alongside structured nested objects (`deviceContext`, `network`, `deviceSecurity`). This was intentionally done for backwards compatibility, but creates redundant JSON payload overhead over MethodChannel.
- **Hardcoded Values:** Compatibility keys, availability strings (`"AVAILABLE"`, `"RESTRICTED"`, `"ZERO_REPORTED"`).
- **Duplicate Logic:** Redundantly exposes top-level compatibility fields identical to nested structure values.
- **Missing Functionality:** None; aggregator is complete.
- **Production-Ready:** **Yes**.

---

#### 3. `AppUsageMonitor.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/AppUsageMonitor.kt`
- **Purpose:** Collects real application foreground usage duration and transition events using `UsageStatsManager` and `UsageEvents`.
- **Important Classes/Functions:** `AppUsageMonitor`, `isUsageAccessGranted()`, `getUsageTelemetry(intervalHours = 24)`.
- **Android API Used:** `android.app.AppOpsManager` (`OPSTR_GET_USAGE_STATS`, `unsafeCheckOpNoThrow`), `android.app.usage.UsageStatsManager`, `android.app.usage.UsageEvents`, `android.os.Process`.
- **Data Collected:** `usageAccessGranted`, `availability`, `currentForegroundApp`, `totalForegroundDurationMs`, `totalForegroundTransitions`, per-app `foregroundDurationMs`, `foregroundMinutes`, `foregroundTransitionCount`, `lastTimeUsedMs`, `isCurrentlyForeground`, `isRecentlyUsedDerived`.
- **Real or Derived:** Real `UsageStats` and `UsageEvents`; derived `isRecentlyUsedDerived` (heuristic: `now - lastUsed < 5 min`).
- **Device-level or App-level:** App-level (with aggregated device totals).
- **Real-time, Periodic, Event-driven, or Historical:** Historical 24h interval with real-time foreground state tracking.
- **Required Permissions:** `android.permission.PACKAGE_USAGE_STATS` (Special App Access).
- **Android Limitations:** `UsageEvents` can be dropped by aggressive OEM battery managers; `queryUsageStats` is aggregated in daily buckets and not fine-grained down to seconds.
- **Problems / Incorrect Assumptions:** Uses a 24-hour fixed window (`intervalHours: Int = 24`). If an app was used 23 hours ago, `foregroundDurationMs` reflects the full day's aggregate, which might mislead an instantaneous risk engine if not normalized by time.
- **Hardcoded Values:** `5 * 60 * 1000` (5 minutes recency threshold), `24` hours default interval.
- **Duplicate Logic:** `isUsageAccessGranted()` logic is duplicated in `NetworkMonitor.kt` and `PermissionMonitor.kt`.
- **Missing Functionality:** Configurable interval filtering (e.g. last 1 hour vs. last 24 hours vs. last 7 days).
- **Production-Ready:** **Yes**.

---

#### 4. `DeviceContextCollector.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/DeviceContextCollector.kt`
- **Purpose:** Collects hardware/OS specifications (cached once) and real-time physical device context (battery, screen interactivity, lock state, Doze mode, uptime).
- **Important Classes/Functions:** `DeviceContextCollector`, `staticHardwareInfo` (lazy), `collectDynamicState()`, `collect()`.
- **Android API Used:** `android.os.Build`, `android.os.PowerManager`, `android.app.KeyguardManager`, `android.os.BatteryManager`, `android.content.Intent.ACTION_BATTERY_CHANGED`, `android.os.SystemClock`, `java.util.TimeZone`, `java.util.Locale`.
- **Data Collected:** Manufacturer, model, brand, device, board, hardware, Android OS version, SDK int, `screenOn`, `screenLocked`, `isDeviceSecure`, `batteryPercent`, `isCharging`, `batteryStatus`, `batteryPlugged`, `batteryHealth`, `batteryTemperatureCelsius`, `batteryVoltageMv`, `powerSaveMode`, `deviceIdleMode` (Doze), `uptimeMs`, `timezone`, `locale`.
- **Real or Derived:** Real ground-truth device telemetry from system services and sticky battery broadcast.
- **Device-level or App-level:** Device-level only.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time instantaneous snapshot.
- **Required Permissions:** None (standard unprivileged Android APIs).
- **Android Limitations:** `ACTION_BATTERY_CHANGED` receiver registered with `null` BroadcastReceiver returns sticky broadcast snapshot, which is completely valid and battery-efficient.
- **Problems / Incorrect Assumptions:** None.
- **Hardcoded Values:** `/ 10.0` for battery temperature division (standard Android tenths of a degree Celsius).
- **Duplicate Logic:** None.
- **Missing Functionality:** Thermal throttling status (`PowerManager.getCurrentThermalStatus()` on API 29+).
- **Production-Ready:** **Yes**.

---

#### 5. `DeviceSecurityMonitor.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/DeviceSecurityMonitor.kt`
- **Purpose:** Collects device-level security posture (developer settings, ADB, accessibility services, VPN transport, lock screen security) and host-app capabilities (overlay, doze exemption, package install permissions) plus probabilistic root detection.
- **Important Classes/Functions:** `DeviceSecurityMonitor`, `selfCanDrawOverlays()`, `selfIsIgnoringBatteryOptimizations()`, `selfCanRequestPackageInstalls()`, `accessibilityEnabled()`, `getEnabledAccessibilityServices()`, `developerOptionsEnabled()`, `adbEnabled()`, `isDeviceSecure()`, `vpnActive()`, `evaluateRootHeuristic()`, `collectSecurityState()`.
- **Android API Used:** `android.provider.Settings` (`canDrawOverlays`, `Global.DEVELOPMENT_SETTINGS_ENABLED`, `Global.ADB_ENABLED`), `android.os.PowerManager.isIgnoringBatteryOptimizations`, `android.content.pm.PackageManager.canRequestPackageInstalls`, `android.view.accessibility.AccessibilityManager`, `android.app.KeyguardManager.isDeviceSecure`, `android.net.ConnectivityManager`, `android.net.NetworkCapabilities`.
- **Data Collected:** Host app special capabilities (`selfCanDrawOverlays`, `selfIsIgnoringBatteryOptimizations`, `selfCanRequestPackageInstalls`), device-level states (`accessibilityEnabled`, `enabledAccessibilityServices`, `developerOptionsEnabled`, `adbEnabled`, `isDeviceSecure`, `vpnActive`), root heuristic result (`isRootedHeuristic`, `confidence`, `matchedIndicators`, `disclaimer`).
- **Real or Derived:** Real device settings; root detection is derived/probabilistic.
- **Device-level or App-level:** Strictly demarcated: host app capabilities vs. device-wide settings.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time snapshot.
- **Required Permissions:** `ACCESS_NETWORK_STATE`.
- **Android Limitations:** Android does not provide an official API for root detection; any root detection is heuristic.
- **Problems / Incorrect Assumptions:** The root heuristic inspects static paths and known package names. Advanced root cloaks (e.g. Magisk DenyList/Zygisk) cannot be detected by filesystem inspection alone. However, the code explicitly includes a disclaimer and marks it as heuristic.
- **Hardcoded Values:** List of 11 su paths, list of 7 root management packages.
- **Duplicate Logic:** Aliased keys for backward compatibility.
- **Missing Functionality:** Google Play Protect status / SafetyNet / Play Integrity API integration.
- **Production-Ready:** **Yes**.

---

#### 6. `DeviceStateMonitor.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/DeviceStateMonitor.kt`
- **Purpose:** Wrapper facade providing helper methods `isScreenLocked()`, `isScreenOn()`, and `isDeviceSecure()`.
- **Important Classes/Functions:** `DeviceStateMonitor`, `isScreenLocked()`, `isScreenOn()`, `isDeviceSecure()`.
- **Android API Used:** None directly; delegates to `DeviceContextCollector`.
- **Data Collected:** Screen and lock states.
- **Real or Derived:** Real.
- **Device-level or App-level:** Device-level.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** Redundant class. It creates a new `DeviceContextCollector` instance and calls `collectDynamicState()` on every method invocation, doing redundant battery receiver registrations.
- **Hardcoded Values:** None.
- **Duplicate Logic:** Completely duplicates functionality already provided directly by `DeviceContextCollector`.
- **Missing Functionality:** None (should be deprecated/removed).
- **Production-Ready:** **Redundant / Obsolete**.

---

#### 7. `NetworkMonitor.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/NetworkMonitor.kt`
- **Purpose:** Collects device-level network telemetry (transports, bandwidth, metered status, device traffic totals) and legitimate per-UID historical network usage using `NetworkStatsManager`.
- **Important Classes/Functions:** `NetworkMonitor`, `getDeviceNetworkTelemetry()`, `queryAllUidNetworkStats()`, `collectTransportStats()`, `isUsageAccessGranted()`.
- **Android API Used:** `android.net.TrafficStats`, `android.net.ConnectivityManager`, `android.net.NetworkCapabilities`, `android.app.usage.NetworkStatsManager`, `android.app.usage.NetworkStats`, `android.app.AppOpsManager`.
- **Data Collected:** Device totals (`deviceTotalTxBytes`, `deviceTotalRxBytes`, `deviceMobileTxBytes`, `deviceMobileRxBytes`), connectivity status (`isConnected`, `transport`, `isMetered`, `downstreamBandwidthKbps`, `upstreamBandwidthKbps`, `vpnActive`), per-UID metrics (`txBytes`, `rxBytes`, `availability`, `source`).
- **Real or Derived:** Real ground-truth network statistics.
- **Device-level or App-level:** Both: device-wide totals via `TrafficStats`, app-level per-UID totals via `NetworkStatsManager`.
- **Real-time, Periodic, Event-driven, or Historical:** Device connectivity is real-time; traffic totals are cumulative since boot; per-UID stats are 24-hour historical aggregations.
- **Required Permissions:** `ACCESS_NETWORK_STATE`, `PACKAGE_USAGE_STATS`.
- **Android Limitations:** `TrafficStats.getUidTxBytes(uid)` is restricted for third-party UIDs on Android 9+ (API 28) and returns `TrafficStats.UNSUPPORTED (-1)`. This collector correctly uses `NetworkStatsManager.querySummary` with `TRANSPORT_WIFI` and `TRANSPORT_CELLULAR` to legitimately query per-UID network stats.
- **Problems / Incorrect Assumptions:** None. The fallback and permission gating are handled properly without fabricating fake zeroes.
- **Hardcoded Values:** `24` hours default interval.
- **Duplicate Logic:** `isUsageAccessGranted()` is duplicated from `AppUsageMonitor.kt`.
- **Missing Functionality:** Granular per-domain or per-IP traffic (requires a local VPN service).
- **Production-Ready:** **Yes**.

---

#### 8. `PermissionMonitor.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/PermissionMonitor.kt`
- **Purpose:** Scans all installed packages, categorizes granted/denied permissions, dynamically evaluates `PROTECTION_DANGEROUS` flags, checks per-app AppOps, and caches results.
- **Important Classes/Functions:** `PermissionMonitor`, `getInstalledAppPermissions(forceRefresh = false)`, `isDangerousPermissionDynamic()`, `checkAppOp()`.
- **Android API Used:** `android.content.pm.PackageManager`, `android.content.pm.PackageInfo`, `android.content.pm.ApplicationInfo`, `android.content.pm.PermissionInfo`, `android.app.AppOpsManager`, `java.util.concurrent.ConcurrentHashMap`.
- **Data Collected:** App name, package name, system app flag, enabled flag, UID, target SDK, min SDK, version name/code, install/update timestamps, installer package, requested permissions, granted permissions, denied permissions, dynamic dangerous permissions, `hasOverlayOp`, `hasUsageAccessOp`.
- **Real or Derived:** Real ground-truth package and permission data.
- **Device-level or App-level:** App-level inventory.
- **Real-time, Periodic, Event-driven, or Historical:** Cached in-memory with 10-second TTL.
- **Required Permissions:** `android.permission.QUERY_ALL_PACKAGES`.
- **Android Limitations:** On Android 11+ (API 30), package visibility is restricted without `QUERY_ALL_PACKAGES`. Declared in Manifest.
- **Problems / Incorrect Assumptions:** None. Avoids hardcoded dangerous permission strings by querying `PermissionInfo.protectionLevel` / `protection` against `PROTECTION_DANGEROUS`.
- **Hardcoded Values:** `10_000L` (10-second cache TTL).
- **Duplicate Logic:** `checkAppOp` duplicates AppOps logic found in other monitors.
- **Missing Functionality:** Monitoring runtime permission revocation events via BroadcastReceiver (`ACTION_PACKAGE_ADDED`, `ACTION_PACKAGE_REMOVED`).
- **Production-Ready:** **Yes**.

---

#### 9. `SensorPrivacyMonitor.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/SensorPrivacyMonitor.kt`
- **Purpose:** Monitors hardware camera and microphone occupancy at the device level without violating Android sandbox privacy boundaries.
- **Important Classes/Functions:** `SensorPrivacyMonitor`, `CameraManager.AvailabilityCallback`, `registerCallback()`, `unregister()`, `isCameraHardwareInUse()`, `isMicrophoneHardwareInUse()`, `getSensorTelemetry()`.
- **Android API Used:** `android.hardware.camera2.CameraManager`, `android.media.AudioManager`, `android.media.AudioRecordingConfiguration`.
- **Data Collected:** `cameraHardwareInUse`, `unavailableCamerasCount`, `microphoneHardwareInUse`, `activeAudioRecordingsCount`, `isMicrophoneMuted`, `audioMode`, `attributionScope` (`"DEVICE_LEVEL_ONLY"`).
- **Real or Derived:** Real hardware occupancy state.
- **Device-level or App-level:** Device-level only.
- **Real-time, Periodic, Event-driven, or Historical:** Camera is event-driven (`AvailabilityCallback`); microphone is sampled in real-time (`activeRecordingConfigurations`).
- **Required Permissions:** None.
- **Android Limitations:** Android OS intentionally **does not expose** the specific third-party package name using the camera or microphone to unprivileged apps. This collector honestly reports device-level sensor occupancy and sets `attributionScope = "DEVICE_LEVEL_ONLY"`.
- **Problems / Incorrect Assumptions:** None.
- **Hardcoded Values:** `"DEVICE_LEVEL_ONLY"`, `"NORMAL"`, `"RINGTONE"`, `"IN_CALL"`, `"IN_COMMUNICATION"`.
- **Duplicate Logic:** None.
- **Missing Functionality:** Sensor privacy toggle status (`SensorPrivacyManager` on Android 12+ for microphone/camera global software kill-switch).
- **Production-Ready:** **Yes**.

---

#### 10. `TelemetryForegroundService.kt`
- **File Path:** `android/app/src/main/kotlin/com/example/mobile_privacy_security_project/TelemetryForegroundService.kt`
- **Purpose:** Ongoing Android Service executing periodic background telemetry collection while displaying a persistent notification.
- **Important Classes/Functions:** `TelemetryForegroundService`, `onStartCommand()`, `startForegroundWithNotification()`, `addTelemetryListener()`, `removeTelemetryListener()`, `telemetryRunnable`.
- **Android API Used:** `android.app.Service`, `android.app.Notification`, `android.app.NotificationChannel`, `android.app.NotificationManager`, `android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC`, `android.os.Handler`, `android.os.Looper`.
- **Data Collected:** Triggers `AndroidTelemetryCollector.collectTelemetry()` every 30 seconds and stores `latestSnapshot`.
- **Real or Derived:** Real.
- **Device-level or App-level:** Both.
- **Real-time, Periodic, Event-driven, or Historical:** Periodic background loop (30 seconds).
- **Required Permissions:** `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`.
- **Android Limitations:** Android 14+ (API 34) and Android 15/16 strictly mandate declaring `foregroundServiceType` in code and manifest (`dataSync`).
- **Problems / Incorrect Assumptions:** The collected `latestSnapshot` is stored in an in-memory companion object, but there is no native EventChannel to push background snapshots directly into Flutter when the app is in the background or terminated.
- **Hardcoded Values:** `pollIntervalMs = 30_000L` (30 seconds), `NOTIFICATION_ID = 1001`, `CHANNEL_ID = "privacy_monitor_channel"`.
- **Duplicate Logic:** Instantiates its own `AndroidTelemetryCollector(applicationContext)`.
- **Missing Functionality:** Flutter EventChannel or background Dart Isolate callback to receive background snapshots while the UI is closed.
- **Production-Ready:** **Yes** (Meets Android 14/15/16 background execution rules).

---

### 6.2 Flutter Telemetry & Collector Pipeline

---

#### 11. `android_collector.dart`
- **File Path:** `lib/telemetry/collectors/android_collector.dart`
- **Purpose:** Low-level Flutter MethodChannel client interfacing with Android `privacy_sentinel` channel.
- **Important Classes/Functions:** `AndroidCollector`, `collectTelemetry()`, `getInstalledApps()`, `getUsageStats()`, `getDeviceContext()`, `getDeviceSecurity()`, `getNetworkTelemetry()`, `isUsageAccessGranted()`, `openUsageAccessSettings()`, `startForegroundService()`, `stopForegroundService()`, etc.
- **Android API Used:** Invokes native methods via `MethodChannel("privacy_sentinel")`.
- **Data Collected:** Receives dynamic `Map` and `List` structures returned from native Kotlin.
- **Real or Derived:** Real (deserialized).
- **Device-level or App-level:** Both.
- **Real-time, Periodic, Event-driven, or Historical:** Invoked on-demand.
- **Required Permissions:** Communicates across platform channel.
- **Android Limitations:** Catches `PlatformException` and returns fallback error maps.
- **Problems / Incorrect Assumptions:** Error fallback in `collectTelemetry()` returns a default map with `"apps": []`, which masks underlying failures if not checked.
- **Hardcoded Values:** `"privacy_sentinel"` channel name, method string literals.
- **Duplicate Logic:** Methods like `getInstalledApps()` or `getUsageStats()` duplicate subsets of what `collectTelemetry()` returns in a single round-trip.
- **Missing Functionality:** Native EventChannel listener for continuous streaming.
- **Production-Ready:** **Yes**.

---

#### 12. `ios_collector.dart`
- **File Path:** `lib/telemetry/collectors/ios_collector.dart`
- **Purpose:** Stub collector for iOS platform.
- **Important Classes/Functions:** `IosCollector`, `collectTelemetry()`.
- **Android API Used:** None (iOS target).
- **Data Collected:** Static map indicating iOS unsupported.
- **Real or Derived:** Stub.
- **Device-level or App-level:** N/A.
- **Real-time, Periodic, Event-driven, or Historical:** Static.
- **Required Permissions:** None.
- **Android Limitations:** N/A.
- **Problems / Incorrect Assumptions:** Clearly documented stub; no false claims.
- **Hardcoded Values:** `"platform": "iOS"`, `"supported": false`.
- **Duplicate Logic:** None.
- **Missing Functionality:** iOS NetworkExtension / ScreenTime implementation.
- **Production-Ready:** **Stub only**.

---

#### 13. `device_context_tracker.dart`, `network_tracker.dart`, `permission_tracker.dart`
- **File Paths:**
  - `lib/telemetry/trackers/device_context_tracker.dart`
  - `lib/telemetry/trackers/network_tracker.dart`
  - `lib/telemetry/trackers/permission_tracker.dart`
- **Purpose:** High-level domain wrappers around `AndroidCollector` for specific telemetry domains.
- **Important Classes/Functions:** `DeviceContextTracker`, `NetworkTracker`, `PermissionTracker`.
- **Android API Used:** Calls `AndroidCollector`.
- **Data Collected:** Filtered domain slices (device context, network state, app info list).
- **Real or Derived:** Real.
- **Device-level or App-level:** Domain-specific.
- **Real-time, Periodic, Event-driven, or Historical:** On-demand.
- **Required Permissions:** None directly.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** Each tracker creates an independent instance of `AndroidCollector()` and makes independent `invokeMethod` calls over the MethodChannel. If all three are queried, they execute 3 separate IPC roundtrips instead of reusing a single `collectTelemetry()` payload.
- **Hardcoded Values:** None.
- **Duplicate Logic:** Re-invokes individual sub-methods.
- **Missing Functionality:** Caching or shared stream subscription.
- **Production-Ready:** **Yes** (Functional, but suboptimal IPC efficiency).

---

#### 14. `telemetry_service.dart`
- **File Path:** `lib/telemetry/telemetry_service.dart`
- **Purpose:** Emits a continuous `Stream<PrivacyEvent>` by polling `AndroidCollector.collectTelemetry()` at a configurable periodic interval (default 5 seconds).
- **Important Classes/Functions:** `TelemetryService`, `stream`, `start()`, `stop()`, `refreshOnce()`, `_pollTelemetry()`.
- **Android API Used:** Calls `AndroidCollector`.
- **Data Collected:** Emits fully parsed `PrivacyEvent` instances.
- **Real or Derived:** Real.
- **Device-level or App-level:** Both.
- **Real-time, Periodic, Event-driven, or Historical:** Periodic polling loop (5 seconds).
- **Required Permissions:** None.
- **Android Limitations:** Polling every 5 seconds over MethodChannel runs full package and usage queries; on lower-end devices, 5 seconds is aggressive and may consume unnecessary battery if the UI is open for long periods.
- **Problems / Incorrect Assumptions:** Does not automatically throttle when app lifecycle pauses (`AppLifecycleState.paused`).
- **Hardcoded Values:** `Duration(seconds: 5)` default interval.
- **Duplicate Logic:** None.
- **Missing Functionality:** Integration with `WidgetsBindingObserver` to pause polling when app is backgrounded.
- **Production-Ready:** **Yes**.

---

#### 15. `app_telemetry_builder.dart`
- **File Path:** `lib/telemetry/app_telemetry_builder.dart`
- **Purpose:** Converts the raw JSON app list inside a `PrivacyEvent` into a strongly-typed list of `AppTelemetry` domain models, attaching forwarded device-level signals (screenLocked, accessibilityEnabled, batteryOptimizationIgnored, vpnActive).
- **Important Classes/Functions:** `AppTelemetryBuilder`, `build(PrivacyEvent telemetry)`.
- **Android API Used:** None (pure Dart).
- **Data Collected:** Transforms `telemetry.apps` maps into `AppTelemetry` domain objects.
- **Real or Derived:** Real transformed data.
- **Device-level or App-level:** Maps app-level data while forwarding device-level context flags.
- **Real-time, Periodic, Event-driven, or Historical:** Synchronous mapping.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** None; handles nullability, type casting from dynamic maps, and fallback keys seamlessly.
- **Hardcoded Values:** `"RESTRICTED"`, `"UNAVAILABLE"`.
- **Duplicate Logic:** None.
- **Missing Functionality:** None.
- **Production-Ready:** **Yes**.

---

### 6.3 Data Models & Diagnostics

---

#### 16. `privacy_event.dart`
- **File Path:** `lib/models/privacy_event.dart`
- **Purpose:** Root domain model encapsulating the complete device and app snapshot returned by the native collector.
- **Important Classes/Functions:** `PrivacyEvent`, `DeviceContext`, `SecurityContext`, `NetworkTelemetry`, `SensorPrivacyTelemetry`, `UsageSummary`, factory `fromMap()`, `toJson()`, backward compatibility getters.
- **Android API Used:** Pure Dart data structures representing Android system constructs.
- **Data Collected:** 28 device hardware/state fields, 13 security/root fields, 10 network fields, 7 sensor fields, 6 usage summary fields, list of app maps, list of diagnostic items.
- **Real or Derived:** Real with derived root/recency fields.
- **Device-level or App-level:** Both, strictly compartmentalized into child classes.
- **Real-time, Periodic, Event-driven, or Historical:** Snapshot container.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** Backward compatibility getters (e.g. `screenLocked => deviceContext.screenLocked`) allow legacy flat access, but could encourage sloppy code to ignore the strongly-typed sub-objects.
- **Hardcoded Values:** Default values in constructors (`"UNKNOWN"`, `false`, `0`).
- **Duplicate Logic:** Backward compatibility getters duplicate access to sub-object fields.
- **Missing Functionality:** Immutable copyWith methods.
- **Production-Ready:** **Yes** (Comprehensive and rock-solid).

---

#### 17. `app_telemetry.dart`
- **File Path:** `lib/models/app_telemetry.dart`
- **Purpose:** Represents the fine-grained telemetry profile of a single installed application.
- **Important Classes/Functions:** `AppTelemetry`, `toJson()`, backward compatibility getters (`overlayPermission`, `launchCount`, `foregroundTimeMs`, `isActive`).
- **Android API Used:** Pure Dart model.
- **Data Collected:** App identity, versions, UID, installation dates, requested/granted/denied/dangerous permissions, overlay/usage AppOps, foreground duration/minutes, transition count, recency, per-UID Wi-Fi/Cell upload/download bytes, network availability status, forwarded device signals.
- **Real or Derived:** Real data.
- **Device-level or App-level:** App-level.
- **Real-time, Periodic, Event-driven, or Historical:** Multi-temporal container.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** None.
- **Hardcoded Values:** Default constructor parameters.
- **Duplicate Logic:** None.
- **Missing Functionality:** None.
- **Production-Ready:** **Yes**.

---

#### 18. `app_info.dart`
- **File Path:** `lib/models/app_info.dart`
- **Purpose:** Minimal package permission model used by `PermissionTracker`.
- **Important Classes/Functions:** `AppInfo`, `fromJson()`, `toJson()`.
- **Android API Used:** Pure Dart.
- **Data Collected:** Name, package, isSystemApp, isEnabled, uid, versionName, versionCode, permissions, grantedPermissions, dangerousPermissions.
- **Real or Derived:** Real.
- **Device-level or App-level:** App-level.
- **Real-time, Periodic, Event-driven, or Historical:** Static snapshot.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** A simplified subset of `AppTelemetry`.
- **Hardcoded Values:** None.
- **Duplicate Logic:** Overlaps with `AppTelemetry`.
- **Missing Functionality:** None.
- **Production-Ready:** **Yes**.

---

#### 19. `telemetry_diagnostics.dart`
- **File Path:** `lib/models/telemetry_diagnostics.dart`
- **Purpose:** Data model for live diagnostic items displayed on the telemetry inspection screen.
- **Important Classes/Functions:** `TelemetryDiagnosticItem`, `fromMap()`, `toJson()`.
- **Android API Used:** Pure Dart.
- **Data Collected:** `field`, `value`, `sourceApi`, `scope`, `collectionType`, `availability`, `limitation`.
- **Real or Derived:** Real diagnostic metadata generated by `AndroidTelemetryCollector.kt`.
- **Device-level or App-level:** Both.
- **Real-time, Periodic, Event-driven, or Historical:** Static metadata.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** None.
- **Hardcoded Values:** Defaults.
- **Duplicate Logic:** None.
- **Missing Functionality:** None.
- **Production-Ready:** **Yes**.

---

#### 20. `ai_response.dart`, `risk_assessment.dart`, `behavior_report.dart`, `threat.dart`, `threat_type.dart`
- **File Paths:**
  - `lib/models/ai_response.dart`
  - `lib/models/risk_assessment.dart`
  - `lib/models/behavior_report.dart`
  - `lib/models/threat.dart`
  - `lib/models/threat_type.dart`
- **Purpose:** Domain models representing risk scores, threat categories, behavior reports, and backend AI responses.
- **Important Classes/Functions:** `AIResponse`, `RiskAssessment`, `BehaviorReport`, `Threat`, `ThreatType`.
- **Android API Used:** Pure Dart.
- **Data Collected:** Risk scores, risk levels, threat enums, findings.
- **Real or Derived:** Derived analytical signals.
- **Device-level or App-level:** Both.
- **Real-time, Periodic, Event-driven, or Historical:** Analytical outputs.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** `constants.dart` contains an exact duplicate of `AIResponse`.
- **Hardcoded Values:** Enum types.
- **Duplicate Logic:** `AIResponse` in `constants.dart`.
- **Missing Functionality:** Serialization helpers on `BehaviorReport` and `Threat`.
- **Production-Ready:** **Yes**.

---

### 6.4 AI / ML Edge Pipeline & Agents

---

#### 21. `feature_encoder.dart`
- **File Path:** `lib/ml/feature_encoder.dart`
- **Purpose:** Extracts and normalizes features from `AppTelemetry` into a numerical array for ML inference.
- **Important Classes/Functions:** `FeatureEncoder`, `encode(AppTelemetry app)`.
- **Android API Used:** Pure Dart.
- **Data Collected:** Generates a `List<double>` of 11 features:
  1. `camera` (1.0 if permissions contain "CAMERA", else 0.0)
  2. `microphone` (1.0 if "RECORD_AUDIO", else 0.0)
  3. `contacts` (1.0 if "CONTACTS", else 0.0)
  4. `location` (1.0 if "LOCATION", else 0.0)
  5. `storage` (1.0 if "STORAGE", else 0.0)
  6. `sms` (1.0 if "SMS", else 0.0)
  7. `permissionCount` (total requested permissions count)
  8. `foreground` (`foregroundMinutes`)
  9. `active` (1.0 if `isActive`, else 0.0)
  10. `upload` (`uploadBytes / 1,000,000` -> MB)
  11. `download` (`downloadBytes / 1,000,000` -> MB)
- **Real or Derived:** Derived feature vector from real telemetry.
- **Device-level or App-level:** App-level.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time transformation.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:**
  1. Uses `.contains("CAMERA")` substring matching on joined uppercase permissions string rather than exact match against standard Android permission strings (e.g. `android.permission.CAMERA`).
  2. Only extracts **11 features**, whereas the underlying ONNX model (`privacy_guardian.onnx`) was trained on **196 tabular features** from `privacy_dataset.csv`.
- **Hardcoded Values:** `/ 1000000` for byte to MB conversion.
- **Duplicate Logic:** None.
- **Missing Functionality:** Normalization/scaling (MinMaxScaler or StandardScaler) matching the training dataset preprocessing.
- **Production-Ready:** **No — Architectural Feature Mismatch**.

---

#### 22. `model_runner.dart`
- **File Path:** `lib/ml/model_runner.dart`
- **Purpose:** Loads `assets/models/privacy_guardian.onnx` via the `onnxruntime` package and executes on-device inference.
- **Important Classes/Functions:** `ModelRunner`, `loadModel()`, `predict(List<double> features)`.
- **Android API Used:** Pure Dart calling `onnxruntime` native library.
- **Data Collected:** Loads ONNX model bytes from Flutter asset bundle, creates an `OrtValueTensor` of shape `[1, 196]`, passes to `_session.run()`, extracts output tensor, and computes a risk score.
- **Real or Derived:** Derived risk score.
- **Device-level or App-level:** App-level inference.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time on-device inference.
- **Required Permissions:** None.
- **Android Limitations:** ONNX Runtime native binary size (~35 MB model asset).
- **Problems / Incorrect Assumptions (CRITICAL):**
  1. **Zero-Padding Dimension Hack:** Receives 11 features, creates a 196-length zero-filled buffer (`modelInput = List<double>.filled(196, 0.0)`), and pads indices 11..195 with zeroes. The model receives 185 zeroes for features it was trained on with actual tabular distributions.
  2. **String Matching Inference Result:** Inspects `result.toString().contains("1")`.
  3. **Synthetic Arithmetic Fallback:** If the output contains `"1"`, it calculates `score = sum(features)`, `riskScore = (score * 15).clamp(10, 100)`. If not, `riskScore = 10`. This effectively **bypasses the ML model's probabilistic classification** and replaces it with a simple manual formula.
- **Hardcoded Values:** `196` (feature dimension), `assets/models/privacy_guardian.onnx`, `* 15`, `clamp(10, 100)`, fallback `10`.
- **Duplicate Logic:** None.
- **Missing Functionality:** Proper tensor output parsing (e.g. probability tensor / class label indexing) and feature alignment with training data.
- **Production-Ready:** **No — Prototype / Proof-of-Concept Only**.

---

#### 23. `risk_agent.dart`
- **File Path:** `lib/agents/risk_agent.dart`
- **Purpose:** Coordinates the ML feature encoding and ONNX inference pipeline to evaluate an app's risk posture and produce a `RiskAssessment`.
- **Important Classes/Functions:** `RiskAgent`, `analyze(AppTelemetry app)`.
- **Android API Used:** Pure Dart calling `FeatureEncoder` and `ModelRunner`.
- **Data Collected:** Returns `RiskAssessment` (`score`, `level` ["HIGH", "MEDIUM", "LOW"], `reason`).
- **Real or Derived:** Derived assessment.
- **Device-level or App-level:** App-level assessment.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** Inherits the ML feature mismatch from `ModelRunner`.
- **Hardcoded Values:** Thresholds: `>= 80` -> HIGH, `>= 50` -> MEDIUM, else LOW.
- **Duplicate Logic:** None.
- **Missing Functionality:** Detailed explainability reasons explaining *which* specific permission or metric caused the risk score.
- **Production-Ready:** **Partial (Functional flow, but dependent on ML fixes)**.

---

#### 24. `local_triage_engine.dart`
- **File Path:** `lib/agents/local_triage_engine.dart`
- **Purpose:** Rule-based heuristic risk calculator evaluating suspicious combinations of device state and app telemetry.
- **Important Classes/Functions:** `LocalTriageEngine`, `calculateBaseRisk(AppTelemetry app)`.
- **Android API Used:** Pure Dart.
- **Data Collected:** Computes integer risk score (0 to 100).
  - Screen locked + upload > 5MB (+20)
  - Overlay permission (+20)
  - Accessibility enabled (+15)
  - Battery optimization disabled (+10)
  - VPN active (+5)
  - Foreground usage > 30 minutes (+10)
  - Permission count > 10 (+10)
- **Real or Derived:** Derived heuristic score.
- **Device-level or App-level:** Evaluates app telemetry against forwarded device context.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** Completely **unconnected** to the main app dashboard. `DashboardScreen` only calls `RiskAgent`, ignoring `LocalTriageEngine`.
- **Hardcoded Values:** Weights: `20`, `20`, `15`, `10`, `5`, `10`, `10`; threshold: `5 * 1024 * 1024` bytes (5 MB), `30` minutes, `10` permissions.
- **Duplicate Logic:** Logic overlaps with `BehaviorAgent` and `PermissionRiskAgent`.
- **Missing Functionality:** Connection to the active risk evaluation pipeline.
- **Production-Ready:** **Unconnected Component**.

---

#### 25. `behavior_agent.dart`, `context_agent.dart`, `decision_agent.dart`, `memory_agent.dart`, `permission_risk_agent.dart`
- **File Paths:**
  - `lib/agents/behavior_agent.dart`
  - `lib/agents/context_agent.dart`
  - `lib/agents/decision_agent.dart`
  - `lib/agents/memory_agent.dart`
  - `lib/agents/permission_risk_agent.dart`
- **Purpose:**
  - `BehaviorAgent`: Detects anomalous device conditions on `PrivacyEvent` (screen lock upload, overlay, accessibility, VPN, battery bypass).
  - `ContextAgent`: Checks if a permission is suspicious given an app category (e.g. UTILITY + CONTACTS, CALCULATOR + LOCATION).
  - `DecisionAgent`: Classifies risk score into actions (`>= 75` -> "BLOCK", `>= 40` -> "WARN", else "ALLOW").
  - `MemoryAgent`: Persists and retrieves app behavior strings via `SharedPreferences`.
  - `PermissionRiskAgent`: Sums static weights for 11 known permissions (CAMERA: 20, RECORD_AUDIO: 20, READ_CONTACTS: 15, READ_SMS: 25, SEND_SMS: 30, SYSTEM_ALERT_WINDOW: 30, PACKAGE_USAGE_STATS: 25, etc.).
- **Android API Used:** Pure Dart; `MemoryAgent` uses `shared_preferences`.
- **Data Collected:** Heuristic scores, action strings, persistence.
- **Real or Derived:** Derived heuristics.
- **Device-level or App-level:** Both.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:**
  1. All 5 agent files are **completely disconnected** from `DashboardScreen` and `TelemetryService`.
  2. `ContextAgent` uses 2 hardcoded string checks (`UTILITY`, `CALCULATOR`).
  3. `DecisionAgent` returns action strings ("BLOCK") that have no corresponding enforcement implementation on Android.
- **Hardcoded Values:** Permission weights, action thresholds, hardcoded category strings.
- **Duplicate Logic:** Permission weights and condition checks are duplicated across multiple agents.
- **Missing Functionality:** Integration into an orchestrated Multi-Agent System (MAS) pipeline.
- **Production-Ready:** **Stubs / Disconnected Proof-of-Concepts**.

---

### 6.5 Services, Core, UI & Widgets

---

#### 26. `api_client.dart` & `app_config.dart`
- **File Paths:** `lib/core/api_client.dart`, `lib/core/app_config.dart`
- **Purpose:** HTTP client sending `PrivacyEvent.toJson()` via `POST /analyze` to FastAPI backend at `http://10.0.2.2:8000`.
- **Important Classes/Functions:** `ApiClient`, `analyze(PrivacyEvent event)`, `AppConfig.backendUrl`.
- **Android API Used:** `package:http/http.dart`.
- **Data Collected:** Encodes entire `PrivacyEvent` as JSON payload.
- **Real or Derived:** Real payload.
- **Device-level or App-level:** Both.
- **Real-time, Periodic, Event-driven, or Historical:** On-demand HTTP POST.
- **Required Permissions:** `android.permission.INTERNET`.
- **Android Limitations:** `10.0.2.2` is Android Emulator host loopback; will not work on physical devices without an external IP/domain.
- **Problems / Incorrect Assumptions:** Unconnected to UI; no retry or auth logic.
- **Hardcoded Values:** `"http://10.0.2.2:8000"`, `"/analyze"`, `"application/json"`.
- **Duplicate Logic:** None.
- **Missing Functionality:** Error handling, certificate pinning, offline queueing.
- **Production-Ready:** **Prototype only**.

---

#### 27. `notification_service.dart`
- **File Path:** `lib/services/notification_service.dart`
- **Purpose:** Displays local user-facing notifications for privacy risks using `flutter_local_notifications`.
- **Important Classes/Functions:** `NotificationService`, `init()`, `showPrivacyAlert(id, title, body)`.
- **Android API Used:** `flutter_local_notifications` plugin.
- **Data Collected:** Shows notification on channel `'privacy_alerts_channel'`.
- **Real or Derived:** Real user alert.
- **Device-level or App-level:** App-level user presentation.
- **Real-time, Periodic, Event-driven, or Historical:** Real-time event alert.
- **Required Permissions:** `android.permission.POST_NOTIFICATIONS` (Android 13+).
- **Android Limitations:** Notification permission must be requested at runtime on Android 13+.
- **Problems / Incorrect Assumptions:** Not called from `DashboardScreen` or `RiskAgent` when a high-risk app is detected.
- **Hardcoded Values:** `'privacy_alerts_channel'`, `'Privacy Sentinel Alerts'`, `'@mipmap/ic_launcher'`.
- **Duplicate Logic:** Channel configuration overlaps with `TelemetryForegroundService.kt`.
- **Missing Functionality:** PendingIntent action handlers to open the offending app details screen.
- **Production-Ready:** **Yes (Standalone service, needs hook into risk stream)**.

---

#### 28. `dashboard_screen.dart`
- **File Path:** `lib/screens/dashboard/dashboard_screen.dart`
- **Purpose:** Primary application screen displaying real-time list of installed apps and their evaluated risk cards.
- **Important Classes/Functions:** `DashboardScreen`, `_DashboardScreenState`, `initState()`, `dispose()`, `telemetry.stream.listen()`.
- **Android API Used:** Flutter Material UI.
- **Data Collected:** Subscribes to `TelemetryService.stream`, builds `AppTelemetry` list via `AppTelemetryBuilder`, calls `RiskAgent.analyze(app)` for each app, and renders `RiskCard` list.
- **Real or Derived:** Real telemetry rendered with ML risk assessment.
- **Device-level or App-level:** Displays app-level cards with top app bar action to open diagnostics.
- **Real-time, Periodic, Event-driven, or Historical:** Live-updating UI (updates every 5 seconds).
- **Required Permissions:** None directly.
- **Android Limitations:** Renders 100-300 cards in a `ListView.builder`.
- **Problems / Incorrect Assumptions:** Iterates over all apps and calls `await agent.analyze(app)` sequentially inside `telemetry.stream.listen()` every 5 seconds. For 200 apps, running 200 sequential async ONNX inferences every 5 seconds creates unnecessary CPU load.
- **Hardcoded Values:** None.
- **Duplicate Logic:** None.
- **Missing Functionality:** Search bar, filtering by risk level (HIGH/MEDIUM/LOW), pull-to-refresh, sorting by risk score.
- **Production-Ready:** **Functional Prototype**.

---

#### 29. `telemetry_diagnostics_screen.dart`
- **File Path:** `lib/screens/settings/telemetry_diagnostics_screen.dart`
- **Purpose:** Development and auditing screen providing a complete, transparent breakdown of every single telemetry field collected from the physical Android device.
- **Important Classes/Functions:** `TelemetryDiagnosticsScreen`, `_fetchTelemetry()`, `_buildDiagnosticsTable()`, `_buildDeviceContextCard()`, `_buildSecurityContextCard()`, `_buildNetworkCard()`, `_buildSensorCard()`, `_buildUsageCard()`.
- **Android API Used:** Flutter UI calling `AndroidCollector().collectTelemetry()`.
- **Data Collected:** Renders structured verification cards for Device Context, Security Context, Network Telemetry, Sensor Privacy, Usage Stats, and a diagnostic summary table.
- **Real or Derived:** Real live inspection.
- **Device-level or App-level:** Both.
- **Real-time, Periodic, Event-driven, or Historical:** On-demand refreshable screen.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** None. Excellent engineering tool for ground-truth verification.
- **Hardcoded Values:** Formatting labels and color indicators.
- **Duplicate Logic:** None.
- **Missing Functionality:** Export diagnostic log to JSON/CSV file.
- **Production-Ready:** **Yes — Highly Complete**.

---

#### 30. `risk_card.dart`
- **File Path:** `lib/widgets/risk_card.dart`
- **Purpose:** Reusable Material Card widget displaying individual app metadata and its color-coded risk percentage.
- **Important Classes/Functions:** `RiskCard`, `build()`.
- **Android API Used:** Pure Flutter UI.
- **Data Collected:** Displays `app.appName`, `app.packageName`, permissions summary, foreground minutes, active state, and `risk.score`.
- **Real or Derived:** Real UI component.
- **Device-level or App-level:** App-level representation.
- **Real-time, Periodic, Event-driven, or Historical:** UI presentation.
- **Required Permissions:** None.
- **Android Limitations:** None.
- **Problems / Incorrect Assumptions:** Color threshold hardcoded: score >= 80 (Red), score >= 50 (Orange), else Green.
- **Hardcoded Values:** Score thresholds `80`, `50`, color choices.
- **Duplicate Logic:** Thresholds duplicate those in `RiskAgent.dart`.
- **Missing Functionality:** Tap handler to navigate to app details screen.
- **Production-Ready:** **Yes**.

---

#### 31. Empty / Stubbed Source Files (15 Files, 0 Bytes Each)
The following 15 files in `lib/` are **completely empty (0 bytes)**:
1. `lib/screens/alerts/alerts_screen.dart`
2. `lib/screens/details/app_details_screen.dart`
3. `lib/screens/monitor/monitor_screen.dart`
4. `lib/screens/settings/settings_screen.dart`
5. `lib/screens/splash_screen.dart`
6. `lib/services/cloud_ai_service.dart`
7. `lib/services/storage_service.dart`
8. `lib/utils/date_formatter.dart`
9. `lib/utils/logger.dart`
10. `lib/utils/permission_helper.dart`
11. `lib/utils/risk_calculator.dart`
12. `lib/widgets/alert_card.dart`
13. `lib/widgets/app_tile.dart`
14. `lib/widgets/permission_tile.dart`
15. `lib/widgets/score_meter.dart`

---

## 7. End-to-End Data Flow Trace (Hardware → Local Edge AI)

The complete end-to-end execution path from physical hardware sensors to local AI evaluation proceeds as follows:

```
[1. Android Hardware & OS Subsystems]
   ├── Camera Sensors (CameraManager)
   ├── Microphone Hardware (AudioManager)
   ├── Network Interfaces (Wi-Fi / Cellular Modem via TrafficStats & NetworkStatsManager)
   ├── Battery IC / Power Controller (ACTION_BATTERY_CHANGED & PowerManager)
   └── Application Sandboxes (PackageManager & AppOpsManager)
              │
              ▼
[2. Native Kotlin Collector Modules]
   ├── SensorPrivacyMonitor.kt      ──> Camera availability & Audio recording state
   ├── NetworkMonitor.kt            ──> Device total bytes & Per-UID Wi-Fi/Cell bytes
   ├── DeviceContextCollector.kt    ──> Hardware Build specs & Battery/Power/Lock state
   ├── DeviceSecurityMonitor.kt     ──> Overlay, Accessibility, ADB, Root heuristics
   ├── AppUsageMonitor.kt           ──> 24h UsageStats & UsageEvents transitions
   └── PermissionMonitor.kt         ──> Installed packages, granted/denied/dangerous flags
              │
              ▼
[3. AndroidTelemetryCollector.kt (Native Aggregator)]
   ├── Queries all 6 modules
   ├── Associates apps by packageName with UsageStats and by UID with NetworkStats
   ├── Enforces Device vs App separation
   └── Compiles List<Map<String, Any?>> diagnostics
              │
              ▼
[4. MethodChannel ("privacy_sentinel") in MainActivity.kt]
   └── Method: "getTelemetry" -> Returns Map<String, Any?> to Dart
              │
              ▼
[5. AndroidCollector (lib/telemetry/collectors/android_collector.dart)]
   └── Invokes MethodChannel and deserializes raw Map<String, dynamic>
              │
              ▼
[6. TelemetryService (lib/telemetry/telemetry_service.dart)]
   └── Periodic timer (5s) calls AndroidCollector and emits on Stream<PrivacyEvent>
              │
              ▼
[7. PrivacyEvent.fromMap (lib/models/privacy_event.dart)]
   └── Instantiates DeviceContext, SecurityContext, NetworkTelemetry, SensorPrivacyTelemetry,
       UsageSummary, List<dynamic> apps, and List<TelemetryDiagnosticItem> diagnostics
              │
              ▼
[8. AppTelemetryBuilder (lib/telemetry/app_telemetry_builder.dart)]
   └── Transforms each raw app dictionary in PrivacyEvent.apps into a strongly-typed
       AppTelemetry model with forwarded device context flags
              │
              ▼
[9. RiskAgent (lib/agents/risk_agent.dart)]
   ├── 9a. FeatureEncoder.encode(app) -> Extracts 11 numerical features
   ├── 9b. ModelRunner.predict(features) -> Pads 11 to 196 floats -> Runs ONNX inference
   └── 9c. Maps score to RiskAssessment ("HIGH" / "MEDIUM" / "LOW" + reason)
              │
              ▼
[10. DashboardScreen (lib/screens/dashboard/dashboard_screen.dart)]
   └── Renders interactive list of RiskCards with real-time risk scores and package details
```

---

## 8. MethodChannel Communication Specification

- **Channel Name:** `privacy_sentinel`
- **Binary Messenger:** `flutterEngine.dartExecutor.binaryMessenger`

| Method Name | Arguments | Return Type | Native Implementation Source | Purpose |
|---|---|---|---|---|
| `getTelemetry` | None | `Map<String, Any?>` | `AndroidTelemetryCollector.collectTelemetry()` | Fetches unified telemetry snapshot (all contexts + apps + diagnostics). |
| `getInstalledApps` | None | `List<Map<String, Any?>>` | `PermissionMonitor.getInstalledAppPermissions()` | Returns package inventory with permissions and AppOps. |
| `getUsageStats` | None | `Map<String, Any?>` | `AppUsageMonitor.getUsageTelemetry()` | Returns 24h usage statistics and foreground transitions. |
| `getDeviceContext` | None | `Map<String, Any?>` | `DeviceContextCollector.collect()` | Returns static hardware specs and dynamic battery/screen state. |
| `getDeviceSecurity` | None | `Map<String, Any?>` | `DeviceSecurityMonitor.collectSecurityState()` | Returns overlay/accessibility/dev options/root heuristic. |
| `getNetworkTelemetry`| None | `Map<String, Any?>` | `NetworkMonitor.getDeviceNetworkTelemetry()` | Returns device network totals, active transport, bandwidth, metered status. |
| `isUsageAccessGranted`| None | `Boolean` | `AppUsageMonitor.isUsageAccessGranted()` | Checks `OPSTR_GET_USAGE_STATS` AppOps status. |
| `openUsageAccessSettings`| None | `Boolean` | `Settings.ACTION_USAGE_ACCESS_SETTINGS` Intent | Opens Android system settings for Special App Usage Access. |
| `isOverlayPermissionGranted`| None | `Boolean` | `Settings.canDrawOverlays(context)` | Checks `SYSTEM_ALERT_WINDOW` permission for host app. |
| `openOverlaySettings`| None | `Boolean` | `Settings.ACTION_MANAGE_OVERLAY_PERMISSION` Intent | Opens overlay settings for host package. |
| `isBatteryOptimizationIgnored`| None | `Boolean` | `PowerManager.isIgnoringBatteryOptimizations` | Checks if host app is exempted from Doze battery restrictions. |
| `openBatteryOptimizationSettings`| None | `Boolean` | `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` | Opens Doze battery optimization settings. |
| `startForegroundService`| None | `Boolean` | `TelemetryForegroundService.ACTION_START` | Launches native foreground monitoring service (`dataSync`). |
| `stopForegroundService`| None | `Boolean` | `TelemetryForegroundService.ACTION_STOP` | Stops native foreground service and removes notification. |
| `isForegroundServiceRunning`| None | `Boolean` | `TelemetryForegroundService.isServiceRunning` | Checks active execution flag of foreground service. |

---

## 9. Telemetry Classification & Scoping Matrix

### 9.1 Device-Level vs. App-Level Telemetry

```
+---------------------------------------------------------------------------------------------------+
|                                      DEVICE-LEVEL TELEMETRY                                       |
|                                                                                                   |
|  - Hardware Specifications (Manufacturer, Model, Brand, Board, Hardware, SDK)                     |
|  - Dynamic Power & Battery (Level, Plugged, Status, Health, Voltage, Temperature, PowerSave, Doze)|
|  - Screen Interactivity & Lock State (isInteractive, isKeyguardLocked, isDeviceSecure)            |
|  - Global Developer & System Settings (DEVELOPMENT_SETTINGS_ENABLED, ADB_ENABLED)                 |
|  - Accessibility Services State (accessibilityEnabled, list of enabled service component IDs)     |
|  - Device Network Transports & Totals (Active Wi-Fi/Cell/VPN, link bandwidth, TrafficStats totals)|
|  - Sensor Hardware Occupancy (cameraHardwareInUse, microphoneHardwareInUse, audioMode)            |
|  - Device Root Status Heuristic (Test-keys build tags, SU binary paths, root manager packages)    |
+---------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+---------------------------------------------------------------------------------------------------+
|                                       APP-LEVEL TELEMETRY                                         |
|                                                                                                   |
|  - Application Identity (Package Name, App Name, UID, Version Code/Name, System/User App Flag)    |
|  - Permission Profiles (Requested list, Granted list, Denied list, Dynamic Dangerous list)        |
|  - Per-App Special AppOps (SYSTEM_ALERT_WINDOW Op status, GET_USAGE_STATS Op status)               |
|  - Installation Provenance (firstInstallTime, lastUpdateTime, installerPackageName)               |
|  - 24-Hour Usage Analytics (foregroundDurationMs, foregroundMinutes, transitionCount, lastUsedMs) |
|  - Live App State Heuristics (isCurrentlyForeground, isRecentlyUsedDerived)                       |
|  - Per-UID Network Traffic (Wi-Fi/Cellular txBytes & rxBytes via NetworkStatsManager)             |
+---------------------------------------------------------------------------------------------------+
```

### 9.2 Real-Time vs. Periodic vs. Event-Driven vs. Historical

| Telemetry Field | Scope | Category | Temporal Mechanism | Source Android API |
|---|---|---|---|---|
| `screenOn`, `screenLocked` | Device | Real-Time | Instantaneous Poll | `PowerManager.isInteractive`, `KeyguardManager.isKeyguardLocked` |
| `batteryPercent`, `batteryTemp`| Device | Real-Time | Sticky Broadcast | `Intent.ACTION_BATTERY_CHANGED` |
| `cameraHardwareInUse` | Device | Event-Driven | OS Callback Event | `CameraManager.AvailabilityCallback` |
| `microphoneHardwareInUse` | Device | Real-Time | Instantaneous Poll | `AudioManager.getActiveRecordingConfigurations()` |
| `developerOptions`, `adb` | Device | Real-Time | Global Settings Query | `Settings.Global.getInt()` |
| `accessibilityEnabled` | Device | Real-Time | Manager Query | `AccessibilityManager.getEnabledAccessibilityServiceList` |
| `deviceTotalTx/RxBytes` | Device | Cumulative | Periodic Snapshot | `TrafficStats.getTotalTxBytes() / getTotalRxBytes()` |
| `installedPackages` | App | Cached Snapshot| 10s In-Memory Cache | `PackageManager.getInstalledPackages()` |
| `dangerousPermissions` | App | Cached Snapshot| ConcurrentHashMap Cache | `PackageManager.getPermissionInfo()` |
| `hasOverlayOp`, `hasUsageOp`| App | Cached Snapshot| In-Memory Query | `AppOpsManager.unsafeCheckOpNoThrow()` |
| `foregroundDurationMs` | App | Historical | 24-Hour Daily Aggregation | `UsageStatsManager.queryUsageStats()` |
| `foregroundTransitionCount`| App | Event-Driven | Aggregated Interval Events | `UsageEvents.Event.ACTIVITY_RESUMED / MOVE_TO_FOREGROUND` |
| `isCurrentlyForeground` | App | Real-Time Event | Latest Observed Transition | Derived from `UsageEvents` timestamp matching |
| `app upload/downloadBytes` | App | Historical | 24-Hour Aggregation | `NetworkStatsManager.querySummary()` |

### 9.3 Real Ground-Truth Data vs. Derived Heuristic Signals

| Field / Output | Nature | Basis & Computation Method |
|---|---|---|
| `isDeviceSecure` | **Real Ground-Truth** | Direct hardware Keyguard PIN/Pattern/Biometric check via `KeyguardManager.isDeviceSecure`. |
| `dangerousPermissions` | **Real Ground-Truth** | Directly queries Android OS `PermissionInfo.protectionLevel & PROTECTION_MASK_BASE == PROTECTION_DANGEROUS`. |
| `cameraHardwareInUse` | **Real Ground-Truth** | Device-level hardware camera availability via `CameraManager.AvailabilityCallback`. |
| `microphoneHardwareInUse`| **Real Ground-Truth** | Device-level audio recording stream presence via `AudioManager.activeRecordingConfigurations`. |
| `isRecentlyUsedDerived` | **Derived Signal** | Evaluated via heuristic formula: `(System.currentTimeMillis() - lastUsedMs) < (5 * 60 * 1000)`. |
| `isRootedHeuristic` | **Derived Signal** | Probabilistic score evaluated from 3 independent indicator probes (build tags, su binaries, packages). |
| `risk.score` (RiskAgent) | **Derived Signal** | Output of `ModelRunner` / zero-padded ONNX inference + arithmetic fallback. |

---

## 10. Android System Permissions, API Restrictions & Platform Boundaries

### 1. Declared Manifest Permissions (`android/app/src/main/AndroidManifest.xml`)
- `android.permission.QUERY_ALL_PACKAGES`: Required on Android 11+ (API 30+) to inspect all installed applications.
- `android.permission.PACKAGE_USAGE_STATS`: Special access permission (granted via Settings) required for `UsageStatsManager` and `NetworkStatsManager`.
- `android.permission.FOREGROUND_SERVICE`: Base foreground service permission.
- `android.permission.FOREGROUND_SERVICE_DATA_SYNC`: Required on Android 14+ (API 34+) for foreground services of type `dataSync`.
- `android.permission.POST_NOTIFICATIONS`: Runtime permission required on Android 13+ (API 33+) to display persistent notifications.
- `android.permission.INTERNET` & `ACCESS_NETWORK_STATE`: Network inspection and backend communication.
- `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`: Prompts user to exempt app from Doze mode.

### 2. Platform Sandbox Boundaries & Privacy Restrictions
1. **Per-App Sensor Attribution Restriction:** Android intentionally **prevents unprivileged third-party apps from knowing which specific application is accessing the camera or microphone**. The native collector strictly adheres to this boundary by reporting device-level occupancy (`attributionScope = "DEVICE_LEVEL_ONLY"`).
2. **Per-UID TrafficStats Deprecation:** Calling `TrafficStats.getUidTxBytes(uid)` for non-owned UIDs returns `TrafficStats.UNSUPPORTED (-1)` on Android 9+ (API 28+). The project correctly uses `NetworkStatsManager.querySummary()` to legitimately access per-UID Wi-Fi and Cellular statistics.
3. **Usage Access Grant Requirement:** `UsageStatsManager` and `NetworkStatsManager` queries return empty/zero results if the user has not explicitly granted "Usage Access" in Android System Settings. The project gracefully handles this by reporting availability status (`"RESTRICTED"`, `"PACKAGE_USAGE_STATS_REQUIRED"`).
4. **Android 14/15/16 Foreground Service Enforcement:** Starting in Android 14 (API 34), foreground services must declare a specific `foregroundServiceType` in both the manifest and code (`startForeground(..., FOREGROUND_SERVICE_TYPE_DATA_SYNC)`). This is fully implemented in `TelemetryForegroundService.kt`.

---

## 11. Codebase Anomalies & Critical Audit Findings

### 11.1 Hardcoded Values & Magic Numbers
1. `ml/feature_encoder.dart`: Hardcoded division `/ 1000000` for byte conversion instead of using standard `1024 * 1024` (1048576) binary megabyte conversion.
2. `ml/model_runner.dart`: Hardcoded 196 tensor input size (`List<double>.filled(196, 0.0)`), hardcoded multiplier `* 15`, hardcoded clamp range `(10, 100)`, and fallback `10`.
3. `agents/permission_risk_agent.dart`: Hardcoded weight map (`"CAMERA": 20`, `"RECORD_AUDIO": 20`, `"READ_SMS": 25`, `"SEND_SMS": 30`, etc.).
4. `agents/local_triage_engine.dart`: Hardcoded upload threshold `5 * 1024 * 1024` (5 MB), usage threshold `30` minutes, permission count threshold `10`.
5. `agents/decision_agent.dart`: Hardcoded thresholds: `>= 75` -> "BLOCK", `>= 40` -> "WARN".
6. `agents/context_agent.dart`: Hardcoded category strings `"UTILITY"`, `"CALCULATOR"`.
7. `core/app_config.dart`: Hardcoded emulator backend URL `"http://10.0.2.2:8000"`.
8. `android/app/src/main/kotlin/.../AppUsageMonitor.kt`: Hardcoded `5 * 60 * 1000` (5 minutes recency threshold).

### 11.2 Incorrect Implementations & Architectural Mismatches
1. **The ONNX Model & Feature Dimension Mismatch (Critical Defect):**
   - The machine learning model (`privacy_guardian.onnx`) was trained with `train_model.py` on `privacy_dataset.csv`, which has **196 tabular columns**.
   - `feature_encoder.dart` extracts only **11 basic features**.
   - `model_runner.dart` pads the remaining 185 features with `0.0`.
   - `model_runner.dart` then inspects the output string for `"1"` and calculates a manual heuristic: `(sum(features) * 15).clamp(10, 100)`.
   - **Impact:** The ONNX machine learning model is effectively bypassed and rendered non-functional; the reported risk score is a simple manual sum of the 11 features.
2. **Sequential UI Blocking in Dashboard Stream:**
   - In `dashboard_screen.dart`, when a new `PrivacyEvent` arrives on `telemetry.stream`, it loops through all apps and sequentially awaits `agent.analyze(app)` for each app. On devices with 200+ apps, executing 200 sequential model calls every 5 seconds creates severe CPU overhead and battery drain.
3. **Duplicate `AIResponse` Class:**
   - `lib/core/constants.dart` defines `class AIResponse { ... }` which is an exact duplicate of `lib/models/ai_response.dart`. `constants.dart` should contain system configuration constants, not duplicate domain models.

### 11.3 Duplicate / Redundant Code & Dead Code
1. `DeviceStateMonitor.kt`: Redundant wrapper around `DeviceContextCollector.kt` that re-instantiates the collector on every method call.
2. `AppUsageService.dart`: Redundant one-line wrapper delegating to `AndroidCollector`.
3. `AndroidTelemetryCollector.kt`: Emits redundant top-level compatibility keys (`screenLocked`, `screenOn`, `uploadBytes`, `downloadBytes`, `rootDetected`) duplicating nested map fields.

### 11.4 Empty / Stubbed Files (Zero-Byte Files)
There are **15 completely empty files (0 bytes)** in the repository:
- `lib/screens/alerts/alerts_screen.dart`
- `lib/screens/details/app_details_screen.dart`
- `lib/screens/monitor/monitor_screen.dart`
- `lib/screens/settings/settings_screen.dart`
- `lib/screens/splash_screen.dart`
- `lib/services/cloud_ai_service.dart`
- `lib/services/storage_service.dart`
- `lib/utils/date_formatter.dart`
- `lib/utils/logger.dart`
- `lib/utils/permission_helper.dart`
- `lib/utils/risk_calculator.dart`
- `lib/widgets/alert_card.dart`
- `lib/widgets/app_tile.dart`
- `lib/widgets/permission_tile.dart`
- `lib/widgets/score_meter.dart`

---

## 12. Phase 1 Completion Assessment & Component Scoring

| Architectural Layer / Component | Implementation Status | Functional Quality | Phase-1 Completion % |
|---|---|---|:---:|
| **Android Native Collectors (Kotlin)** | 8 Modular Collectors + Foreground Service + Aggregator | Production-Grade; Complete API 26-36 compliance | **100%** |
| **Android Manifest & Permissions** | All required permissions & queries declared | Compliant | **100%** |
| **MethodChannel Bridge** | 15 Native methods implemented in `MainActivity.kt` | Fully wired to Dart `AndroidCollector` | **95%** |
| **Flutter Telemetry Pipeline** | `TelemetryService`, `PrivacyEvent`, `AppTelemetryBuilder` | Complete domain parsing & stream pipeline | **95%** |
| **Telemetry Diagnostics UI** | `TelemetryDiagnosticsScreen` | Complete real-device verification inspector | **100%** |
| **Core UI & Presentation** | `DashboardScreen`, `RiskCard` | Functional prototype (15 empty UI screens/widgets) | **40%** |
| **Edge AI / ML Inference** | `FeatureEncoder`, `ModelRunner`, `privacy_guardian.onnx` | Feature dimension mismatch (11 vs 196) & manual fallback | **30%** |
| **Multi-Agent System** | 7 Agent classes created | Disconnected stubs; not orchestrated in stream | **25%** |
| **Local Storage & Services** | `notification_service`, `api_client` (Storage empty) | `storage_service.dart` is 0 bytes | **20%** |
| **Overall Phase 1 Score** | **Core Telemetry & Pipeline Complete; ML & UI Stubs Pending** | **Solid Architectural Foundation** | **85%** |

---

## 13. Actionable Recommendations & Roadmap

### Immediate Fixes (Phase 1 Finalization)
1. **Re-align Edge ML Feature Vector (Critical):**
   - Retrain the RandomForest model in `ai_training/train_model.py` to accept the exact 15-20 features generated by the live mobile collector (e.g. `isSystemApp`, `dangerousPermissionsCount`, `hasOverlayOp`, `hasUsageAccessOp`, `foregroundMinutes`, `uploadBytes`, `downloadBytes`, `isScreenLocked`, `isAccessibilityEnabled`, `isVpnActive`, `isRooted`).
   - Export the retrained ONNX model, replace `assets/models/privacy_guardian.onnx`, and update `FeatureEncoder.dart` and `ModelRunner.dart` to perform genuine tensor output probability extraction without zero-padding hacks.
2. **Populate Empty UI Screens & Widgets:**
   - Implement `AppDetailsScreen` to inspect individual package permissions and usage breakdowns when a user taps a `RiskCard`.
   - Implement `AlertsScreen` to show high-risk security alerts.
   - Implement `MonitorScreen` for live network traffic graphs and sensor activity.
   - Implement `SettingsScreen` with toggles for background monitoring interval, telemetry refresh rate, and cloud backend sync.
3. **Clean Up Code Duplication & Empty Files:**
   - Remove duplicate `AIResponse` class from `lib/core/constants.dart` and populate it with actual system constants (e.g. default intervals, risk thresholds).
   - Implement utility files (`logger.dart`, `date_formatter.dart`, `permission_helper.dart`).
   - Delete obsolete `DeviceStateMonitor.kt`.

### Phase 2 Roadmap (Edge Multi-Agent Orchestration)
1. **Multi-Agent Triage Pipeline:**
   - Wire `LocalTriageEngine`, `BehaviorAgent`, and `ContextAgent` into a unified `AgentCoordinator` that executes on every `PrivacyEvent` stream emission.
2. **Native EventChannel for Background Push:**
   - Add a Flutter `EventChannel` to `TelemetryForegroundService.kt` to push periodic 30-second background snapshots directly into Dart memory even when the main Flutter UI is minimized.
3. **Local SQLite Persistence:**
   - Implement `storage_service.dart` using `sqflite` to record historical telemetry events and track app risk score trends over 7-day and 30-day windows.
