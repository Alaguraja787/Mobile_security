package com.example.mobile_privacy_security_project

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import java.util.Locale
import java.util.TimeZone

/**
 * Collects legitimate real-world device context telemetry from Android system services.
 * 
 * Frequency Tiers:
 * 1. STATIC: Hardware and OS specifications (cached permanently).
 * 2. EVENT-DRIVEN: Screen state (tracked via BroadcastReceiver for SCREEN_ON, SCREEN_OFF, USER_PRESENT).
 * 3. PERIODIC: Battery metrics, power save modes, device idle state, and uptime.
 */
class DeviceContextCollector(
    private val context: Context
) {

    // Health state
    @Volatile
    private var healthStatus: String = "VALID"
    @Volatile
    private var lastErrorMessage: String? = null
    @Volatile
    private var lastSuccessfulCollectionMs: Long = 0

    fun getHealth(): Map<String, Any?> {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager

        val status = when {
            healthStatus == "ERROR" -> "ERROR"
            healthStatus == "RESTRICTED" -> "RESTRICTED"
            pm == null && km == null -> "UNAVAILABLE"
            healthStatus == "UNAVAILABLE" -> "UNAVAILABLE"
            else -> healthStatus
        }

        return mapOf(
            "status" to status,
            "message" to (lastErrorMessage ?: if (status == "VALID") "Operating nominally (Battery / Power / Keyguard inspection active)" else "Device context inspection issue"),
            "sourceApi" to "PowerManager / KeyguardManager / BatteryManager",
            "lastSuccessTimestampMs" to lastSuccessfulCollectionMs
        )
    }

    val pseudonymousDeviceId: String by lazy {
        val prefs = context.getSharedPreferences("privacy_sentinel_prefs", Context.MODE_PRIVATE)
        var id = prefs.getString("pseudonymous_device_id", null)
        if (id.isNullOrEmpty()) {
            id = java.util.UUID.randomUUID().toString()
            prefs.edit().putString("pseudonymous_device_id", id).apply()
        }
        id
    }

    // Cache static hardware information permanently
    val staticHardwareInfo: Map<String, Any?> by lazy {
        mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "brand" to Build.BRAND,
            "device" to Build.DEVICE,
            "board" to Build.BOARD,
            "hardware" to Build.HARDWARE,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "pseudonymousDeviceId" to pseudonymousDeviceId
        )
    }

    @Volatile
    private var isScreenOnEvent: Boolean? = null

    @Volatile
    private var isScreenLockedEvent: Boolean? = null

    private var isScreenReceiverRegistered = false

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    isScreenOnEvent = true
                }
                Intent.ACTION_SCREEN_OFF -> {
                    isScreenOnEvent = false
                    isScreenLockedEvent = true
                }
                Intent.ACTION_USER_PRESENT -> {
                    isScreenLockedEvent = false
                }
            }
        }
    }

    init {
        registerScreenReceiver()
    }

    @Synchronized
    fun registerScreenReceiver() {
        if (isScreenReceiverRegistered) return
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            context.registerReceiver(screenStateReceiver, filter)
            isScreenReceiverRegistered = true
        } catch (e: Exception) {
            lastErrorMessage = "ScreenReceiver registration warning: ${e.message}"
            if (e is SecurityException) {
                healthStatus = "RESTRICTED"
            } else {
                healthStatus = "ERROR"
            }
        }
    }

    @Synchronized
    fun unregister() {
        if (!isScreenReceiverRegistered) return
        try {
            context.unregisterReceiver(screenStateReceiver)
            isScreenReceiverRegistered = false
        } catch (_: Exception) {
            // Safe cleanup
        }
    }

    fun collectDynamicState(): Map<String, Any?> {
        var collectionError: Exception? = null
        var isRestricted = false
        var isUnavailable = false

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager

        if (powerManager == null && keyguardManager == null) {
            isUnavailable = true
        }

        // Screen On: Live system service inspection or broadcast event state; null if neither is available
        val isScreenOn: Boolean? = try {
            powerManager?.isInteractive ?: isScreenOnEvent
        } catch (e: Exception) {
            collectionError = e
            if (e is SecurityException) isRestricted = true
            isScreenOnEvent
        }

        // Screen Locked: Live system service inspection or broadcast event state; null if neither is available
        val isScreenLocked: Boolean? = try {
            keyguardManager?.isKeyguardLocked ?: isScreenLockedEvent
        } catch (e: Exception) {
            collectionError = e
            if (e is SecurityException) isRestricted = true
            isScreenLockedEvent
        }

        // Device Secure: Live system service inspection; null if unavailable or error
        val isDeviceSecure: Boolean? = try {
            keyguardManager?.isDeviceSecure
        } catch (e: Exception) {
            collectionError = e
            if (e is SecurityException) isRestricted = true
            null
        }

        val batteryIntent: Intent? = try {
            context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
        } catch (e: Exception) {
            collectionError = e
            if (e is SecurityException) isRestricted = true
            null
        }

        val level = if (batteryIntent != null && batteryIntent.hasExtra(BatteryManager.EXTRA_LEVEL)) {
            batteryIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        } else {
            -1
        }
        val scale = if (batteryIntent != null && batteryIntent.hasExtra(BatteryManager.EXTRA_SCALE)) {
            batteryIntent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        } else {
            -1
        }
        val batteryPercent: Int? = if (level >= 0 && scale > 0) {
            (level * 100) / scale
        } else {
            null
        }

        val rawStatus = if (batteryIntent != null && batteryIntent.hasExtra(BatteryManager.EXTRA_STATUS)) {
            batteryIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        } else {
            -1
        }
        val isCharging: Boolean? = if (rawStatus != -1) {
            rawStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
                    rawStatus == BatteryManager.BATTERY_STATUS_FULL
        } else {
            null
        }

        val batteryStatus = when (rawStatus) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "CHARGING"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "DISCHARGING"
            BatteryManager.BATTERY_STATUS_FULL -> "FULL"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "NOT_CHARGING"
            else -> "UNKNOWN"
        }

        val rawPlugged = if (batteryIntent != null && batteryIntent.hasExtra(BatteryManager.EXTRA_PLUGGED)) {
            batteryIntent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        } else {
            -1
        }
        val batteryPlugged = when (rawPlugged) {
            BatteryManager.BATTERY_PLUGGED_AC -> "AC"
            BatteryManager.BATTERY_PLUGGED_USB -> "USB"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "WIRELESS"
            0 -> "UNPLUGGED"
            else -> "UNKNOWN"
        }

        val rawHealth = if (batteryIntent != null && batteryIntent.hasExtra(BatteryManager.EXTRA_HEALTH)) {
            batteryIntent.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)
        } else {
            -1
        }
        val batteryHealth = when (rawHealth) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "GOOD"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "OVERHEAT"
            BatteryManager.BATTERY_HEALTH_DEAD -> "DEAD"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "OVER_VOLTAGE"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "UNSPECIFIED_FAILURE"
            BatteryManager.BATTERY_HEALTH_COLD -> "COLD"
            else -> "UNKNOWN"
        }

        // Temperature: Real temperature in tenths of a degree Celsius; null if not available
        val batteryTemperature: Double? = if (batteryIntent != null && batteryIntent.hasExtra(BatteryManager.EXTRA_TEMPERATURE)) {
            val rawTemp = batteryIntent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            if (rawTemp != Int.MIN_VALUE) rawTemp / 10.0 else null
        } else {
            null
        }

        // Voltage: in mV; null if not available
        val batteryVoltage: Int? = if (batteryIntent != null && batteryIntent.hasExtra(BatteryManager.EXTRA_VOLTAGE)) {
            val rawVolt = batteryIntent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, Int.MIN_VALUE)
            if (rawVolt != Int.MIN_VALUE) rawVolt else null
        } else {
            null
        }

        val powerSaveMode: Boolean? = try {
            powerManager?.isPowerSaveMode
        } catch (e: Exception) {
            collectionError = e
            if (e is SecurityException) isRestricted = true
            null
        }

        val isDeviceIdleMode: Boolean? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                powerManager?.isDeviceIdleMode
            } catch (e: Exception) {
                collectionError = e
                if (e is SecurityException) isRestricted = true
                null
            }
        } else {
            null
        }

        val uptimeMs = SystemClock.elapsedRealtime()
        val timezone = TimeZone.getDefault().id
        val locale = Locale.getDefault().toLanguageTag()

        if (collectionError != null) {
            healthStatus = if (isRestricted) "RESTRICTED" else "ERROR"
            lastErrorMessage = collectionError.message ?: "Failed to collect dynamic device state"
        } else if (isUnavailable) {
            healthStatus = "UNAVAILABLE"
            lastErrorMessage = "PowerManager and KeyguardManager unavailable on this device"
        } else {
            healthStatus = "VALID"
            lastErrorMessage = null
            lastSuccessfulCollectionMs = System.currentTimeMillis()
        }

        return mapOf(
            "screenOn" to isScreenOn,
            "screenLocked" to isScreenLocked,
            "isDeviceSecure" to isDeviceSecure,
            "batteryPercent" to batteryPercent,
            "isCharging" to isCharging,
            "batteryStatus" to batteryStatus,
            "batteryPlugged" to batteryPlugged,
            "batteryHealth" to batteryHealth,
            "batteryTemperatureCelsius" to batteryTemperature,
            "batteryVoltageMv" to batteryVoltage,
            "powerSaveMode" to powerSaveMode,
            "deviceIdleMode" to isDeviceIdleMode,
            "uptimeMs" to uptimeMs,
            "timezone" to timezone,
            "locale" to locale
        )
    }

    fun collect(): Map<String, Any?> {
        val dynamicState = collectDynamicState()
        return staticHardwareInfo + dynamicState
    }
}