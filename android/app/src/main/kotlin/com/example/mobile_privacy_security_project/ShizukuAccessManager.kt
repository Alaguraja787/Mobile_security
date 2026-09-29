package com.example.mobile_privacy_security_project

import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import org.json.JSONObject
import rikka.shizuku.Shizuku
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Lifecycle and Coordination Manager for Shizuku-based Precise App Attribution.
 * 
 * Strict Responsibilities:
 * 1. Safely observe Shizuku binder lifecycle (received, dead).
 * 2. Manage user permission requests (never auto-request without user interaction).
 * 3. Bind and unbind PreciseSensorAttributionUserService in isolated process.
 * 4. Resolve verified package names to genuine application labels via PackageManager.
 * 5. Emit verified APP_LEVEL SensorAccessEvent maps to the sensor monitoring pipeline.
 * 6. Never crash if Shizuku is stopped, uninstalled, or permissions are revoked.
 * 7. Persist user's Precise Mode preference independently of transient binder state.
 */
class ShizukuAccessManager private constructor(
    private val context: Context
) {

    companion object {
        private const val TAG = "ShizukuAccessManager"
        const val SHIZUKU_PERMISSION_REQUEST_CODE = 102
        private const val PREFS_NAME = "privacy_sentinel_prefs"
        private const val PREF_KEY_PRECISE_MODE = "shizuku_precise_mode_enabled"

        @Volatile
        private var INSTANCE: ShizukuAccessManager? = null

        fun getInstance(context: Context): ShizukuAccessManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: ShizukuAccessManager(context.applicationContext).also { INSTANCE = it }
            }
        }
    }

    enum class ShizukuState {
        OFF,
        AVAILABLE,
        NEEDS_SHIZUKU,
        NEEDS_PERMISSION,
        ACTIVE,
        TEMPORARILY_UNAVAILABLE,
        ERROR
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val eventListeners = CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()
    private val statusListeners = CopyOnWriteArrayList<(ShizukuState) -> Unit>()

    private val isServiceBound = AtomicBoolean(false)
    private val isServiceBinding = AtomicBoolean(false)
    private val isWatchingAppOps = AtomicBoolean(false)
    private var userServiceBinder: IPreciseSensorAttributionService? = null
    private var userServiceUid: Int = -1
    private var userServiceServerVersion: Int = -1
    private val userActionAuditLog = CopyOnWriteArrayList<Map<String, Any?>>()

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        val version = try { Shizuku.getVersion() } catch (_: Throwable) { -1 }
        Log.i("SHIZUKU_BINDER_CONNECTED", "Shizuku binder connected. Shizuku service is running (serverVersion=$version).")
        Log.i("SHIZUKU_STATUS", "Shizuku binder received: Shizuku process is running.")
        mainHandler.post {
            handleBinderReceived()
        }
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Log.w(TAG, "Shizuku binder dead.")
        Log.w("SHIZUKU_UNAVAILABLE", "Shizuku binder dead: Shizuku service was killed or stopped.")
        Log.w("SHIZUKU_FALLBACK", "Shizuku binder died. Active fallback: CameraManager DEVICE_LEVEL.")
        mainHandler.post {
            handleBinderDead()
        }
    }

    private val requestPermissionResultListener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        if (requestCode == SHIZUKU_PERMISSION_REQUEST_CODE) {
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            if (granted) {
                Log.i("SHIZUKU_PERMISSION_GRANTED", "Shizuku permission request GRANTED (requestCode=$requestCode).")
                if (isPreciseModeEnabled()) {
                    bindUserService()
                }
            } else {
                Log.w("SHIZUKU_PERMISSION_DENIED", "Shizuku permission request DENIED (requestCode=$requestCode, grantResult=$grantResult).")
            }
            Log.i("SHIZUKU_PERMISSION", "onRequestPermissionResult: requestCode=$requestCode, granted=$granted")
            mainHandler.post {
                notifyStatusChanged()
            }
        }
    }

    private val wasBinderDead = AtomicBoolean(false)

    fun isDeviceScreenLocked(): Boolean {
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val isLocked = km?.isKeyguardLocked ?: false
        val isInteractive = pm?.isInteractive ?: true
        return isLocked || !isInteractive
    }

    private val serviceListener = object : ISensorAttributionListener.Stub() {
        override fun onSensorEvent(eventJson: String?) {
            if (eventJson.isNullOrBlank()) return
            try {
                val json = JSONObject(eventJson)
                val sensor = json.optString("sensor")
                val state = json.optString("state")
                val uid = json.optInt("uid", -1)
                var packageName = if (json.isNull("packageName")) null else json.optString("packageName")
                val timestamp = json.optString("timestamp")
                val source = json.optString("source", "SHIZUKU_APPOPS")
                val confidence = json.optString("confidence", "VERIFIED")
                val attributionScope = json.optString("attributionScope", "APP_LEVEL")
                val availability = json.optString("availability", "FULL")

                Log.i("SHIZUKU_APPOPS_EVENT", "UserService onSensorEvent: sensor=$sensor state=$state uid=$uid pkg=$packageName")

                // If package name is not provided or empty, resolve via local PackageManager using UID
                if (packageName.isNullOrBlank() && uid > 0) {
                    try {
                        val pkgs = context.packageManager.getPackagesForUid(uid)
                        if (!pkgs.isNullOrEmpty()) {
                            packageName = pkgs[0]
                            Log.i("SHIZUKU_PACKAGE_RESOLVED", "UID $uid resolved to package '$packageName' via Context PackageManager")
                        }
                    } catch (_: Exception) {}
                }

                if (packageName.isNullOrBlank()) {
                    Log.w("SHIZUKU_FALLBACK", "AppOps event for sensor=$sensor has unresolvable package (UID $uid). Falling back to DEVICE_LEVEL.")
                }

                val appName = resolvePackageNameToAppName(packageName)

                val eventId = "SHIZUKU_${sensor}_${state}_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}"

                val isLocked = isDeviceScreenLocked()

                val fileName = if (json.isNull("fileName")) null else json.optString("fileName")
                val mimeType = if (json.isNull("mimeType")) null else json.optString("mimeType")
                val humanExplanation = if (json.isNull("humanExplanation")) null else json.optString("humanExplanation")

                val eventMap = mutableMapOf<String, Any?>(
                    "type" to "sensor_access",
                    "sensor" to sensor,
                    "state" to state,
                    "packageName" to packageName,
                    "appName" to appName,
                    "timestamp" to timestamp,
                    "source" to source,
                    "confidence" to confidence,
                    "attributionScope" to attributionScope,
                    "availability" to availability,
                    "reason" to "Verified via Shizuku UserService AppOps active callback for UID $uid ($packageName).",
                    "eventId" to eventId,
                    "isScreenLocked" to isLocked
                )
                if (!fileName.isNullOrBlank()) {
                    eventMap["fileName"] = fileName
                }
                if (!mimeType.isNullOrBlank()) {
                    eventMap["mimeType"] = mimeType
                }
                if (!humanExplanation.isNullOrBlank()) {
                    eventMap["humanExplanation"] = humanExplanation
                }

                Log.i(TAG, "PRECISE_EVENT_RECEIVED: sensor=$sensor state=$state pkg=$packageName app=$appName")

                mainHandler.post {
                    for (listener in eventListeners) {
                        try {
                            listener(eventMap)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error dispatching precise event to listener: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing precise sensor event: ${e.message}")
            }
        }
    }

    private val userServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            isServiceBinding.set(false)
            Log.i(TAG, "PreciseSensorAttributionUserService connected: $name")
            Log.i("SHIZUKU_USERSERVICE_CONNECTED", "UserService connected: $name")
            isServiceBound.set(true)
            try {
                val attributionService = IPreciseSensorAttributionService.Stub.asInterface(service)
                userServiceBinder = attributionService

                // Requirement 5: Perform health/status PING handshake
                val pingResult = attributionService.ping()
                Log.i("SHIZUKU_USERSERVICE_PING_OK", "UserService ping response: $pingResult")
                try {
                    val json = JSONObject(pingResult)
                    userServiceUid = json.optInt("serviceUid", -1)
                    val rawServerVersion = json.optInt("shizukuServerVersion", -1)
                    userServiceServerVersion = if (rawServerVersion > 0) rawServerVersion else {
                        try { Shizuku.getVersion() } catch (_: Throwable) { -1 }
                    }
                    Log.i("SHIZUKU_USERSERVICE_PING_OK", "Handshake verified: connected=true, serviceUid=$userServiceUid, shizukuServerVersion=$userServiceServerVersion")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse ping JSON: ${e.message}")
                }

                // Register listener and start watching AppOps (Phase A & I)
                Log.i("SHIZUKU_APPOPS_REGISTER_START", "Registering listener and starting AppOps watcher...")
                attributionService.registerListener(serviceListener)
                attributionService.startWatching()
                val watching = attributionService.isWatching()
                isWatchingAppOps.set(watching)
                if (watching) {
                    Log.i("SHIZUKU_APPOPS_REGISTERED", "AppOps active watcher registered and watching (ops: CAMERA, RECORD_AUDIO)")
                } else {
                    Log.w("SHIZUKU_APPOPS_UNAVAILABLE", "AppOps watcher returned isWatching=false")
                }
            } catch (e: Exception) {
                Log.e("SHIZUKU_USERSERVICE_PING_FAILED", "UserService ping/setup failed: ${e.message}", e)
                isWatchingAppOps.set(false)
            }
            mainHandler.post {
                notifyStatusChanged()
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            isServiceBinding.set(false)
            Log.w(TAG, "PreciseSensorAttributionUserService disconnected: $name")
            Log.w("SHIZUKU_USERSERVICE_DISCONNECTED", "UserService disconnected: $name")
            Log.w("SHIZUKU_FALLBACK", "UserService disconnected ($name). Falling back to CameraManager DEVICE_LEVEL.")
            isServiceBound.set(false)
            isWatchingAppOps.set(false)
            userServiceBinder = null
            userServiceUid = -1
            userServiceServerVersion = -1
            mainHandler.post {
                notifyStatusChanged()
            }
        }
    }

    init {
        try {
            Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
            Shizuku.addBinderDeadListener(binderDeadListener)
            Shizuku.addRequestPermissionResultListener(requestPermissionResultListener)
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing Shizuku listeners: ${e.message}")
        }

        if (isPreciseModeEnabled() && isShizukuAvailable() && hasPermission()) {
            bindUserService()
        }
    }

    fun addEventListener(listener: (Map<String, Any?>) -> Unit) {
        eventListeners.add(listener)
    }

    fun removeEventListener(listener: (Map<String, Any?>) -> Unit) {
        eventListeners.remove(listener)
    }

    fun addStatusListener(listener: (ShizukuState) -> Unit) {
        statusListeners.add(listener)
        listener(getShizukuState())
    }

    fun removeStatusListener(listener: (ShizukuState) -> Unit) {
        statusListeners.remove(listener)
    }

    private fun notifyStatusChanged() {
        val state = getShizukuState()
        val installed = isShizukuInstalled()
        val running = isShizukuAvailable()
        val permitted = if (running) hasPermission() else false
        val bound = isServiceBound.get()
        val enabled = isPreciseModeEnabled()

        Log.i("SHIZUKU_STATUS", "State: ${state.name} | Installed: $installed | Running: $running | Permitted: $permitted | Bound: $bound | ModeEnabled: $enabled")

        if (!running) {
            Log.w("SHIZUKU_UNAVAILABLE", "Shizuku service is not running on device. Fallback to CameraManager DEVICE_LEVEL.")
        } else if (!permitted) {
            Log.i("SHIZUKU_PERMISSION_REQUIRED", "Shizuku running but authorization not yet granted to Privacy Sentinel.")
        } else {
            Log.i("SHIZUKU_PERMISSION_GRANTED", "Shizuku running and authorization granted.")
        }

        if (state != ShizukuState.ACTIVE) {
            Log.i("SHIZUKU_FALLBACK", "Precise attribution inactive (state=${state.name}). Fallback: CameraManager DEVICE_LEVEL.")
        }

        for (listener in statusListeners) {
            try {
                listener(state)
            } catch (_: Exception) {}
        }
    }

    fun isShizukuInstalled(): Boolean {
        return try {
            context.packageManager.getPackageInfo("moe.shizuku.privileged.api", 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun isShizukuAvailable(): Boolean {
        val available = try {
            Shizuku.pingBinder()
        } catch (_: Exception) {
            false
        }
        if (!available) {
            Log.i("SHIZUKU_UNAVAILABLE", "isShizukuAvailable: Shizuku binder is not available/running")
        }
        return available
    }

    fun hasPermission(): Boolean {
        if (!isShizukuAvailable()) {
            Log.i("SHIZUKU_UNAVAILABLE", "hasPermission: Shizuku is not running/available.")
            return false
        }
        val granted = try {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            Log.w(TAG, "checkSelfPermission exception: ${e.message}")
            false
        }
        if (granted) {
            Log.i("SHIZUKU_PERMISSION_GRANTED", "checkSelfPermission: GRANTED")
        } else {
            Log.i("SHIZUKU_PERMISSION_REQUIRED", "checkSelfPermission: PERMISSION_REQUIRED (not granted)")
        }
        return granted
    }

    fun isPreciseModeEnabled(): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(PREF_KEY_PRECISE_MODE, false)
    }

    fun setPreciseModeEnabled(enabled: Boolean) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(PREF_KEY_PRECISE_MODE, enabled).apply()
        Log.i(TAG, "setPreciseModeEnabled: $enabled")
        Log.i("SHIZUKU_STATUS", "setPreciseModeEnabled: $enabled")

        if (enabled) {
            if (isShizukuAvailable() && hasPermission()) {
                bindUserService()
            }
        } else {
            unbindUserService()
        }
        notifyStatusChanged()
    }

    fun requestPermission(): Boolean {
        if (!isShizukuAvailable()) {
            Log.w("SHIZUKU_UNAVAILABLE", "requestPermission aborted: Shizuku binder is not available/running.")
            return false
        }
        return try {
            if (hasPermission()) {
                Log.i("SHIZUKU_PERMISSION_GRANTED", "requestPermission called, but Shizuku permission is already GRANTED.")
                if (isPreciseModeEnabled()) {
                    bindUserService()
                }
                return true
            }
            Log.i("SHIZUKU_PERMISSION_REQUIRED", "requestPermission: dispatching Shizuku.requestPermission (requestCode=$SHIZUKU_PERMISSION_REQUEST_CODE)")
            Shizuku.requestPermission(SHIZUKU_PERMISSION_REQUEST_CODE)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request Shizuku permission: ${e.message}")
            Log.e("SHIZUKU_UNAVAILABLE", "Failed to request Shizuku permission: ${e.message}")
            false
        }
    }

    @Synchronized
    private fun bindUserService() {
        if ((isServiceBound.get() && userServiceBinder != null) || isServiceBinding.get()) {
            Log.i(TAG, "bindUserService called but already bound or binding in progress.")
            return
        }

        if (!isShizukuAvailable()) {
            Log.w("SHIZUKU_USERSERVICE_BIND_FAILED", "bindUserService aborted: Shizuku binder is not available/running.")
            return
        }

        if (!hasPermission()) {
            Log.w("SHIZUKU_USERSERVICE_BIND_FAILED", "bindUserService aborted: Shizuku permission has not been granted.")
            return
        }

        try {
            val componentName = ComponentName(context.packageName, PreciseSensorAttributionUserService::class.java.name)
            val versionCode = try {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                    context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode.toInt()
                } else {
                    @Suppress("DEPRECATION")
                    context.packageManager.getPackageInfo(context.packageName, 0).versionCode
                }
            } catch (_: Exception) {
                1
            }

            val isDebuggable = (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

            val args = Shizuku.UserServiceArgs(componentName)
                .processNameSuffix("precise_sensor_service")
                .debuggable(isDebuggable)
                .version(versionCode)

            Log.i("SHIZUKU_USERSERVICE_BIND_START", "Binding UserService: $componentName (version=$versionCode, debuggable=$isDebuggable)")
            isServiceBinding.set(true)
            Shizuku.bindUserService(args, userServiceConnection)
        } catch (e: Exception) {
            isServiceBinding.set(false)
            Log.e("SHIZUKU_USERSERVICE_BIND_FAILED", "bindUserService failed: ${e.message}", e)
            Log.e("SHIZUKU_FALLBACK", "bindUserService failed (${e.message}). Falling back to CameraManager DEVICE_LEVEL.")
            isServiceBound.set(false)
            userServiceBinder = null
            notifyStatusChanged()
        }
    }

    @Synchronized
    private fun unbindUserService() {
        isServiceBinding.set(false)
        if (!isServiceBound.get() && userServiceBinder == null) return

        try {
            val componentName = ComponentName(context.packageName, PreciseSensorAttributionUserService::class.java.name)
            val args = Shizuku.UserServiceArgs(componentName)
                .processNameSuffix("precise_sensor_service")
            Shizuku.unbindUserService(args, userServiceConnection, true)
            Log.i(TAG, "unbindUserService completed")
            Log.i("SHIZUKU_USERSERVICE_DISCONNECTED", "unbindUserService completed: service disconnected.")
            Log.i("SHIZUKU_FALLBACK", "UserService unbound. Active fallback: CameraManager DEVICE_LEVEL.")
        } catch (e: Exception) {
            Log.e(TAG, "unbindUserService error: ${e.message}")
        } finally {
            isServiceBound.set(false)
            isWatchingAppOps.set(false)
            userServiceBinder = null
            userServiceUid = -1
            userServiceServerVersion = -1
        }
    }

    private fun handleBinderReceived() {
        wasBinderDead.set(false)
        if (isPreciseModeEnabled() && hasPermission()) {
            bindUserService()
        }
        notifyStatusChanged()
    }

    private fun handleBinderDead() {
        wasBinderDead.set(true)
        unbindUserService()
        notifyStatusChanged()
    }

    fun getShizukuState(): ShizukuState {
        val enabled = isPreciseModeEnabled()
        if (!enabled) return ShizukuState.OFF

        val available = isShizukuAvailable()
        if (!available) {
            return if (wasBinderDead.get()) ShizukuState.TEMPORARILY_UNAVAILABLE else ShizukuState.NEEDS_SHIZUKU
        }

        val permitted = hasPermission()
        if (!permitted) return ShizukuState.NEEDS_PERMISSION

        // If UserService is bound and AppOps watcher is actively watching,
        // precise mode evaluates to ACTIVE. If watching is false, returns AVAILABLE (fallback).
        if (!isServiceBound.get() || !isWatchingAppOps.get()) return ShizukuState.AVAILABLE
        return ShizukuState.ACTIVE
    }

    fun getStatusMap(): Map<String, Any?> {
        val state = getShizukuState()
        val installed = isShizukuInstalled()
        val available = isShizukuAvailable()
        val permitted = hasPermission()
        val enabled = isPreciseModeEnabled()
        val bound = isServiceBound.get()
        val watching = isWatchingAppOps.get()
        val isPreciseActive = (state == ShizukuState.ACTIVE)

        val lifecycleState = when {
            !available -> if (wasBinderDead.get()) "SHIZUKU_BINDER_DEAD" else "SHIZUKU_UNAVAILABLE"
            !permitted -> "SHIZUKU_AVAILABLE_NO_PERMISSION"
            else -> "SHIZUKU_PERMISSION_GRANTED"
        }

        val status = when {
            isPreciseActive -> "Precise Attribution Active"
            bound -> "UserService Connected"
            else -> "Standard Monitoring"
        }

        val summary = when {
            !enabled -> "Uses standard Android privacy monitoring."
            !available -> if (wasBinderDead.get()) "Elevated service temporarily unavailable. Falling back to device monitoring." else "Install and start Shizuku to enable precise app attribution."
            !permitted -> "Grant Privacy Sentinel access in Shizuku."
            isPreciseActive -> "Precise app attribution active via Shizuku AppOps."
            bound -> "Elevated UserService connected."
            else -> "Precise app attribution is ready."
        }

        Log.i("SHIZUKU_STATUS", "getStatusMap: state=${state.name}, installed=$installed, running=$available, permitted=$permitted, bound=$bound, watching=$watching, preciseActive=$isPreciseActive, uid=$userServiceUid, serverVer=$userServiceServerVersion")

        return mapOf(
            "state" to state.name,
            "lifecycleState" to lifecycleState,
            "status" to status,
            "isPreciseModeEnabled" to enabled,
            "isShizukuInstalled" to installed,
            "isShizukuAvailable" to available,
            "isShizukuRunning" to available,
            "hasPermission" to permitted,
            "isServiceBound" to bound,
            "isAppOpsWatching" to watching,
            "isPreciseModeActive" to isPreciseActive,
            "summary" to summary,
            "serviceUid" to userServiceUid,
            "shizukuServerVersion" to userServiceServerVersion
        )
    }

    fun blockSensorAccess(packageName: String, sensor: String): Map<String, Any?> {
        val appName = resolvePackageNameToAppName(packageName) ?: packageName
        Log.i("PHASE4_ACTION_CONFIRMED", "Executing confirmed block action: pkg=$packageName app=$appName sensor=$sensor")

        // Validation per Phase L
        if (packageName.isBlank() || packageName == "null") {
            Log.w("PHASE4_ACTION_FAILED", "Block validation failed: invalid package name")
            return mapOf("success" to false, "verified" to false, "error" to "Invalid package name")
        }

        // Verify package is currently installed
        try {
            context.packageManager.getPackageInfo(packageName, 0)
        } catch (_: Exception) {
            Log.w("PHASE4_ACTION_FAILED", "Block validation failed: package '$packageName' is not installed")
            return mapOf("success" to false, "verified" to false, "error" to "Package is not installed")
        }

        // Verify sensor
        val normSensor = sensor.uppercase()
        if (normSensor != "CAMERA" && normSensor != "MICROPHONE" && normSensor != "LOCATION") {
            Log.w("PHASE4_ACTION_FAILED", "Block validation failed: unsupported sensor '$sensor'")
            return mapOf("success" to false, "verified" to false, "error" to "Unsupported sensor")
        }

        val permission = when (normSensor) {
            "MICROPHONE" -> "android.permission.RECORD_AUDIO"
            "LOCATION" -> "android.permission.ACCESS_FINE_LOCATION"
            else -> "android.permission.CAMERA"
        }

        // Verify UserService is bound
        val service = userServiceBinder
        if (!isServiceBound.get() || service == null) {
            Log.w("PHASE4_ACTION_FAILED", "Block validation failed: Shizuku UserService is not connected")
            return mapOf("success" to false, "verified" to false, "error" to "UserService disconnected")
        }

        return try {
            val payload = JSONObject().apply {
                put("action", "BLOCK_$normSensor")
                put("packageName", packageName)
                put("sensor", normSensor)
            }.toString()

            val responseStr = service.executeAction(payload)
            val resp = JSONObject(responseStr)
            val success = resp.optBoolean("success", false)
            val verified = resp.optBoolean("verified", false)
            val permState = resp.optString("permissionState", "UNKNOWN")

            val auditEntry = mapOf(
                "action" to "BLOCK_$normSensor",
                "packageName" to packageName,
                "appName" to appName,
                "sensor" to normSensor,
                "userConfirmed" to true,
                "result" to if (success && verified) "SUCCESS" else "FAILED",
                "verified" to verified,
                "permissionState" to permState,
                "timestamp" to java.time.Instant.now().toString()
            )
            userActionAuditLog.add(auditEntry)

            if (success && verified) {
                Log.i("PHASE4_ACTION_SUCCESS", "Successfully blocked and verified $normSensor for $packageName ($appName)")
            } else {
                Log.e("PHASE4_ACTION_FAILED", "Failed to block or verify $normSensor for $packageName ($appName)")
            }

            auditEntry
        } catch (e: Exception) {
            Log.e("PHASE4_ACTION_FAILED", "Exception executing block action: ${e.message}", e)
            mapOf("success" to false, "verified" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    fun restoreSensorAccess(packageName: String, sensor: String): Map<String, Any?> {
        val appName = resolvePackageNameToAppName(packageName) ?: packageName
        Log.i("PHASE4_ACTION_CONFIRMED", "Executing confirmed restore action: pkg=$packageName app=$appName sensor=$sensor")

        val normSensor = sensor.uppercase()
        val permission = when (normSensor) {
            "MICROPHONE" -> "android.permission.RECORD_AUDIO"
            "LOCATION" -> "android.permission.ACCESS_FINE_LOCATION"
            else -> "android.permission.CAMERA"
        }

        val service = userServiceBinder
        if (!isServiceBound.get() || service == null) {
            return mapOf("success" to false, "verified" to false, "error" to "UserService disconnected")
        }

        return try {
            val payload = JSONObject().apply {
                put("action", "RESTORE_$normSensor")
                put("packageName", packageName)
                put("sensor", normSensor)
            }.toString()

            val responseStr = service.executeAction(payload)
            val resp = JSONObject(responseStr)
            val success = resp.optBoolean("success", false)
            val verified = resp.optBoolean("verified", false)
            val permState = resp.optString("permissionState", "UNKNOWN")

            val auditEntry = mapOf(
                "action" to "RESTORE_$normSensor",
                "packageName" to packageName,
                "appName" to appName,
                "sensor" to normSensor,
                "userConfirmed" to true,
                "result" to if (success && verified) "SUCCESS" else "FAILED",
                "verified" to verified,
                "permissionState" to permState,
                "timestamp" to java.time.Instant.now().toString()
            )
            userActionAuditLog.add(auditEntry)
            auditEntry
        } catch (e: Exception) {
            Log.e(TAG, "Exception restoring sensor access: ${e.message}", e)
            mapOf("success" to false, "verified" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    fun checkSensorPermission(packageName: String, sensor: String): Boolean {
        val service = userServiceBinder
        val normSensor = sensor.uppercase()
        val permission = when (normSensor) {
            "MICROPHONE" -> "android.permission.RECORD_AUDIO"
            "LOCATION" -> "android.permission.ACCESS_FINE_LOCATION"
            else -> "android.permission.CAMERA"
        }

        if (service != null && isServiceBound.get()) {
            return try {
                service.checkSensorPermission(packageName, permission)
            } catch (_: Exception) {
                false
            }
        }
        return try {
            context.packageManager.checkPermission(permission, packageName) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }

    fun getUserActionAuditLog(): List<Map<String, Any?>> {
        return java.util.Collections.unmodifiableList(ArrayList(userActionAuditLog))
    }

    private fun resolvePackageNameToAppName(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        return try {
            val pm = context.packageManager
            val ai = pm.getApplicationInfo(packageName, 0)
            val appLabel = pm.getApplicationLabel(ai).toString()
            Log.i("SHIZUKU_PACKAGE_RESOLVED", "Package '$packageName' resolved to application label '$appLabel'")
            appLabel
        } catch (_: Exception) {
            Log.i("SHIZUKU_PACKAGE_RESOLVED", "Package '$packageName' not found in PackageManager, using packageName as fallback label")
            packageName
        }
    }

    fun destroy() {
        try {
            Shizuku.removeBinderReceivedListener(binderReceivedListener)
            Shizuku.removeBinderDeadListener(binderDeadListener)
            Shizuku.removeRequestPermissionResultListener(requestPermissionResultListener)
            unbindUserService()
        } catch (_: Exception) {}
    }
}
