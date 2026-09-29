package com.example.mobile_privacy_security_project

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import java.io.File

/**
 * Collects legitimate device-level security context and host-app capabilities.
 * 
 * Strict Scoping:
 * - Host-App Capabilities: selfCanDrawOverlays, selfIsIgnoringBatteryOptimizations, selfCanRequestPackageInstalls.
 * - Device-Wide State: developerOptionsEnabled, adbEnabled, accessibilityEnabled, enabledAccessibilityServices, isDeviceSecure, vpnActive.
 * - Probabilistic Root Heuristic: Multi-indicator inspection (never claimed to be absolute).
 * 
 * NON-RESPONSIBILITY:
 * - Pure observations only. No risk inference or threat scoring is performed here.
 */
class DeviceSecurityMonitor(
    private val context: Context
) {

    @Volatile
    private var healthStatus: String = "VALID"
    @Volatile
    private var lastErrorMessage: String? = null
    @Volatile
    private var lastSuccessfulCollectionMs: Long = 0

    fun getHealth(): Map<String, Any?> {
        return mapOf(
            "status" to healthStatus,
            "message" to (lastErrorMessage ?: if (healthStatus == "VALID") "Operating nominally" else "Security signals inspection issue"),
            "sourceApi" to "Settings.Global / KeyguardManager / PowerManager / AccessibilityManager",
            "lastSuccessTimestampMs" to lastSuccessfulCollectionMs
        )
    }

    private val recordedErrors = mutableListOf<Throwable>()
    private val recordedMessages = mutableListOf<String>()

    private fun recordQueryFailure(e: Throwable?, detail: String) {
        synchronized(recordedErrors) {
            if (e != null) {
                recordedErrors.add(e)
                recordedMessages.add("$detail: ${e.message}")
            } else {
                recordedMessages.add(detail)
            }
        }
    }

    fun selfCanDrawOverlays(): Boolean? {
        return try {
            Settings.canDrawOverlays(context)
        } catch (e: Exception) {
            recordQueryFailure(e, "selfCanDrawOverlays")
            null
        }
    }

    fun selfIsIgnoringBatteryOptimizations(): Boolean? {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (power == null) {
            recordQueryFailure(null, "PowerManager unavailable for battery optimization check")
            return null
        }
        return try {
            power.isIgnoringBatteryOptimizations(context.packageName)
        } catch (e: Exception) {
            recordQueryFailure(e, "selfIsIgnoringBatteryOptimizations")
            null
        }
    }

    fun selfCanRequestPackageInstalls(): Boolean? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.packageManager.canRequestPackageInstalls()
            } else {
                @Suppress("DEPRECATION")
                Settings.Secure.getInt(
                    context.contentResolver,
                    Settings.Secure.INSTALL_NON_MARKET_APPS,
                    0
                ) != 0
            }
        } catch (e: Exception) {
            recordQueryFailure(e, "selfCanRequestPackageInstalls")
            null
        }
    }

    fun accessibilityEnabled(): Boolean? {
        val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        if (manager == null) {
            recordQueryFailure(null, "AccessibilityManager unavailable")
            return null
        }
        return try {
            manager.isEnabled && manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).isNotEmpty()
        } catch (e: Exception) {
            recordQueryFailure(e, "accessibilityEnabled")
            null
        }
    }

    fun getEnabledAccessibilityServices(): List<String>? {
        val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        if (manager == null) {
            recordQueryFailure(null, "AccessibilityManager unavailable")
            return null
        }
        return try {
            manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                .mapNotNull { it.id ?: it.resolveInfo?.serviceInfo?.name }
        } catch (e: Exception) {
            recordQueryFailure(e, "getEnabledAccessibilityServices")
            null
        }
    }

    fun developerOptionsEnabled(): Boolean? {
        return try {
            Settings.Global.getInt(
                context.contentResolver,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED,
                0
            ) != 0
        } catch (e: Exception) {
            recordQueryFailure(e, "developerOptionsEnabled")
            null
        }
    }

    fun adbEnabled(): Boolean? {
        return try {
            Settings.Global.getInt(
                context.contentResolver,
                Settings.Global.ADB_ENABLED,
                0
            ) != 0
        } catch (e: Exception) {
            recordQueryFailure(e, "adbEnabled")
            null
        }
    }

    fun isDeviceSecure(): Boolean? {
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard == null) {
            recordQueryFailure(null, "KeyguardManager unavailable")
            return null
        }
        return try {
            keyguard.isDeviceSecure
        } catch (e: Exception) {
            recordQueryFailure(e, "isDeviceSecure")
            null
        }
    }

    fun vpnActive(): Boolean? {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (manager == null) {
            recordQueryFailure(null, "ConnectivityManager unavailable")
            return null
        }
        return try {
            val network = manager.activeNetwork
            if (network == null) {
                false // Device has no active network -> VPN is not active
            } else {
                val capabilities = manager.getNetworkCapabilities(network)
                if (capabilities != null) {
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                } else {
                    recordQueryFailure(null, "NetworkCapabilities unavailable for active network")
                    null // Could not retrieve network capabilities
                }
            }
        } catch (e: Exception) {
            recordQueryFailure(e, "vpnActive")
            null
        }
    }

    /**
     * Probabilistic root detection heuristic.
     * 
     * Uses legitimate dynamic Android platform signals:
     * 1. Test-keys in Build tags.
     * 2. Non-release/test build indicators in Build fingerprint.
     * 3. Presence of 'su' binaries in standard system locations.
     * 
     * Non-authoritative: Reports raw observations with rootDetectionMethod=HEURISTIC.
     * Does not depend on hardcoded package lists or make unsupported claims.
     */
    fun evaluateRootHeuristic(): Map<String, Any?> {
        val matchedIndicators = mutableListOf<String>()

        // Signal 1: Dynamic Build Tags inspection
        try {
            val buildTags = Build.TAGS
            if (buildTags != null && buildTags.contains("test-keys")) {
                matchedIndicators.add("BUILD_TAGS_TEST_KEYS")
            }
        } catch (e: Exception) {
            recordQueryFailure(e, "Build.TAGS inspection")
        }

        // Signal 2: Dynamic Build Fingerprint inspection
        try {
            val fingerprint = Build.FINGERPRINT
            if (fingerprint != null && (fingerprint.startsWith("generic") || fingerprint.contains("test-keys"))) {
                matchedIndicators.add("BUILD_FINGERPRINT_NON_RELEASE")
            }
        } catch (e: Exception) {
            recordQueryFailure(e, "Build.FINGERPRINT inspection")
        }

        // Signal 3: Standard system su binary inspection
        val standardSuPaths = arrayOf(
            "/system/bin/su",
            "/system/xbin/su",
            "/sbin/su",
            "/vendor/bin/su"
        )
        for (path in standardSuPaths) {
            try {
                if (File(path).exists()) {
                    matchedIndicators.add("SU_BINARY_PATH:$path")
                    break
                }
            } catch (e: Exception) {
                recordQueryFailure(e, "SU binary check ($path)")
            }
        }

        val hasHeuristicIndicators = matchedIndicators.isNotEmpty()
        val confidence = when {
            matchedIndicators.size >= 2 -> "HIGH"
            matchedIndicators.size == 1 -> "HEURISTIC_INDICATOR"
            else -> "NONE"
        }

        return mapOf(
            "rootDetectionMethod" to "HEURISTIC",
            "isRootedHeuristic" to hasHeuristicIndicators,
            "confidence" to confidence,
            "matchedIndicators" to matchedIndicators,
            "disclaimer" to "Observation only. Heuristic root signals cannot authoritatively confirm or disprove root."
        )
    }

    fun collectSecurityState(): Map<String, Any?> {
        synchronized(recordedErrors) {
            recordedErrors.clear()
            recordedMessages.clear()
        }

        val rootResult = evaluateRootHeuristic()
        val selfOverlay = selfCanDrawOverlays()
        val selfBatteryOpt = selfIsIgnoringBatteryOptimizations()
        val selfInstall = selfCanRequestPackageInstalls()
        val isDevOptions = developerOptionsEnabled()
        val isAdb = adbEnabled()
        val isAccessEnabled = accessibilityEnabled()
        val accessServices = getEnabledAccessibilityServices()
        val isSecure = isDeviceSecure()
        val isVpn = vpnActive()

        var hasSecException = false
        var hasException = false
        var hasUnavailable = false
        var errorSummary: String? = null

        synchronized(recordedErrors) {
            hasSecException = recordedErrors.any { it is SecurityException }
            hasException = recordedErrors.any { it !is SecurityException }
            hasUnavailable = recordedMessages.isNotEmpty() && recordedErrors.isEmpty()
            errorSummary = if (recordedMessages.isNotEmpty()) recordedMessages.joinToString("; ") else null
        }

        if (hasSecException) {
            healthStatus = "RESTRICTED"
            lastErrorMessage = errorSummary ?: "Security signal query restricted"
        } else if (hasException) {
            healthStatus = "ERROR"
            lastErrorMessage = errorSummary ?: "Security signal query failed"
        } else if (hasUnavailable) {
            healthStatus = "UNAVAILABLE"
            lastErrorMessage = errorSummary ?: "Security system services unavailable"
        } else {
            healthStatus = "VALID"
            lastErrorMessage = null
            lastSuccessfulCollectionMs = System.currentTimeMillis()
        }

        return mapOf(
            "selfCanDrawOverlays" to selfOverlay,
            "selfIsIgnoringBatteryOptimizations" to selfBatteryOpt,
            "selfCanRequestPackageInstalls" to selfInstall,
            "accessibilityEnabled" to isAccessEnabled,
            "enabledAccessibilityServices" to accessServices,
            "developerOptionsEnabled" to isDevOptions,
            "adbEnabled" to isAdb,
            "isDeviceSecure" to isSecure,
            "vpnActive" to isVpn,
            "rootDetection" to rootResult
        )
    }
}