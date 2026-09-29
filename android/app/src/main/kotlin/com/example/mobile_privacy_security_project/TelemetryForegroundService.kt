package com.example.mobile_privacy_security_project

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Android Foreground Service for continuous 24/7 background privacy/security monitoring.
 * 
 * Capabilities:
 * - Stays alive continuously even when the app is minimized or closed.
 * - Listens in real-time to AndroidTelemetryCollector sensor events (Camera, Microphone, Photos, Location).
 * - Immediately displays high-priority Heads-Up notifications on sensor access.
 * - Speaks voice alerts aloud via on-device TextToSpeech (TTS) when another app opens camera, mic, photos, or location.
 * - Handles onTaskRemoved and START_STICKY to guarantee non-stop background surveillance protection.
 */
class TelemetryForegroundService : Service(), TextToSpeech.OnInitListener {

    companion object {
        private const val TAG = "TelemetryForegroundService"
        const val CHANNEL_ID = "privacy_monitor_channel"
        const val ALERT_CHANNEL_ID = "privacy_sensor_alerts"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START_TELEMETRY"
        const val ACTION_STOP = "ACTION_STOP_TELEMETRY"

        enum class ServiceState {
            STOPPED,
            RUNNING,
            TIMEOUT,
            START_FAILED
        }

        @Volatile
        var serviceState: ServiceState = ServiceState.STOPPED
            private set

        @Volatile
        var lastErrorDiagnostic: String? = null
            private set

        @Volatile
        var stopReason: String = "NONE"
            private set

        @Volatile
        var serviceStartTimeMs: Long = 0L
            private set

        @Volatile
        var lastTimeoutTimestampMs: Long = 0L
            private set

        @Volatile
        var collectionGapStartMs: Long = 0L
            private set

        @Volatile
        var collectionGapEndMs: Long = 0L
            private set

        val isServiceRunning: Boolean
            get() = serviceState == ServiceState.RUNNING

        fun getServiceHealth(): Map<String, Any?> {
            return mapOf(
                "state" to serviceState.name,
                "isRunning" to (serviceState == ServiceState.RUNNING),
                "lastError" to lastErrorDiagnostic,
                "stopReason" to stopReason,
                "serviceStartTimeMs" to serviceStartTimeMs,
                "lastTimeoutTimestampMs" to lastTimeoutTimestampMs,
                "collectionGapStartMs" to collectionGapStartMs,
                "collectionGapEndMs" to collectionGapEndMs,
                "foregroundServiceType" to "dataSync",
                "maxDurationHours" to 6
            )
        }
    }

    private lateinit var telemetryCollector: AndroidTelemetryCollector
    private var scheduler: ScheduledExecutorService? = null
    private val pollIntervalSeconds = 30L

    // Native Text-To-Speech engine
    private var tts: TextToSpeech? = null
    @Volatile
    private var isTtsReady = false

    // Deduplication cooldown tracking (app+sensor -> last alert time ms)
    private val lastAlertTimestamps = ConcurrentHashMap<String, Long>()
    private val activeAlertKeys = ConcurrentHashMap.newKeySet<String>()
    private val cooldownMs = 15_000L // 15 seconds cooldown per app+sensor

    private val sensorEventListener: (Map<String, Any?>) -> Unit = { event ->
        handleSensorEvent(event)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        telemetryCollector = AndroidTelemetryCollector.getInstance(applicationContext)
        telemetryCollector.addSensorEventListener(sensorEventListener)
        initTts()
        Log.i(TAG, "TelemetryForegroundService created & sensor listener registered")
    }

