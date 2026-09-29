package com.example.mobile_privacy_security_project

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Process

/**
 * Collects application usage statistics and foreground transition telemetry
 * using Android's UsageStatsManager and UsageEvents.
 * 
 * Frequency Tiers:
 * - HISTORICAL: 24-hour interval query cached with 30-second TTL.
 * - EVENT-INFORMED: Foreground transitions and current foreground app derived from UsageEvents.
 * 
 * Semantics & Scoping:
 * - foregroundDurationMs: Aggregated time spent in foreground over the queried interval.
 * - foregroundTransitionCount: Count of observed ACTIVITY_RESUMED and MOVE_TO_FOREGROUND events.
 *   (Not called "launchCount" because Android does not guarantee every resume is a fresh launch).
 * - lastTimeUsedMs: Timestamp of the most recent usage / event.
 * - isCurrentlyForeground: True if the most recent observed transition event was a foreground event.
 * - isRecentlyUsedDerived: Derived heuristic signal based on (now - lastUsedMs) < 5 minutes (scope: DERIVED).
 * - timeSemantics: Explicitly records interval duration, start time, and end time.
 */
class AppUsageMonitor(
    private val context: Context
) {

    @Volatile
    private var cachedUsageData: Map<String, Any?>? = null
    private var lastUsageQueryTime: Long = 0
    private val cacheTtlMs = 30_000L // 30 seconds caching for heavy UsageStats queries

    // Health tracking
    @Volatile
    private var healthStatus: String = if (!isUsageAccessGranted()) "RESTRICTED" else "UNAVAILABLE"
    @Volatile
    private var lastErrorMessage: String? = null
    @Volatile
    private var lastSuccessfulCollectionMs: Long = 0

    fun getHealth(): Map<String, Any?> {
        val isGranted = isUsageAccessGranted()
        val currentStatus = when {
            !isGranted -> "RESTRICTED"
            healthStatus == "ERROR" -> "ERROR"
            healthStatus == "UNAVAILABLE" -> "UNAVAILABLE"
            healthStatus == "RESTRICTED" -> "RESTRICTED"
            healthStatus == "PARTIAL" -> "PARTIAL"
            else -> "VALID"
        }
        return mapOf(
            "status" to currentStatus,
            "message" to (if (!isGranted) "PACKAGE_USAGE_STATS permission not granted by user in Settings" else (lastErrorMessage ?: if (currentStatus == "PARTIAL") "Partial usage telemetry collected" else "Operating nominally")),
            "sourceApi" to "UsageStatsManager / UsageEvents",
            "lastSuccessTimestampMs" to lastSuccessfulCollectionMs,
            "usageAccessGranted" to isGranted
        )
    }

    fun isUsageAccessGranted(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val appOpsGranted = try {
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
        if (appOpsGranted) return true

        // Dual-check: on some Samsung and customized OEM devices, AppOps can report MODE_DEFAULT
        // even after user grants access in Settings. Verify via live test query.
        return try {
            val usageManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            val now = System.currentTimeMillis()
            val testStats = usageManager?.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                now - 60_000L,
                now
            )
            testStats != null && testStats.isNotEmpty()
        } catch (_: Exception) {
            false
        }
    }

    fun getStartOfTodayMs(): Long {
        val calendar = java.util.Calendar.getInstance()
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    fun invalidateCache() {
        cachedUsageData = null
        lastUsageQueryTime = 0
    }

    fun getUsageTelemetry(intervalHours: Int = 24, forceRefresh: Boolean = false): Map<String, Any?> {
        val now = System.currentTimeMillis()
        if (forceRefresh) {
            invalidateCache()
        }
        if (!forceRefresh && cachedUsageData != null && (now - lastUsageQueryTime < cacheTtlMs)) {
            return cachedUsageData!!
        }

        val startOfToday = getStartOfTodayMs()
        val isGranted = isUsageAccessGranted()
        if (!isGranted) {
            healthStatus = "RESTRICTED"
            lastErrorMessage = "PACKAGE_USAGE_STATS permission required"
            val restrictedResult = mapOf(
                "usageAccessGranted" to false,
                "availability" to "USAGE_DATA_UNAVAILABLE",
                "usageDataState" to "USAGE_DATA_UNAVAILABLE",
                "reason" to "PACKAGE_USAGE_STATS_REQUIRED",
                "queriedIntervalHours" to intervalHours,
                "startOfTodayMs" to startOfToday,
                "intervalStartTimeMs" to startOfToday,
                "intervalEndTimeMs" to now,
                "currentForegroundApp" to null,
                "totalForegroundDurationMs" to null,
                "totalForegroundTransitions" to null,
                "appsUsage" to emptyList<Map<String, Any?>>()
            )
            cachedUsageData = restrictedResult
            lastUsageQueryTime = now
            return restrictedResult
        }

        val usageManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        if (usageManager == null) {
            healthStatus = "UNAVAILABLE"
            lastErrorMessage = "USAGE_STATS_SERVICE not available on this device"
            val unavailableResult = mapOf(
                "usageAccessGranted" to false,
                "availability" to "UNAVAILABLE",
                "usageDataState" to "UNAVAILABLE",
                "reason" to "USAGE_STATS_SERVICE_NOT_FOUND",
                "queriedIntervalHours" to intervalHours,
                "startOfTodayMs" to startOfToday,
                "intervalStartTimeMs" to startOfToday,
                "intervalEndTimeMs" to now,
                "currentForegroundApp" to null,
                "totalForegroundDurationMs" to null,
                "totalForegroundTransitions" to null,
                "appsUsage" to emptyList<Map<String, Any?>>()
            )
            cachedUsageData = unavailableResult
            lastUsageQueryTime = now
            return unavailableResult
        }

        val endTime = now
        // Use device's local calendar day: startOfToday -> now
        val startTime = startOfToday

        val transitionCounts = mutableMapOf<String, Int>()
        val latestUsageEventByPackage = mutableMapOf<String, Long>()
        var currentForegroundPackage: String? = null
        var lastResumeTimestamp = 0L

        var eventsQueryError: Exception? = null
        try {
            val events = usageManager.queryEvents(startTime, endTime)
            val event = UsageEvents.Event()

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val pkg = event.packageName ?: continue
                val eventType = event.eventType

                // Only record user foreground / resume / user-interaction events for lastUsed
                if (eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                    eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                    eventType == UsageEvents.Event.USER_INTERACTION) {
                    val prev = latestUsageEventByPackage[pkg] ?: 0L
                    if (event.timeStamp > prev) {
                        latestUsageEventByPackage[pkg] = event.timeStamp
                    }
                    if (eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                        eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                        transitionCounts[pkg] = (transitionCounts[pkg] ?: 0) + 1
                        if (event.timeStamp >= lastResumeTimestamp) {
                            lastResumeTimestamp = event.timeStamp
                            currentForegroundPackage = pkg
                        }
                    }
                } else if (eventType == UsageEvents.Event.ACTIVITY_PAUSED ||
                    eventType == UsageEvents.Event.MOVE_TO_BACKGROUND ||
                    eventType == UsageEvents.Event.ACTIVITY_STOPPED) {
                    if (pkg == currentForegroundPackage && event.timeStamp >= lastResumeTimestamp) {
                        currentForegroundPackage = null
                    }
                }
            }
        } catch (e: Exception) {
            eventsQueryError = e
            lastErrorMessage = "UsageEvents query warning: ${e.message}"
        }

        var statsQueryError: Exception? = null
        val stats = try {
            usageManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            ) ?: emptyList()
        } catch (e: Exception) {
            statsQueryError = e
            emptyList()
        }

        // Map latest lastTimeUsed per package from today's UsageStats
        val statsLastUsedByPackage = mutableMapOf<String, Long>()
        for (app in stats) {
            val pkg = app.packageName ?: continue
            val prev = statsLastUsedByPackage[pkg] ?: 0L
            if (app.lastTimeUsed > prev) {
                statsLastUsedByPackage[pkg] = app.lastTimeUsed
            }
        }

        // Also query historical usage stats (up to 30 days) to accurately resolve lastTimeUsed for packages not active today
        try {
            val historyStats = usageManager.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                now - (30L * 24 * 60 * 60 * 1000L),
                now
            ) ?: emptyList()
            for (app in historyStats) {
                val pkg = app.packageName ?: continue
                val prev = statsLastUsedByPackage[pkg] ?: 0L
                if (app.lastTimeUsed > prev) {
                    statsLastUsedByPackage[pkg] = app.lastTimeUsed
                }
            }
        } catch (_: Exception) {}

        fun getLastUsed(packageName: String): Long {
            val eventTime = latestUsageEventByPackage[packageName] ?: 0L
            val statTime = statsLastUsedByPackage[packageName] ?: 0L
            return maxOf(eventTime, statTime)
        }

        // Case 1: Both queries failed
        if (statsQueryError != null && eventsQueryError != null) {
            val ex = statsQueryError ?: eventsQueryError
            val status = if (ex is SecurityException) "RESTRICTED" else "ERROR"
            healthStatus = status
            lastErrorMessage = "Usage queries failed: events(${eventsQueryError?.message}), stats(${statsQueryError?.message})"
            val errorResult = mapOf(
                "usageAccessGranted" to true,
                "availability" to status,
                "eventsAvailability" to (if (eventsQueryError is SecurityException) "RESTRICTED" else "ERROR"),
                "statsAvailability" to (if (statsQueryError is SecurityException) "RESTRICTED" else "ERROR"),
                "eventsError" to eventsQueryError?.message,
                "statsError" to statsQueryError?.message,
                "reason" to lastErrorMessage,
                "queriedIntervalHours" to intervalHours,
                "intervalStartTimeMs" to startTime,
                "intervalEndTimeMs" to endTime,
                "currentForegroundApp" to null,
                "totalForegroundDurationMs" to null,
                "totalForegroundTransitions" to null,
                "appsUsage" to emptyList<Map<String, Any?>>()
            )
            cachedUsageData = errorResult
            lastUsageQueryTime = now
            return errorResult
        }

        // Case 2: UsageEvents succeeded, but UsageStats failed
        if (statsQueryError != null) {
            val status = if (statsQueryError is SecurityException) "RESTRICTED" else "ERROR"
            healthStatus = "PARTIAL"
            lastErrorMessage = "UsageStats query failed: ${statsQueryError.message} (UsageEvents succeeded)"
            lastSuccessfulCollectionMs = now

            val aggregatedUsage = mutableMapOf<String, MutableMap<String, Any?>>()
            var totalDeviceTransitions = 0

            for ((pkg, transitions) in transitionCounts) {
                val lastEventTime = getLastUsed(pkg)
                val isCurrentlyForeground = (pkg == currentForegroundPackage)
                val isRecentlyUsedDerived = if (lastEventTime > 0) (endTime - lastEventTime) < (5 * 60 * 1000) else false

                totalDeviceTransitions += transitions
                aggregatedUsage[pkg] = mutableMapOf(
                    "packageName" to pkg,
                    "lastTimeUsedMs" to lastEventTime,
                    "lastUsedTimestamp" to lastEventTime,
                    "foregroundDurationMs" to null,
                    "foregroundMinutes" to null,
                    "usageTodayMs" to null,
                    "foregroundTimeMs" to null,
                    "visibleTimeMs" to null,
                    "foregroundServiceTimeMs" to null,
                    "foregroundTransitionCount" to transitions,
                    "isCurrentlyForeground" to isCurrentlyForeground,
                    "isRecentlyUsedDerived" to (isRecentlyUsedDerived || isCurrentlyForeground),
                    "usageAvailability" to "PARTIAL_EVENTS_ONLY",
                    "usageDataState" to "PARTIAL"
                )
            }

            val partialResult = mapOf(
                "usageAccessGranted" to true,
                "availability" to "PARTIAL",
                "eventsAvailability" to "AVAILABLE",
                "statsAvailability" to status,
                "eventsError" to null,
                "statsError" to statsQueryError.message,
                "queriedIntervalHours" to intervalHours,
                "intervalStartTimeMs" to startTime,
                "intervalEndTimeMs" to endTime,
                "currentForegroundApp" to currentForegroundPackage,
                "totalForegroundDurationMs" to null,
                "totalForegroundTransitions" to totalDeviceTransitions,
                "appsUsage" to aggregatedUsage.values.toList()
            )
            cachedUsageData = partialResult
            lastUsageQueryTime = now
            return partialResult
        }

        // Case 3: UsageStats succeeded, but UsageEvents failed
        if (eventsQueryError != null) {
            val status = if (eventsQueryError is SecurityException) "RESTRICTED" else "ERROR"
            healthStatus = "PARTIAL"
            lastErrorMessage = "UsageEvents query failed: ${eventsQueryError.message} (UsageStats succeeded)"
            lastSuccessfulCollectionMs = now

            val aggregatedUsage = mutableMapOf<String, MutableMap<String, Any?>>()
            var totalDeviceForegroundTimeMs = 0L

            for (app in stats) {
                val pkg = app.packageName ?: continue
                val timeInFg = app.totalTimeInForeground
                val lastUsed = getLastUsed(pkg)
                val isRecentlyUsedDerived = if (lastUsed > 0) (endTime - lastUsed) < (5 * 60 * 1000) else false

                val visibleTime: Long? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try { app.totalTimeVisible } catch (_: Exception) { null }
                } else null
                val fgServiceTime: Long? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try { app.totalTimeForegroundServiceUsed } catch (_: Exception) { null }
                } else null

                totalDeviceForegroundTimeMs += timeInFg

                val existing = aggregatedUsage[pkg]
                if (existing != null) {
                    val prevTime = existing["foregroundDurationMs"] as? Long ?: 0L
                    val prevLastUsed = existing["lastUsedTimestamp"] as? Long ?: 0L
                    val newTotalTime = prevTime + timeInFg
                    existing["foregroundDurationMs"] = newTotalTime
                    existing["usageTodayMs"] = newTotalTime
                    existing["foregroundTimeMs"] = newTotalTime
                    existing["foregroundMinutes"] = newTotalTime / 60000.0
                    existing["lastTimeUsedMs"] = maxOf(prevLastUsed, lastUsed)
                    existing["lastUsedTimestamp"] = maxOf(prevLastUsed, lastUsed)
                    existing["isRecentlyUsedDerived"] = isRecentlyUsedDerived
                    if (visibleTime != null) existing["visibleTimeMs"] = visibleTime
                    if (fgServiceTime != null) existing["foregroundServiceTimeMs"] = fgServiceTime
                } else {
                    aggregatedUsage[pkg] = mutableMapOf(
                        "packageName" to pkg,
                        "lastTimeUsedMs" to lastUsed,
                        "lastUsedTimestamp" to lastUsed,
                        "foregroundDurationMs" to timeInFg,
                        "usageTodayMs" to timeInFg,
                        "foregroundTimeMs" to timeInFg,
                        "visibleTimeMs" to visibleTime,
                        "foregroundServiceTimeMs" to fgServiceTime,
                        "foregroundMinutes" to (timeInFg / 60000.0),
                        "foregroundTransitionCount" to null,
                        "isCurrentlyForeground" to null,
                        "isRecentlyUsedDerived" to isRecentlyUsedDerived,
                        "usageAvailability" to "PARTIAL_STATS_ONLY",
                        "usageDataState" to "PARTIAL"
                    )
                }
            }

            val partialResult = mapOf(
                "usageAccessGranted" to true,
                "availability" to "PARTIAL",
                "usageDataState" to "PARTIAL",
                "eventsAvailability" to status,
                "statsAvailability" to "AVAILABLE",
                "eventsError" to eventsQueryError.message,
                "statsError" to null,
                "queriedIntervalHours" to intervalHours,
                "intervalStartTimeMs" to startTime,
                "intervalEndTimeMs" to endTime,
                "currentForegroundApp" to null,
                "totalForegroundDurationMs" to totalDeviceForegroundTimeMs,
                "totalForegroundTransitions" to null,
                "appsUsage" to aggregatedUsage.values.toList(),
                "allPackagesLastUsed" to statsLastUsedByPackage
            )
            cachedUsageData = partialResult
            lastUsageQueryTime = now
            return partialResult
        }

        // Case 4: Both queries succeeded
        healthStatus = "VALID"
        lastErrorMessage = null
        lastSuccessfulCollectionMs = now

        // Aggregate usage stats by package name
        val aggregatedUsage = mutableMapOf<String, MutableMap<String, Any?>>()
        var totalDeviceForegroundTimeMs = 0L
        var totalDeviceTransitions = 0

        for (app in stats) {
            val pkg = app.packageName ?: continue
            val timeInFg = app.totalTimeInForeground
            val transitions = transitionCounts[pkg] ?: 0
            val lastUsed = getLastUsed(pkg)
            val isCurrentlyForeground = (pkg == currentForegroundPackage)
            val isRecentlyUsedDerived = if (lastUsed > 0) (endTime - lastUsed) < (5 * 60 * 1000) else false

            val visibleTime: Long? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try { app.totalTimeVisible } catch (_: Exception) { null }
            } else null
            val fgServiceTime: Long? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try { app.totalTimeForegroundServiceUsed } catch (_: Exception) { null }
            } else null

            totalDeviceForegroundTimeMs += timeInFg
            totalDeviceTransitions += transitions

            val existing = aggregatedUsage[pkg]
            if (existing != null) {
                val prevTime = existing["foregroundDurationMs"] as? Long ?: 0L
                val prevLastUsed = existing["lastUsedTimestamp"] as? Long ?: 0L
                val newTotalTime = prevTime + timeInFg
                existing["foregroundDurationMs"] = newTotalTime
                existing["usageTodayMs"] = newTotalTime
                existing["foregroundTimeMs"] = newTotalTime
                existing["foregroundMinutes"] = newTotalTime / 60000.0
                existing["lastTimeUsedMs"] = maxOf(prevLastUsed, lastUsed)
                existing["lastUsedTimestamp"] = maxOf(prevLastUsed, lastUsed)
                existing["isCurrentlyForeground"] = isCurrentlyForeground
                existing["isRecentlyUsedDerived"] = isRecentlyUsedDerived || isCurrentlyForeground
                if (visibleTime != null) existing["visibleTimeMs"] = visibleTime
                if (fgServiceTime != null) existing["foregroundServiceTimeMs"] = fgServiceTime
            } else {
                aggregatedUsage[pkg] = mutableMapOf(
                    "packageName" to pkg,
                    "lastTimeUsedMs" to lastUsed,
                    "lastUsedTimestamp" to lastUsed,
                    "foregroundDurationMs" to timeInFg,
                    "usageTodayMs" to timeInFg,
                    "foregroundTimeMs" to timeInFg,
                    "visibleTimeMs" to visibleTime,
                    "foregroundServiceTimeMs" to fgServiceTime,
                    "foregroundMinutes" to (timeInFg / 60000.0),
                    "foregroundTransitionCount" to transitions,
                    "isCurrentlyForeground" to isCurrentlyForeground,
                    "isRecentlyUsedDerived" to (isRecentlyUsedDerived || isCurrentlyForeground),
                    "usageAvailability" to "VALID",
                    "usageDataState" to "AVAILABLE"
                )
            }
        }

        // Add packages that had transition/usage events but were not present in stats query
        for ((pkg, eventTime) in latestUsageEventByPackage) {
            if (!aggregatedUsage.containsKey(pkg)) {
                val transitions = transitionCounts[pkg] ?: 0
                val isCurrentlyForeground = (pkg == currentForegroundPackage)
                val isRecentlyUsedDerived = (endTime - eventTime) < (5 * 60 * 1000)

                totalDeviceTransitions += transitions
                aggregatedUsage[pkg] = mutableMapOf(
                    "packageName" to pkg,
                    "lastTimeUsedMs" to eventTime,
                    "lastUsedTimestamp" to eventTime,
                    "foregroundDurationMs" to 0L,
                    "usageTodayMs" to 0L,
                    "foregroundTimeMs" to 0L,
                    "visibleTimeMs" to null,
                    "foregroundServiceTimeMs" to null,
                    "foregroundMinutes" to 0.0,
                    "foregroundTransitionCount" to transitions,
                    "isCurrentlyForeground" to isCurrentlyForeground,
                    "isRecentlyUsedDerived" to (isRecentlyUsedDerived || isCurrentlyForeground),
                    "usageAvailability" to "VALID",
                    "usageDataState" to "AVAILABLE"
                )
            }
        }

        val availabilityStatus = if (aggregatedUsage.isEmpty()) "ZERO_REPORTED" else "VALID"

        val result = mapOf(
            "usageAccessGranted" to true,
            "availability" to availabilityStatus,
            "eventsAvailability" to "VALID",
            "statsAvailability" to "VALID",
            "queriedIntervalHours" to intervalHours,
            "intervalStartTimeMs" to startTime,
            "intervalEndTimeMs" to endTime,
            "currentForegroundApp" to currentForegroundPackage,
            "totalForegroundDurationMs" to totalDeviceForegroundTimeMs,
            "totalForegroundTransitions" to totalDeviceTransitions,
            "appsUsage" to aggregatedUsage.values.toList(),
            "allPackagesLastUsed" to statsLastUsedByPackage
        )

        cachedUsageData = result
        lastUsageQueryTime = now
        return result
    }
}