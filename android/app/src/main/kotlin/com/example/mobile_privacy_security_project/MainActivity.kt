package com.example.mobile_privacy_security_project

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "privacy_sentinel"
    private val EVENT_CHANNEL = "privacy_sentinel_events"

    private lateinit var telemetryCollector: AndroidTelemetryCollector
    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private val telemetryListener: (Map<String, Any?>) -> Unit = { telemetry ->
        mainHandler.post {
            try {
                eventSink?.success(telemetry)
            } catch (_: Exception) {
                // Event sink closed or stream cancelled
            }
        }
    }
    private val sensorEventListener: (Map<String, Any?>) -> Unit = { sensorEvent ->
        mainHandler.post {
            val sinkActive = (eventSink != null)
            Log.i("MainActivity", "SENSOR_EVENT_EMITTED: sensor=${sensorEvent["sensor"]} state=${sensorEvent["state"]} sinkActive=$sinkActive")
            Log.i("MainActivity", "EVENT_CHANNEL_EMIT: type=sensor_access sinkActive=$sinkActive payload=$sensorEvent")
            try {
                if (eventSink != null) {
                    eventSink?.success(sensorEvent)
                } else {
                    Log.w("MainActivity", "EVENT_CHANNEL_EMIT: eventSink is null; Flutter is not listening to EventChannel")
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "EVENT_CHANNEL_EMIT: Error sending event to sink: ${e.message}")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        telemetryCollector = AndroidTelemetryCollector.getInstance(this)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (nm != null && nm.getNotificationChannel("privacy_sensor_alerts") == null) {
                val channel = NotificationChannel(
                    "privacy_sensor_alerts",
                    "Privacy Sentinel Sensor Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Real-time alerts when applications access camera, microphone, photos, or files"
                    enableVibration(true)
                    setShowBadge(true)
                }
                nm.createNotificationChannel(channel)
                Log.i("MainActivity", "NOTIFICATION_CHANNEL_CREATED: privacy_sensor_alerts")
            }
        }

        // Automatically start background TelemetryForegroundService for continuous 24/7 protection
        try {
            val serviceIntent = Intent(this, TelemetryForegroundService::class.java).apply {
                action = TelemetryForegroundService.ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            Log.i("MainActivity", "Auto-started TelemetryForegroundService for 24/7 privacy protection")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to auto-start TelemetryForegroundService: ${e.message}")
        }

        // Setup MethodChannel for request-response invocation
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getTelemetry" -> {
                        val forceRefresh = call.argument<Boolean>("forceRefresh") ?: false
                        telemetryCollector.collectTelemetryAsync(forceRefresh) { telemetryMap ->
                            mainHandler.post {
                                result.success(telemetryMap)
                            }
                        }
                    }

                    "getInstalledApps" -> {
                        val forceRefresh = call.argument<Boolean>("forceRefresh") ?: false
                        backgroundExecutor.execute {
                            try {
                                val apps = telemetryCollector.getInstalledApps(forceRefresh)
                                mainHandler.post { result.success(apps) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("GET_APPS_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "getUsageStats" -> {
                        val forceRefresh = call.argument<Boolean>("forceRefresh") ?: false
                        backgroundExecutor.execute {
                            try {
                                val stats = telemetryCollector.getUsageStats(forceRefresh)
                                mainHandler.post { result.success(stats) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("GET_USAGE_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "getDeviceContext" -> {
                        backgroundExecutor.execute {
                            try {
                                val data = telemetryCollector.getDeviceContext()
                                mainHandler.post { result.success(data) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("DEVICE_CONTEXT_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "getDeviceSecurity" -> {
                        backgroundExecutor.execute {
                            try {
                                val data = telemetryCollector.getDeviceSecurity()
                                mainHandler.post { result.success(data) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("DEVICE_SECURITY_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "getNetworkTelemetry" -> {
                        backgroundExecutor.execute {
                            try {
                                val data = telemetryCollector.getNetworkTelemetry()
                                mainHandler.post { result.success(data) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("NETWORK_TELEMETRY_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "getSensorTelemetry" -> {
                        backgroundExecutor.execute {
                            try {
                                val data = telemetryCollector.getSensorTelemetry()
                                mainHandler.post { result.success(data) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("SENSOR_TELEMETRY_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "getTelemetryHealth" -> {
                        backgroundExecutor.execute {
                            try {
                                val data = telemetryCollector.getTelemetryHealth()
                                mainHandler.post { result.success(data) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("TELEMETRY_HEALTH_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "isUsageAccessGranted" -> {
                        backgroundExecutor.execute {
                            try {
                                val granted = telemetryCollector.isUsageAccessGranted()
                                mainHandler.post { result.success(granted) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("USAGE_ACCESS_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "openUsageAccessSettings" -> {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    }

                    "isOverlayPermissionGranted" -> {
                        result.success(telemetryCollector.isOverlayPermissionGranted())
                    }

                    "openOverlaySettings" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    }

                    "isBatteryOptimizationIgnored" -> {
                        result.success(telemetryCollector.isBatteryOptimizationIgnored())
                    }

                    "openBatteryOptimizationSettings" -> {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    }

                    "startForegroundService" -> {
                        val serviceIntent = Intent(this, TelemetryForegroundService::class.java).apply {
                            action = TelemetryForegroundService.ACTION_START
                        }
                        ContextCompat.startForegroundService(this, serviceIntent)
                        result.success(true)
                    }

                    "stopForegroundService" -> {
                        val serviceIntent = Intent(this, TelemetryForegroundService::class.java).apply {
                            action = TelemetryForegroundService.ACTION_STOP
                        }
                        startService(serviceIntent)
                        result.success(true)
                    }

                    "isForegroundServiceRunning" -> {
                        result.success(TelemetryForegroundService.isServiceRunning)
                    }

                    "getForegroundServiceState" -> {
                        result.success(TelemetryForegroundService.serviceState.name)
                    }

                    "getForegroundServiceHealth" -> {
                        result.success(TelemetryForegroundService.getServiceHealth())
                    }

                    "startCollectionSession" -> {
                        val sessionId = call.argument<String>("sessionId")
                        telemetryCollector.setCollectionSession(true, sessionId)
                        result.success(true)
                    }

                    "stopCollectionSession" -> {
                        telemetryCollector.setCollectionSession(false, null)
                        result.success(true)
                    }

                    "getAppIcon" -> {
                        val pkgName = call.argument<String>("packageName")
                        if (pkgName.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "Package name is required", null)
                        } else {
                            backgroundExecutor.execute {
                                try {
                                    val iconBytes = telemetryCollector.getAppIcon(pkgName)
                                    mainHandler.post { result.success(iconBytes) }
                                } catch (e: Exception) {
                                    mainHandler.post { result.success(null) }
                                }
                            }
                        }
                    }

                    "checkSpeechRecognitionAvailability" -> {
                        backgroundExecutor.execute {
                            try {
                                val diag = telemetryCollector.checkSpeechRecognitionAvailability()
                                mainHandler.post { result.success(diag) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("SPEECH_CHECK_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "getSensorCapabilities" -> {
                        backgroundExecutor.execute {
                            try {
                                val caps = telemetryCollector.getSensorCapabilities()
                                mainHandler.post { result.success(caps) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("SENSOR_CAPABILITIES_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "reconcileSensorState" -> {
                        backgroundExecutor.execute {
                            try {
                                val state = telemetryCollector.reconcileSensorState()
                                mainHandler.post { result.success(state) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("RECONCILE_SENSOR_STATE_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "checkNotificationPermission" -> {
                        val status = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            val enabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
                            if (enabled) "GRANTED" else "DENIED"
                        } else {
                            val permCheck = ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS)
                            if (permCheck == PackageManager.PERMISSION_GRANTED) {
                                "GRANTED"
                            } else {
                                val prefs = getSharedPreferences("privacy_sentinel_prefs", Context.MODE_PRIVATE)
                                val hasRequested = prefs.getBoolean("has_requested_post_notifications", false)
                                if (!hasRequested) "NOT_REQUESTED" else "DENIED"
                            }
                        }
                        Log.i("MainActivity", "NOTIFICATION_PERMISSION_CHECK: status=$status")
                        result.success(status)
                    }

                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val prefs = getSharedPreferences("privacy_sentinel_prefs", Context.MODE_PRIVATE)
                            prefs.edit().putBoolean("has_requested_post_notifications", true).apply()
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    }

                    "checkNotificationChannel" -> {
                        val channelId = call.argument<String>("channelId") ?: "privacy_sensor_alerts"
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                        if (nm == null) {
                            Log.w("MainActivity", "NOTIFICATION_CHANNEL_CHECK: NotificationManager is null")
                            result.success(mapOf(
                                "exists" to false,
                                "importance" to 0,
                                "importanceName" to "NONE",
                                "notificationsEnabled" to false,
                                "disabled" to true
                            ))
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val areEnabled = nm.areNotificationsEnabled()
                            val channel = nm.getNotificationChannel(channelId)
                            if (channel == null) {
                                Log.w("MainActivity", "NOTIFICATION_CHANNEL_CHECK: channel=$channelId DOES_NOT_EXIST notificationsEnabled=$areEnabled")
                                result.success(mapOf(
                                    "exists" to false,
                                    "importance" to 0,
                                    "importanceName" to "DOES_NOT_EXIST",
                                    "notificationsEnabled" to areEnabled,
                                    "disabled" to true
                                ))
                            } else {
                                val imp = channel.importance
                                val impName = when (imp) {
                                    NotificationManager.IMPORTANCE_NONE -> "NONE"
                                    NotificationManager.IMPORTANCE_MIN -> "MIN"
                                    NotificationManager.IMPORTANCE_LOW -> "LOW"
                                    NotificationManager.IMPORTANCE_DEFAULT -> "DEFAULT"
                                    NotificationManager.IMPORTANCE_HIGH -> "HIGH"
                                    NotificationManager.IMPORTANCE_MAX -> "MAX"
                                    else -> "UNKNOWN"
                                }
                                val disabled = !areEnabled || imp == NotificationManager.IMPORTANCE_NONE
                                Log.i("MainActivity", "NOTIFICATION_CHANNEL_CHECK: channel=$channelId exists=true importance=$impName notificationsEnabled=$areEnabled disabled=$disabled")
                                result.success(mapOf(
                                    "exists" to true,
                                    "importance" to imp,
                                    "importanceName" to impName,
                                    "notificationsEnabled" to areEnabled,
                                    "disabled" to disabled
                                ))
                            }
                        } else {
                            val areEnabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
                            result.success(mapOf(
                                "exists" to true,
                                "importance" to 4,
                                "importanceName" to "HIGH",
                                "notificationsEnabled" to areEnabled,
                                "disabled" to !areEnabled
                            ))
                        }
                    }

                    "getShizukuStatus" -> {
                        backgroundExecutor.execute {
                            try {
                                val status = telemetryCollector.getShizukuStatus()
                                mainHandler.post { result.success(status) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("SHIZUKU_STATUS_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "setPreciseModeEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        backgroundExecutor.execute {
                            try {
                                telemetryCollector.setPreciseModeEnabled(enabled)
                                mainHandler.post { result.success(true) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("SHIZUKU_SET_MODE_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "requestShizukuPermission" -> {
                        backgroundExecutor.execute {
                            try {
                                val requested = telemetryCollector.requestShizukuPermission()
                                mainHandler.post { result.success(requested) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("SHIZUKU_REQUEST_PERM_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "openShizukuApp" -> {
                        try {
                            val shizukuPackage = "moe.shizuku.privileged.api"
                            val launchIntent = packageManager.getLaunchIntentForPackage(shizukuPackage)
                            if (launchIntent != null) {
                                launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                startActivity(launchIntent)
                                result.success(true)
                            } else {
                                val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$shizukuPackage")).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(marketIntent)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            try {
                                val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://shizuku.rikka.app")).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(webIntent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("OPEN_SHIZUKU_ERROR", e2.message, e2.stackTraceToString())
                            }
                        }
                    }

                    "setVoiceAlertsEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("flutter.voice_alerts_enabled", enabled).apply()
                        Log.i("MainActivity", "Voice alerts setting updated: enabled=$enabled")
                        result.success(true)
                    }

                    "isVoiceAlertsEnabled" -> {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val enabled = prefs.getBoolean("flutter.voice_alerts_enabled", true)
                        result.success(enabled)
                    }

                    "setNotificationsEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("flutter.notifications_enabled", enabled).apply()
                        Log.i("MainActivity", "Alert notifications setting updated: enabled=$enabled")
                        result.success(true)
                    }

                    "isNotificationsEnabled" -> {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val enabled = prefs.getBoolean("flutter.notifications_enabled", true)
                        result.success(enabled)
                    }

                    "openAppSettings" -> {
                        val pkgName = call.argument<String>("packageName") ?: ""
                        if (pkgName.isNotBlank()) {
                            try {
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$pkgName")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("OPEN_APP_SETTINGS_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "Package name is required", null)
                        }
                    }

                    "blockSensorAccess" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val sensor = call.argument<String>("sensor") ?: "CAMERA"
                        backgroundExecutor.execute {
                            try {
                                val outcome = telemetryCollector.blockSensorAccess(packageName, sensor)
                                mainHandler.post { result.success(outcome) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("BLOCK_SENSOR_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "restoreSensorAccess" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val sensor = call.argument<String>("sensor") ?: "CAMERA"
                        backgroundExecutor.execute {
                            try {
                                val outcome = telemetryCollector.restoreSensorAccess(packageName, sensor)
                                mainHandler.post { result.success(outcome) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("RESTORE_SENSOR_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "checkSensorPermission" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val sensor = call.argument<String>("sensor") ?: "CAMERA"
                        backgroundExecutor.execute {
                            try {
                                val granted = telemetryCollector.checkSensorPermission(packageName, sensor)
                                mainHandler.post { result.success(granted) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("CHECK_PERMISSION_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    "getUserActionAuditLog" -> {
                        backgroundExecutor.execute {
                            try {
                                val logs = telemetryCollector.getUserActionAuditLog()
                                mainHandler.post { result.success(logs) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("AUDIT_LOG_ERROR", e.message, e.stackTraceToString()) }
                            }
                        }
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                result.error("TELEMETRY_ERROR", e.message, e.stackTraceToString())
            }
        }

        // Setup EventChannel for real-time telemetry streaming
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                telemetryCollector.addTelemetryListener(telemetryListener)
                telemetryCollector.addSensorEventListener(sensorEventListener)
            }

            override fun onCancel(arguments: Any?) {
                telemetryCollector.removeTelemetryListener(telemetryListener)
                telemetryCollector.removeSensorEventListener(sensorEventListener)
                eventSink = null
            }
        })
    }

    override fun onDestroy() {
        if (::telemetryCollector.isInitialized) {
            telemetryCollector.removeTelemetryListener(telemetryListener)
            telemetryCollector.removeSensorEventListener(sensorEventListener)
        }
        backgroundExecutor.shutdown()
        super.onDestroy()
    }
}