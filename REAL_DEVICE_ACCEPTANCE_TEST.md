# Real Device Acceptance Test Protocol

**Project**: Mobile Privacy & Security Project — Phase 1 Hardening  
**Target Environment**: Physical Android Smartphone (Android 10+ / targetSdk 36)  
**Execution Date**: September 19, 2026  

---

## Pre-Requisites & Permissions
Before initiating the physical device acceptance test:
1. Deploy app APK to physical Android hardware (`flutter run --release` or `flutter install`).
2. Grant **Usage Access Permission** via system settings (`Settings -> Security -> Usage Access`).
3. Grant **Notification Permission** (Android 13+).
4. Verify battery optimization whitelist / background execution settings.

---

## Acceptance Test Protocol (16 Scenarios)

| # | Action / Scenario | Physical Device Procedure | Expected Empirical Signal | Verification Criterion | Status |
|---|---|---|---|---|---|
| 1 | **Start Collection Session** | Open App -> Dataset Collection -> Tap "Start Collection". | Notification shown, `isCollecting == true`, `sessionId` created. | `sessionId` present in active session metadata & native prefs. | `[READY FOR DEVICE]` |
| 2 | **Open Instagram** | Launch Instagram, scroll feed for 30s. | Package `com.instagram.android` transition to foreground. | `isCurrentlyForeground == true`, `foregroundDurationMs > 0`, `usageAvailability == "VALID"`. | `[READY FOR DEVICE]` |
| 3 | **Browse Chrome** | Open Chrome, visit news/web page for 30s. | Package `com.android.chrome` in foreground, NetworkStats increase. | `downloadBytes > 0`, `uploadBytes > 0`, `networkUsageAvailability == "VALID"`. | `[READY FOR DEVICE]` |
| 4 | **Use Camera** | Open System Camera App, take photo/video. | Device-level `cameraUnavailable == true` / `cameraAvailable == false` callback. | `cameraUnavailable` recorded as device availability status (NOT attributed as fake app usage). | `[READY FOR DEVICE]` |
| 5 | **Record Audio** | Open Voice Recorder / Send voice message. | `microphoneHardwareInUse == true` / `activeAudioRecordingsCount >= 1`. | `microphoneHardwareInUse == true`, `sensorAvailability == "VALID"`. | `[READY FOR DEVICE]` |
| 6 | **Make Phone Call** | Dial phone number, answer/hold for 15s. | Audio mode changes to `IN_CALL` or `IN_COMMUNICATION`. | `audioMode == "IN_CALL"` or `"IN_COMMUNICATION"`. | `[READY FOR DEVICE]` |
| 7 | **Use Wi-Fi / Mobile** | Toggle Wi-Fi off -> Mobile Data on -> load page. | `transport` switches (`WIFI` -> `CELLULAR`), `isMetered` updates. | `transport == "CELLULAR"`, `trafficStatsAvailability == "VALID"`. | `[READY FOR DEVICE]` |
| 8 | **Lock Screen** | Press Power button to turn off screen. | `screenOn == false`, `screenLocked == true`. | `screenOn == false`, `screenLocked == true` in device context. | `[READY FOR DEVICE]` |
| 9 | **Unlock Screen** | Unlock device with PIN/Fingerprint. | `screenOn == true`, `screenLocked == false`. | `screenOn == true`, `screenLocked == false` in device context. | `[READY FOR DEVICE]` |
| 10| **Background Apps** | Press Home button, leave app in background 2 min. | `TelemetryForegroundService` polls periodically in background. | Native JSONL appends records natively while UI is inactive. | `[READY FOR DEVICE]` |
| 11| **Stop Collection** | Reopen App -> Tap "Stop Collection". | Service stops, `state == STOPPED`, final count/size saved. | `stopTime` saved, file flushed, zero dangling background tasks. | `[READY FOR DEVICE]` |
| 12| **Restart Application** | Force stop app from settings & relaunch. | Pseudonymous UUID & persisted JSONL file remain intact. | `deviceIdHash` matches previous session, storage file loads. | `[READY FOR DEVICE]` |
| 13| **Open Dataset Viewer** | Navigate to Dataset Viewer screen. | Persisted records rendered in list, filters active. | All session records visible with complete details. | `[READY FOR DEVICE]` |
| 14| **Verify Persistence** | Inspect record timestamps, packages, and health. | Telemetry records contain original event timestamps. | Timestamps are original event time (NOT `DateTime.now()`). | `[READY FOR DEVICE]` |
| 15| **Export Dataset** | Tap "Export Session" -> Save `.jsonl` file. | File exported to target destination without truncation. | JSONL contains valid `datasetSchema`, `featureSchema`, and records. | `[READY FOR DEVICE]` |
| 16| **Inspect JSONL/JSON** | Open exported JSONL file in text editor. | Verify 100% schema compliance & availability states. | Availability states (`VALID`, `RESTRICTED`, `UNAVAILABLE`) preserved. | `[READY FOR DEVICE]` |

---

## Detailed Field Audit Matrix for Physical Verification

For every record captured during testing, verify the presence and fidelity of these 9 canonical pillars:

1. **`timestamp`**: Native event timestamp in ISO 8601 format (e.g. `2026-09-19T09:30:00Z`), never overwritten with `DateTime.now()`.
2. **`packageName`**: Real package string (e.g., `com.instagram.android`, `com.android.chrome`).
3. **`usage`**: `foregroundDurationMs`, `lastTimeUsedMs`, `isCurrentlyForeground`, `usageAvailability`.
4. **`network`**: `uploadBytes`, `downloadBytes`, `transport`, `isMetered`, `networkUsageAvailability`.
5. **`permissions`**: `requestedPermissions`, `grantedPermissions`, `deniedPermissions`, `dangerousGrantedPermissions`.
6. **`deviceContext`**: `brand`, `model`, `androidVersion`, `sdkInt`, `screenOn`, `screenLocked`, `batteryPercent`, `isCharging`.
7. **`sensorContext`**: `cameraUnavailable`, `cameraAvailable`, `cameraAvailabilityStatus`, `microphoneHardwareInUse`, `activeAudioRecordingsCount`, `audioMode`, `sensorAvailability`.
8. **`availabilityState`**: Explicit status strings (`VALID`, `ZERO_REPORTED`, `DENIED`, `RESTRICTED`, `UNAVAILABLE`, `ERROR`, `UNKNOWN`).
9. **`provenance`**: `recordId`, `sessionId`, stable pseudonymous `deviceIdHash`.
