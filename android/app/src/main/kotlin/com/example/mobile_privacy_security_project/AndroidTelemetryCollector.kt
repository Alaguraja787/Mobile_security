package com.example.mobile_privacy_security_project

import android.content.Context
import android.util.Log
import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * Central Native Aggregator, Repository, and Cache for Mobile Device Layer Telemetry.
 * 
 * Responsibilities:
 * 1. Thread-safe Singleton Repository accessible by MainActivity, TelemetryForegroundService, and background workers.
 * 2. Orchestrates tiered telemetry across Static, Event-Driven, Periodic, and Historical monitors.
 * 3. Enforces strict separation between Device-Level context and App-Level telemetry.
 * 4. Provides listener streaming for real-time telemetry updates.
 * 5. Generates structured platform verification diagnostics matrix.
 * 6. Executes heavy binder IPC queries off the Android UI/main thread.
 * 
 * NON-RESPONSIBILITIES:
 * - NO AI decisions
 * - NO risk scoring
 * - NO fabricated values
 */
class AndroidTelemetryCollector private constructor(
    private val context: Context
) {

    companion object {
        @Volatile
        private var INSTANCE: AndroidTelemetryCollector? = null

        fun getInstance(context: Context): AndroidTelemetryCollector {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: AndroidTelemetryCollector(context.applicationContext).also { INSTANCE = it }
            }
        }
    }

    val permissionMonitor = PermissionMonitor(context)
    val usageMonitor = AppUsageMonitor(context)
    val deviceContextCollector = DeviceContextCollector(context)
    val securityMonitor = DeviceSecurityMonitor(context)
    val networkMonitor = NetworkMonitor(context)
    val sensorMonitor = SensorPrivacyMonitor(context)
    val sensorWatchManager = SensorWatchManager(context)
    val shizukuAccessManager = ShizukuAccessManager.getInstance(context)
    val mediaFileAccessMonitor = MediaFileAccessMonitor(context)

    private val executor = Executors.newFixedThreadPool(4)
    private val telemetryListeners = CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()
    private val sensorEventListeners = CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()

    @Volatile
    private var latestConsolidatedTelemetry: Map<String, Any?>? = null
    private var lastFullCollectionTimestamp: Long = 0
    private val fullCollectionTtlMs = 5_000L // 5 seconds cache TTL for full consolidated snapshot

    init {
        // Invalidate usage and network caches when apps are installed/removed/updated
        permissionMonitor.setOnPackageChangeListener {
            usageMonitor.invalidateCache()
            networkMonitor.invalidateCache()
            latestConsolidatedTelemetry = null
        }
        sensorWatchManager.startWatching()

        sensorWatchManager.addEventListener { event ->
            notifySensorEventListeners(event)
        }

        shizukuAccessManager.addEventListener { event ->
            notifySensorEventListeners(event)
        }

        mediaFileAccessMonitor.startWatching()
        mediaFileAccessMonitor.addEventListener { event ->
            notifySensorEventListeners(event)
        }
    }

    private fun notifySensorEventListeners(event: Map<String, Any?>) {
        for (listener in sensorEventListeners) {
            try {
                listener(event)
            } catch (_: Exception) {}
        }
    }

    fun addSensorEventListener(listener: (Map<String, Any?>) -> Unit) {
        sensorEventListeners.add(listener)
    }

    fun removeSensorEventListener(listener: (Map<String, Any?>) -> Unit) {
        sensorEventListeners.remove(listener)
    }

    fun getSensorCapabilities(): Map<String, Any?> {
        return sensorWatchManager.getCapabilities()
    }

    fun reconcileSensorState(): Map<String, Any?> {
        return sensorWatchManager.reconcileSensorState()
    }

    fun getShizukuStatus(): Map<String, Any?> {
        return shizukuAccessManager.getStatusMap()
    }

    fun setPreciseModeEnabled(enabled: Boolean) {
        shizukuAccessManager.setPreciseModeEnabled(enabled)
    }

    fun requestShizukuPermission(): Boolean {
        return shizukuAccessManager.requestPermission()
    }

    fun blockSensorAccess(packageName: String, sensor: String): Map<String, Any?> {
        return shizukuAccessManager.blockSensorAccess(packageName, sensor)
    }

    fun restoreSensorAccess(packageName: String, sensor: String): Map<String, Any?> {
        return shizukuAccessManager.restoreSensorAccess(packageName, sensor)
    }

    fun checkSensorPermission(packageName: String, sensor: String): Boolean {
        return shizukuAccessManager.checkSensorPermission(packageName, sensor)
    }

    fun getUserActionAuditLog(): List<Map<String, Any?>> {
        return shizukuAccessManager.getUserActionAuditLog()
    }

    fun addTelemetryListener(listener: (Map<String, Any?>) -> Unit) {
        telemetryListeners.add(listener)
        latestConsolidatedTelemetry?.let { listener(it) }
    }

    fun removeTelemetryListener(listener: (Map<String, Any?>) -> Unit) {
        telemetryListeners.remove(listener)
    }

    private fun notifyListeners(telemetry: Map<String, Any?>) {
        for (listener in telemetryListeners) {
            try {
                listener(telemetry)
            } catch (_: Exception) {}
        }
    }

    /**
     * Executes telemetry collection asynchronously on background worker threads
     * and invokes the callback with the result.
     */
    fun collectTelemetryAsync(forceRefresh: Boolean = false, callback: (Map<String, Any?>) -> Unit) {
        val now = System.currentTimeMillis()
        if (forceRefresh) {
            latestConsolidatedTelemetry = null
            lastFullCollectionTimestamp = 0
            usageMonitor.invalidateCache()
            networkMonitor.invalidateCache()
        } else if (latestConsolidatedTelemetry != null && (now - lastFullCollectionTimestamp < fullCollectionTtlMs)) {
            callback(latestConsolidatedTelemetry!!)
            return
        }

        executor.execute {
            try {
                val result = collectTelemetryInternal(forceRefresh)
                latestConsolidatedTelemetry = result
                lastFullCollectionTimestamp = System.currentTimeMillis()
                notifyListeners(result)
                callback(result)
            } catch (e: Exception) {
                val errorMsg = e.message ?: "Unknown native collection error"
                val errorHealthItem = mapOf(
                    "status" to "ERROR",
                    "message" to errorMsg,
                    "sourceApi" to "AndroidTelemetryCollector",
                    "lastSuccessTimestampMs" to 0L
                )
                callback(
                    mapOf(
                        "error" to errorMsg,
                        "timestamp" to DateTimeFormatter.ISO_INSTANT.format(Instant.now()),
                        "apps" to emptyList<Map<String, Any?>>(),
                        "telemetryHealth" to mapOf(
                            "permissions" to errorHealthItem,
                            "usage" to errorHealthItem,
                            "network" to errorHealthItem,
                            "security" to errorHealthItem,
                            "sensors" to errorHealthItem,
                            "deviceContext" to errorHealthItem
                        )
                    )
                )
            }
        }
    }

    /**
     * Synchronous collection method (when called from background services or tests).
     */
    fun collectTelemetry(forceRefresh: Boolean = false): Map<String, Any?> {
        val now = System.currentTimeMillis()
        if (forceRefresh) {
            latestConsolidatedTelemetry = null
            lastFullCollectionTimestamp = 0
            usageMonitor.invalidateCache()
            networkMonitor.invalidateCache()
        } else if (latestConsolidatedTelemetry != null && (now - lastFullCollectionTimestamp < fullCollectionTtlMs)) {
            return latestConsolidatedTelemetry!!
        }

        val result = collectTelemetryInternal(forceRefresh)
        latestConsolidatedTelemetry = result
        lastFullCollectionTimestamp = now
        notifyListeners(result)
        persistNativeTelemetrySnapshotIfNeeded(result)
        return result
    }

    fun setCollectionSession(active: Boolean, sessionId: String?) {
        val prefs = context.getSharedPreferences("privacy_sentinel_prefs", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putBoolean("is_collection_active", active)
            if (active && sessionId != null) {
                putString("active_session_id", sessionId)
            } else if (!active) {
                remove("active_session_id")
            }
            apply()
        }
    }

    private fun persistNativeTelemetrySnapshotIfNeeded(telemetry: Map<String, Any?>) {
        val prefs = context.getSharedPreferences("privacy_sentinel_prefs", Context.MODE_PRIVATE)
        val isCollecting = prefs.getBoolean("is_collection_active", false)
        if (!isCollecting) return

        val sessionId = prefs.getString("active_session_id", "bg_session")
        val timestamp = telemetry["timestamp"] as? String ?: return
        @Suppress("UNCHECKED_CAST")
        val apps = telemetry["apps"] as? List<Map<String, Any?>> ?: return

        executor.execute {
            try {
                var targetDir = File(context.filesDir.parentFile, "app_flutter")
                if (!targetDir.exists()) {
                    targetDir.mkdirs()
                }
                if (!targetDir.exists()) {
                    targetDir = context.filesDir
                }
                val datasetFile = File(targetDir, "privacy_sentinel_dataset.jsonl")

                val deviceId = deviceContextCollector.pseudonymousDeviceId
                val androidVer = android.os.Build.VERSION.RELEASE
                val sdkInt = android.os.Build.VERSION.SDK_INT

                val sb = StringBuilder()
                for (app in apps) {
                    val pkg = app["packageName"] as? String ?: continue
                    val uid = (app["uid"] as? Number)?.toInt() ?: -1
                    val recordId = "${timestamp}_${pkg}_${uid}"

                    val jsonRecord = org.json.JSONObject().apply {
                        put("recordId", recordId)
                        put("sessionId", sessionId)
                        put("deviceIdHash", deviceId)
                        put("androidVersion", androidVer)
                        put("sdkInt", sdkInt)
                        put("timestamp", timestamp)
                        put("packageName", pkg)
                        put("collectorHealthStatus", "VALID")
                        put("rawTelemetry", org.json.JSONObject().apply {
                            put("app", org.json.JSONObject(app))
                            @Suppress("UNCHECKED_CAST")
                            put("deviceContext", org.json.JSONObject((telemetry["deviceContext"] as? Map<String, Any?>) ?: emptyMap<String, Any?>()))
                            @Suppress("UNCHECKED_CAST")
                            put("securityContext", org.json.JSONObject((telemetry["securityContext"] as? Map<String, Any?>) ?: emptyMap<String, Any?>()))
                            @Suppress("UNCHECKED_CAST")
                            put("network", org.json.JSONObject((telemetry["network"] as? Map<String, Any?>) ?: emptyMap<String, Any?>()))
                            @Suppress("UNCHECKED_CAST")
                            put("sensorTelemetry", org.json.JSONObject((telemetry["sensorTelemetry"] as? Map<String, Any?>) ?: emptyMap<String, Any?>()))
                            @Suppress("UNCHECKED_CAST")
                            put("usageSummary", org.json.JSONObject((telemetry["usageSummary"] as? Map<String, Any?>) ?: emptyMap<String, Any?>()))
                        })
                        put("featureVector", org.json.JSONObject())
                        put("label", org.json.JSONObject.NULL)
                    }
                    sb.append(jsonRecord.toString()).append("\n")
                }

                if (sb.isNotEmpty()) {
                    datasetFile.appendText(sb.toString())
                }
            } catch (_: Exception) {
                // Background file persistence error isolation
            }
        }
    }

    fun getLatestSnapshot(): Map<String, Any?>? = latestConsolidatedTelemetry

    private fun collectTelemetryInternal(forceRefresh: Boolean): Map<String, Any?> {
        // Collect from all specialized monitors
        val rawApps = permissionMonitor.getInstalledAppPermissions(forceRefresh)
        val usageData = usageMonitor.getUsageTelemetry(intervalHours = 24, forceRefresh = forceRefresh)
        val networkData = networkMonitor.getDeviceNetworkTelemetry()
        val contextData = deviceContextCollector.collect()
        val securityData = securityMonitor.collectSecurityState()
        val sensorData = sensorMonitor.getSensorTelemetry()

        // Index usage stats by package name
        val appsUsageList = (usageData["appsUsage"] as? List<*>)?.filterIsInstance<Map<String, Any?>>() ?: emptyList()
        val usageByPackage = appsUsageList.associateBy { it["packageName"] as? String ?: "" }
        val allPackagesLastUsed = (usageData["allPackagesLastUsed"] as? Map<*, *>)?.mapNotNull { (k, v) ->
            val p = k as? String
            val ts = (v as? Number)?.toLong()
            if (p != null && ts != null) p to ts else null
        }?.toMap() ?: emptyMap()
        val usageAvailabilityGeneral = usageData["availability"] as? String ?: "UNKNOWN"

        // Query real per-UID network statistics if usage stats access is granted
        val netResult = networkMonitor.queryAllUidNetworkStatsDetailed(intervalHours = 24, forceRefresh = forceRefresh)
        val uidNetworkStats = netResult.statsByUid
        val netQueryStatus = netResult.status

        // Enrich apps with strictly app-specific information (NO device-level flags inside app objects)
        val enrichedApps = rawApps.map { app ->
            val appMap = app.toMutableMap()
            val pkg = app["packageName"] as? String ?: ""
            val uid = app["uid"] as? Int ?: -1

            // Attach app-specific usage metrics
            val usage = usageByPackage[pkg]
            if (usage != null) {
                appMap["foregroundDurationMs"] = usage["foregroundDurationMs"]
                appMap["usageTodayMs"] = usage["usageTodayMs"] ?: usage["foregroundDurationMs"]
                appMap["foregroundTimeMs"] = usage["foregroundTimeMs"] ?: usage["foregroundDurationMs"]
                appMap["visibleTimeMs"] = usage["visibleTimeMs"]
                appMap["foregroundServiceTimeMs"] = usage["foregroundServiceTimeMs"]
                appMap["lastUsedTimestamp"] = usage["lastUsedTimestamp"] ?: usage["lastTimeUsedMs"]
                appMap["foregroundMinutes"] = usage["foregroundMinutes"]
                appMap["foregroundTransitionCount"] = usage["foregroundTransitionCount"]
                appMap["lastTimeUsedMs"] = usage["lastTimeUsedMs"]
                appMap["isCurrentlyForeground"] = usage["isCurrentlyForeground"]
                appMap["isRecentlyUsedDerived"] = usage["isRecentlyUsedDerived"]
                appMap["usageAvailability"] = usage["usageAvailability"] ?: "VALID"
                appMap["usageDataState"] = usage["usageDataState"] ?: "AVAILABLE"
            } else {
                val historicalLastUsed = allPackagesLastUsed[pkg] ?: 0L
                val lastTs = if (historicalLastUsed > 0L) historicalLastUsed else null
                when (usageAvailabilityGeneral) {
                    "AVAILABLE", "VALID" -> {
                        appMap["foregroundDurationMs"] = 0L
                        appMap["usageTodayMs"] = 0L
                        appMap["foregroundTimeMs"] = 0L
                        appMap["visibleTimeMs"] = null
                        appMap["foregroundServiceTimeMs"] = null
                        appMap["lastUsedTimestamp"] = lastTs
                        appMap["foregroundMinutes"] = 0.0
                        appMap["foregroundTransitionCount"] = 0
                        appMap["lastTimeUsedMs"] = lastTs
                        appMap["isCurrentlyForeground"] = false
                        appMap["isRecentlyUsedDerived"] = false
                        appMap["usageAvailability"] = "ZERO_REPORTED"
                        appMap["usageDataState"] = "AVAILABLE"
                    }
                    "ZERO_REPORTED" -> {
                        appMap["foregroundDurationMs"] = 0L
                        appMap["usageTodayMs"] = 0L
                        appMap["foregroundTimeMs"] = 0L
                        appMap["visibleTimeMs"] = null
                        appMap["foregroundServiceTimeMs"] = null
                        appMap["lastUsedTimestamp"] = lastTs
                        appMap["foregroundMinutes"] = 0.0
                        appMap["foregroundTransitionCount"] = 0
                        appMap["lastTimeUsedMs"] = lastTs
                        appMap["isCurrentlyForeground"] = false
                        appMap["isRecentlyUsedDerived"] = false
                        appMap["usageAvailability"] = "ZERO_REPORTED"
                        appMap["usageDataState"] = "AVAILABLE"
                    }
                    "PARTIAL" -> {
                        val statsAvail = usageData["statsAvailability"] as? String ?: "ERROR"
                        val eventsAvail = usageData["eventsAvailability"] as? String ?: "ERROR"
                        appMap["foregroundDurationMs"] = if (statsAvail == "AVAILABLE") 0L else null
                        appMap["usageTodayMs"] = if (statsAvail == "AVAILABLE") 0L else null
                        appMap["foregroundTimeMs"] = if (statsAvail == "AVAILABLE") 0L else null
                        appMap["visibleTimeMs"] = null
                        appMap["foregroundServiceTimeMs"] = null
                        appMap["lastUsedTimestamp"] = lastTs
                        appMap["foregroundMinutes"] = if (statsAvail == "AVAILABLE") 0.0 else null
                        appMap["foregroundTransitionCount"] = if (eventsAvail == "AVAILABLE") 0 else null
                        appMap["lastTimeUsedMs"] = lastTs
                        appMap["isCurrentlyForeground"] = if (eventsAvail == "AVAILABLE") false else null
                        appMap["isRecentlyUsedDerived"] = false
                        appMap["usageAvailability"] = "PARTIAL"
                        appMap["usageDataState"] = "PARTIAL"
                    }
                    "USAGE_DATA_UNAVAILABLE", "RESTRICTED" -> {
                        appMap["foregroundDurationMs"] = null
                        appMap["usageTodayMs"] = null
                        appMap["foregroundTimeMs"] = null
                        appMap["visibleTimeMs"] = null
                        appMap["foregroundServiceTimeMs"] = null
                        appMap["lastUsedTimestamp"] = null
                        appMap["foregroundMinutes"] = null
                        appMap["foregroundTransitionCount"] = null
                        appMap["lastTimeUsedMs"] = null
                        appMap["isCurrentlyForeground"] = null
                        appMap["isRecentlyUsedDerived"] = null
                        appMap["usageAvailability"] = "USAGE_DATA_UNAVAILABLE"
                        appMap["usageDataState"] = "USAGE_DATA_UNAVAILABLE"
                    }
                    "UNAVAILABLE" -> {
                        appMap["foregroundDurationMs"] = null
                        appMap["usageTodayMs"] = null
                        appMap["foregroundTimeMs"] = null
                        appMap["visibleTimeMs"] = null
                        appMap["foregroundServiceTimeMs"] = null
                        appMap["lastUsedTimestamp"] = null
                        appMap["foregroundMinutes"] = null
                        appMap["foregroundTransitionCount"] = null
                        appMap["lastTimeUsedMs"] = null
                        appMap["isCurrentlyForeground"] = null
                        appMap["isRecentlyUsedDerived"] = null
                        appMap["usageAvailability"] = "UNAVAILABLE"
                        appMap["usageDataState"] = "UNAVAILABLE"
                    }
                    else -> {
                        appMap["foregroundDurationMs"] = null
                        appMap["usageTodayMs"] = null
                        appMap["foregroundTimeMs"] = null
                        appMap["visibleTimeMs"] = null
                        appMap["foregroundServiceTimeMs"] = null
                        appMap["lastUsedTimestamp"] = null
                        appMap["foregroundMinutes"] = null
                        appMap["foregroundTransitionCount"] = null
                        appMap["lastTimeUsedMs"] = null
                        appMap["isCurrentlyForeground"] = null
                        appMap["isRecentlyUsedDerived"] = null
                        appMap["usageAvailability"] = "ERROR"
                        appMap["usageDataState"] = "ERROR"
                    }
                }
            }

            // Attach app-specific network metrics with explicit failure semantics
            if (uid > 0 && uidNetworkStats.containsKey(uid)) {
                val net = uidNetworkStats[uid]!!
                appMap["uploadBytes"] = net.txBytes
                appMap["downloadBytes"] = net.rxBytes
                appMap["networkUsageAvailability"] = if (net.txBytes == 0L && net.rxBytes == 0L) "ZERO_REPORTED" else "VALID"
                appMap["networkUsageSource"] = "NetworkStatsManager"
            } else if (uid > 0) {
                when (netQueryStatus) {
                    "VALID", "ZERO_REPORTED" -> {
                        appMap["uploadBytes"] = 0L
                        appMap["downloadBytes"] = 0L
                        appMap["networkUsageAvailability"] = "ZERO_REPORTED"
                        appMap["networkUsageSource"] = "NetworkStatsManager"
                    }
                    "RESTRICTED", "DENIED" -> {
                        appMap["uploadBytes"] = null
                        appMap["downloadBytes"] = null
                        appMap["networkUsageAvailability"] = netQueryStatus
                        appMap["networkUsageSource"] = "UNAVAILABLE_NO_PERMISSION"
                    }
                    "UNAVAILABLE" -> {
                        appMap["uploadBytes"] = null
                        appMap["downloadBytes"] = null
                        appMap["networkUsageAvailability"] = "UNAVAILABLE"
                        appMap["networkUsageSource"] = "SERVICE_UNAVAILABLE"
                    }
                    "ERROR" -> {
                        appMap["uploadBytes"] = null
                        appMap["downloadBytes"] = null
                        appMap["networkUsageAvailability"] = "ERROR"
                        appMap["networkUsageSource"] = "QUERY_ERROR"
                    }
                    else -> {
                        appMap["uploadBytes"] = null
                        appMap["downloadBytes"] = null
                        appMap["networkUsageAvailability"] = "RESTRICTED"
                        appMap["networkUsageSource"] = "UNAVAILABLE_NO_PERMISSION"
                    }
                }
            } else {
                appMap["uploadBytes"] = null
                appMap["downloadBytes"] = null
                appMap["networkUsageAvailability"] = "UNAVAILABLE"
                appMap["networkUsageSource"] = "INVALID_UID"
            }

            appMap
        }

        val timestamp = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
        val telemetryHealth = getTelemetryHealth()

        val diagnostics = generateDiagnostics(
            contextData = contextData,
            securityData = securityData,
            networkData = networkData,
            sensorData = sensorData,
            usageData = usageData,
            appsCount = rawApps.size,
            netQueryStatus = netQueryStatus
        )

        return mapOf(
            "timestamp" to timestamp,
            "deviceContext" to contextData,
            "deviceSecurity" to securityData,
            "network" to networkData,
            "sensorTelemetry" to sensorData,
            "usageSummary" to usageData,
            "apps" to enrichedApps,
            "telemetryHealth" to telemetryHealth,
            "diagnostics" to diagnostics
        )
    }

    fun getTelemetryHealth(): Map<String, Any?> {
        return mapOf(
            "permissions" to permissionMonitor.getHealth(),
            "usage" to usageMonitor.getHealth(),
            "network" to networkMonitor.getHealth(),
            "security" to securityMonitor.getHealth(),
            "sensors" to sensorMonitor.getHealth(),
            "deviceContext" to deviceContextCollector.getHealth(),
            "foregroundService" to TelemetryForegroundService.getServiceHealth()
        )
    }

    fun getInstalledApps(forceRefresh: Boolean = false): List<Map<String, Any?>> {
        return permissionMonitor.getInstalledAppPermissions(forceRefresh)
    }

    fun getUsageStats(forceRefresh: Boolean = false): Map<String, Any?> {
        return usageMonitor.getUsageTelemetry(intervalHours = 24, forceRefresh = forceRefresh)
    }

    fun getDeviceContext(): Map<String, Any?> {
        return deviceContextCollector.collect()
    }

    fun getDeviceSecurity(): Map<String, Any?> {
        return securityMonitor.collectSecurityState()
    }

    fun getNetworkTelemetry(): Map<String, Any?> {
        return networkMonitor.getDeviceNetworkTelemetry()
    }

    fun getSensorTelemetry(): Map<String, Any?> {
        return sensorMonitor.getSensorTelemetry()
    }

    fun isUsageAccessGranted(): Boolean {
        return usageMonitor.isUsageAccessGranted()
    }

    fun isOverlayPermissionGranted(): Boolean? {
        return securityMonitor.selfCanDrawOverlays()
    }

    fun isBatteryOptimizationIgnored(): Boolean? {
        return securityMonitor.selfIsIgnoringBatteryOptimizations()
    }

    fun getAppIcon(packageName: String): ByteArray? {
        return try {
            val pm = context.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val drawable = pm.getApplicationIcon(appInfo)
            val bitmap = if (drawable is android.graphics.drawable.BitmapDrawable && drawable.bitmap != null) {
                drawable.bitmap
            } else {
                val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 72
                val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 72
                val bmp = android.graphics.Bitmap.createBitmap(
                    width.coerceAtMost(144).coerceAtLeast(32),
                    height.coerceAtMost(144).coerceAtLeast(32),
                    android.graphics.Bitmap.Config.ARGB_8888
                )
                val canvas = android.graphics.Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }
            val stream = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
            val bytes = stream.toByteArray()
            Log.i("SHIZUKU_APP_ICON_RESOLVED", "Resolved real app icon for package '$packageName' (${bytes.size} bytes)")
            bytes
        } catch (e: Exception) {
            Log.w("SHIZUKU_APP_ICON_RESOLVED", "Could not resolve app icon for package '$packageName': ${e.message}")
            null
        }
    }

    fun checkSpeechRecognitionAvailability(): Map<String, Any?> {
        val isAvailable = android.speech.SpeechRecognizer.isRecognitionAvailable(context)
        val pm = context.packageManager
        val intent = android.content.Intent(android.speech.RecognitionService.SERVICE_INTERFACE)
        val resolveInfos = pm.queryIntentServices(intent, 0)
        val services = resolveInfos.map { it.serviceInfo?.packageName ?: "unknown" }
        return mapOf(
            "isAvailable" to isAvailable,
            "servicesCount" to services.size,
            "services" to services
        )
    }

    fun shutdown() {
        permissionMonitor.unregisterPackageReceiver()
        deviceContextCollector.unregister()
        networkMonitor.unregister()
        sensorMonitor.unregister()
        sensorWatchManager.stopWatching()
        executor.shutdown()
    }

    private fun generateDiagnostics(
        contextData: Map<String, Any?>,
        securityData: Map<String, Any?>,
        networkData: Map<String, Any?>,
        sensorData: Map<String, Any?>,
        usageData: Map<String, Any?>,
        appsCount: Int,
        netQueryStatus: String
    ): List<Map<String, Any?>> {
        val permHealth = permissionMonitor.getHealth()["status"] as? String ?: "UNKNOWN"
        val usageHealth = usageMonitor.getHealth()["status"] as? String ?: "UNKNOWN"
        val netHealth = networkMonitor.getHealth()["status"] as? String ?: "UNKNOWN"
        val secHealth = securityMonitor.getHealth()["status"] as? String ?: "UNKNOWN"
        val sensorHealth = sensorMonitor.getHealth()["status"] as? String ?: "UNKNOWN"
        val contextHealth = deviceContextCollector.getHealth()["status"] as? String ?: "UNKNOWN"

        val permAvailability = if (permHealth == "VALID") "AVAILABLE" else permHealth
        val usageAvailability = if (usageHealth == "VALID") {
            val avail = usageData["availability"] as? String
            if (avail == "VALID" || avail == "AVAILABLE") "AVAILABLE" else (avail ?: "AVAILABLE")
        } else {
            usageHealth
        }
        val netTotalsAvailability = if (netHealth == "VALID") (networkData["trafficStatsAvailability"] as? String ?: "AVAILABLE") else netHealth
        val appNetAvailability = if (netHealth == "VALID") {
            when (netQueryStatus) {
                "VALID", "ZERO_REPORTED" -> "AVAILABLE"
                "RESTRICTED", "DENIED" -> "RESTRICTED"
                "UNAVAILABLE" -> "UNAVAILABLE"
                "ERROR" -> "ERROR"
                else -> "RESTRICTED"
            }
        } else {
            netHealth
        }
        val contextAvailability = if (contextHealth == "VALID") "AVAILABLE" else contextHealth
        val sensorAvailability = if (sensorHealth == "VALID") {
            val sAvail = sensorData["sensorAvailability"] as? String
            if (sAvail == "VALID" || sAvail == "AVAILABLE") "AVAILABLE" else (sAvail ?: "AVAILABLE")
        } else {
            sensorHealth
        }
        val secAvailability = if (secHealth == "VALID") "AVAILABLE" else secHealth

        return listOf(
            mapOf(
                "field" to "installedPackages",
                "value" to "$appsCount packages",
                "sourceApi" to "PackageManager.getInstalledPackages",
                "scope" to "APP_INVENTORY",
                "collectionType" to "STATIC_CACHED",
                "availability" to permAvailability,
                "limitation" to "Filtered by QUERY_ALL_PACKAGES permission on Android 11+"
            ),
            mapOf(
                "field" to "dangerousPermissions",
                "value" to "Dynamic protectionLevel inspection",
                "sourceApi" to "PackageManager.getPermissionInfo",
                "scope" to "APP_METADATA",
                "collectionType" to "STATIC_CACHED",
                "availability" to permAvailability,
                "limitation" to "Only system-defined permission protection flags are inspected"
            ),
            mapOf(
                "field" to "appUsageStats",
                "value" to "${usageData["totalForegroundTransitions"]} transitions",
                "sourceApi" to "UsageStatsManager / UsageEvents",
                "scope" to "APP_USAGE",
                "collectionType" to "HISTORICAL_AND_EVENT",
                "availability" to usageAvailability,
                "limitation" to "Requires PACKAGE_USAGE_STATS special access; events subject to OEM background policies"
            ),
            mapOf(
                "field" to "deviceNetworkTotals",
                "value" to "TX: ${networkData["deviceTotalTxBytes"]} bytes, RX: ${networkData["deviceTotalRxBytes"]} bytes",
                "sourceApi" to "TrafficStats.getTotal*Bytes",
                "scope" to "DEVICE",
                "collectionType" to "PERIODIC_SNAPSHOT",
                "availability" to netTotalsAvailability,
                "limitation" to "Resets on device reboot"
            ),
            mapOf(
                "field" to "appNetworkUsage",
                "value" to if (usageData["usageAccessGranted"] == true) "Aggregated via NetworkStatsManager" else "UNAVAILABLE",
                "sourceApi" to "NetworkStatsManager.querySummary",
                "scope" to "APP",
                "collectionType" to "HISTORICAL_STATISTIC",
                "availability" to appNetAvailability,
                "limitation" to "Requires PACKAGE_USAGE_STATS; TrafficStats per-UID unsupported for third-party UIDs on Android 9+"
            ),
            mapOf(
                "field" to "screenState",
                "value" to "Interactive: ${contextData["screenOn"]}, Locked: ${contextData["screenLocked"]}",
                "sourceApi" to "PowerManager.isInteractive / KeyguardManager.isKeyguardLocked",
                "scope" to "DEVICE",
                "collectionType" to "EVENT_DRIVEN_AND_SNAPSHOT",
                "availability" to contextAvailability,
                "limitation" to "Real-time state via broadcast receiver & system service inspection"
            ),
            mapOf(
                "field" to "batteryContext",
                "value" to "${contextData["batteryPercent"]}% (${contextData["batteryStatus"]})",
                "sourceApi" to "ACTION_BATTERY_CHANGED BroadcastReceiver",
                "scope" to "DEVICE",
                "collectionType" to "PERIODIC_SNAPSHOT",
                "availability" to contextAvailability,
                "limitation" to "Sticky intent broadcast from Android BatteryManager"
            ),
            mapOf(
                "field" to "cameraAvailability",
                "value" to "Unavailable: ${sensorData["cameraUnavailable"]}",
                "sourceApi" to "CameraManager.AvailabilityCallback",
                "scope" to "DEVICE",
                "collectionType" to "EVENT_DRIVEN",
                "availability" to sensorAvailability,
                "limitation" to "Device-level hardware state only; Android does not attribute app package to 3rd-party apps"
            ),
            mapOf(
                "field" to "microphoneHardwareInUse",
                "value" to "${sensorData["microphoneHardwareInUse"]}",
                "sourceApi" to "AudioManager.registerAudioRecordingCallback / getActiveRecordingConfigurations",
                "scope" to "DEVICE",
                "collectionType" to "EVENT_DRIVEN_AND_SNAPSHOT",
                "availability" to sensorAvailability,
                "limitation" to "Device-level recording activity; unprivileged apps cannot attribute to specific 3rd-party packages"
            ),
            mapOf(
                "field" to "rootDetectionHeuristic",
                "value" to "${(securityData["rootDetection"] as? Map<*, *>)?.get("confidence")} confidence",
                "sourceApi" to "Multi-indicator filesystem & build tags inspection",
                "scope" to "DEVICE",
                "collectionType" to "DERIVED_SIGNAL",
                "availability" to secAvailability,
                "limitation" to "Heuristic only; advanced root cloaking (e.g. Magisk DenyList) cannot be deterministically detected"
            )
        )
    }
}