    private fun initTts() {
        try {
            tts = TextToSpeech(applicationContext, this)
        } catch (e: Exception) {
            Log.e(TAG, "TTS init exception: ${e.message}")
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts?.setLanguage(Locale.US)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                tts?.setLanguage(Locale.getDefault())
            }
            tts?.setSpeechRate(0.95f)
            tts?.setPitch(1.0f)
            isTtsReady = true
            Log.i(TAG, "Native TextToSpeech engine ready for real-time sensor voice alerts")
        } else {
            Log.w(TAG, "Native TextToSpeech initialization failed (status=$status)")
        }
    }

    /**
     * Speaks alert aloud to user even when app is minimized, locked, or closed.
     */
    fun speakAlert(text: String) {
        if (!isTtsReady || tts == null) {
            Log.w(TAG, "TTS not ready to speak: $text")
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "sensor_alert_${System.currentTimeMillis()}")
            } else {
                @Suppress("DEPRECATION")
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null)
            }
            Log.i(TAG, "SPOKEN_ALERT: \"$text\"")
        } catch (e: Exception) {
            Log.e(TAG, "Error speaking alert: ${e.message}")
        }
    }

    private fun handleSensorEvent(event: Map<String, Any?>) {
        try {
            val sensor = event["sensor"]?.toString()?.uppercase() ?: return
            val state = event["state"]?.toString()?.uppercase() ?: return
            val pkg = event["packageName"]?.toString()
            val rawApp = event["appName"]?.toString()
            val appName = if (!rawApp.isNullOrBlank()) rawApp else (pkg ?: "An app")
            val fileName = event["fileName"]?.toString()

            val key = "${sensor}_${pkg ?: "DEVICE"}"

            if (state == "STOPPED") {
                activeAlertKeys.remove(key)
                return
            }

            // Only notify & speak on active usage
            if (state != "STARTED" && state != "ACTIVE") return

            // Deduplication cooldown: don't spam if already alerted within cooldown window
            val now = System.currentTimeMillis()
            val lastTime = lastAlertTimestamps[key] ?: 0L
            if (activeAlertKeys.contains(key) || (now - lastTime < cooldownMs)) {
                return
            }

            activeAlertKeys.add(key)
            lastAlertTimestamps[key] = now

            // Clean up point-in-time accesses after 10s
            if (sensor == "PHOTOS" || sensor == "VIDEOS" || sensor == "FILES" || sensor == "LOCATION") {
                scheduler?.schedule({ activeAlertKeys.remove(key) }, 10, TimeUnit.SECONDS)
            }

            // Construct title, body, and spoken sentence in clear everyday language
            val (title, body, speech) = when (sensor) {
                "CAMERA" -> Triple(
                    "📷 Camera Access Alert",
                    "$appName is currently accessing your camera.",
                    "$appName is using your camera."
                )
                "MICROPHONE" -> Triple(
                    "🎙️ Microphone Access Alert",
                    "$appName is currently accessing your microphone.",
                    "$appName is using your microphone."
                )
                "PHOTOS" -> {
                    val fileDesc = if (!fileName.isNullOrBlank()) "\"$fileName\"" else "photos"
                    Triple(
                        "🖼️ Photo Access Alert",
                        "$appName accessed $fileDesc from your device storage.",
                        "$appName accessed your photos."
                    )
                }
                "VIDEOS" -> Triple(
                    "🎥 Video Access Alert",
                    "$appName accessed videos from your storage.",
                    "$appName accessed your videos."
                )
                "FILES" -> Triple(
                    "📁 File Storage Access Alert",
                    "$appName accessed sensitive files on your device.",
                    "$appName accessed your files."
                )
                "LOCATION" -> Triple(
                    "📍 Location Access Alert",
                    "$appName accessed your GPS location.",
                    "$appName accessed your location."
                )
                else -> Triple(
                    "🛡️ Privacy Sentinel Alert",
                    "$appName accessed $sensor.",
                    "$appName accessed $sensor."
                )
            }

            // 1. Dispatch High-Priority Heads-Up Notification (if enabled by the user)
            if (isNotificationsEnabled()) {
                dispatchSensorAlertNotification(title, body, key.hashCode())
            } else {
                Log.i(TAG, "Sensor alert notification suppressed by user setting (notifications disabled).")
            }

            // 2. Speak Aloud ONLY if voice alerts are turned ON by the user
            if (isVoiceAlertsEnabled()) {
                speakAlert(speech)
            } else {
                Log.i(TAG, "Voice alert muted by user setting.")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error handling background sensor event: ${e.message}")
        }
    }

    private fun isNotificationsEnabled(): Boolean {
        return try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.getBoolean("flutter.notifications_enabled", true)
        } catch (_: Exception) {
            true
        }
    }

    private fun isVoiceAlertsEnabled(): Boolean {
        return try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.getBoolean("flutter.voice_alerts_enabled", true)
        } catch (_: Exception) {
            true
        }
    }

    private fun dispatchSensorAlertNotification(title: String, body: String, notificationId: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            PendingIntent.getActivity(this, 0, launchIntent, flags)
        } else {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_ALARM)
            builder.setPriority(Notification.PRIORITY_MAX)
            builder.setVibrate(longArrayOf(0, 250, 150, 250))
        }

        nm.notify(notificationId, builder.build())
        Log.i(TAG, "DISPATCHED_BACKGROUND_ALERT: title=\"$title\" body=\"$body\"")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (action == ACTION_STOP) {
            serviceState = ServiceState.STOPPED
            stopReason = "USER_STOPPED"
            collectionGapStartMs = System.currentTimeMillis()
            stopMonitoring()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val started = startForegroundWithNotification()
        if (started) {
            serviceState = ServiceState.RUNNING
            stopReason = "NONE"
            serviceStartTimeMs = System.currentTimeMillis()
            if (collectionGapStartMs > 0) {
                collectionGapEndMs = System.currentTimeMillis()
            }
            lastErrorDiagnostic = null
            startMonitoring()
        } else {
            stopReason = "START_FAILED"
            return START_NOT_STICKY
        }

        // START_STICKY ensures Android automatically restarts this service if killed by OS
        return START_STICKY
    }

    private fun startForegroundWithNotification(): Boolean {
        try {
            val notification = createNotification()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            return true
        } catch (e: Exception) {
            serviceState = ServiceState.START_FAILED
            lastErrorDiagnostic = "Foreground service start rejected: ${e.javaClass.simpleName}${if (e.message != null) ": " + e.message else ""}"
            stopMonitoring()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return false
        }
    }

    private fun createNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            PendingIntent.getActivity(this, 0, launchIntent, flags)
        } else {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Privacy Sentinel AI • Active Protection")
            .setContentText("24/7 background privacy, camera & microphone monitoring active")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun startMonitoring() {
        if (scheduler == null || scheduler?.isShutdown == true) {
            scheduler = Executors.newSingleThreadScheduledExecutor()
        }
        scheduler?.scheduleWithFixedDelay(
            {
                if (serviceState == ServiceState.RUNNING) {
                    try {
                        telemetryCollector.collectTelemetry(forceRefresh = false)
                    } catch (e: Exception) {
                        lastErrorDiagnostic = "Background collection warning: ${e.javaClass.simpleName}"
                    }
                }
            },
            0L,
            pollIntervalSeconds,
            TimeUnit.SECONDS
        )
    }

    private fun stopMonitoring() {
        if (serviceState == ServiceState.RUNNING) {
            serviceState = ServiceState.STOPPED
        }
        try {
            scheduler?.shutdownNow()
            scheduler?.awaitTermination(1, TimeUnit.SECONDS)
        } catch (_: Exception) {
        } finally {
            scheduler = null
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.i(TAG, "onTaskRemoved: App swiped away / closed by user. Keeping background protection active.")
        // Ensure service remains running or relaunches
        val restartIntent = Intent(applicationContext, TelemetryForegroundService::class.java).apply {
            action = ACTION_START
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(restartIntent)
            } else {
                startService(restartIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restart onTaskRemoved: ${e.message}")
        }
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        serviceState = ServiceState.TIMEOUT
        stopReason = "TIMEOUT"
        val now = System.currentTimeMillis()
        lastTimeoutTimestampMs = now
        collectionGapStartMs = now
        lastErrorDiagnostic = "dataSync execution limit reached (Android 15+ 6h limit)"
        handleTimeout(startId)
    }

    fun handleTimeout(startId: Int = -1) {
        stopMonitoring()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        if (startId != -1) {
            stopSelf(startId)
        } else {
            stopSelf()
        }
    }

    override fun onDestroy() {
        if (serviceState == ServiceState.RUNNING) {
            serviceState = ServiceState.STOPPED
        }
        telemetryCollector.removeSensorEventListener(sensorEventListener)
        stopMonitoring()
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        isTtsReady = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
        Log.i(TAG, "TelemetryForegroundService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

            // 1. Monitor Channel (Ongoing Service)
            val monitorChannel = NotificationChannel(
                CHANNEL_ID,
                "Privacy Sentinel Monitor",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "24/7 background privacy and security monitoring"
                setShowBadge(false)
            }
            manager.createNotificationChannel(monitorChannel)

            // 2. High-Priority Alert Channel (Camera, Mic, Photo alerts)
            val alertChannel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "Privacy Sentinel Sensor Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Real-time alerts when applications access camera, microphone, photos, or files"
                enableVibration(true)
                setShowBadge(true)
            }
            manager.createNotificationChannel(alertChannel)
        }
    }
}