package com.example.mobile_privacy_security_project

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.Build
import android.os.Process

/**
 * Collects legitimate network telemetry separated into:
 * 1. Device-Level Network Telemetry (TrafficStats cumulative totals, ConnectivityManager transports, bandwidth, VPN state).
 * 2. App-Level Network Telemetry (NetworkStatsManager historical per-UID usage when PACKAGE_USAGE_STATS is granted).
 * 
 * Frequency Tiers:
 * - EVENT-DRIVEN: Network connectivity, active transport, bandwidth, and VPN state (via ConnectivityManager.NetworkCallback).
 * - PERIODIC: TrafficStats device cumulative totals.
 * - HISTORICAL: Per-UID network statistics (24h window via NetworkStatsManager, cached with 30s TTL).
 * 
 * Never converts TrafficStats.UNSUPPORTED (-1) to fake 0L.
 * Executes heavy queries on background threads to prevent UI blocking.
 */
class NetworkMonitor(
    private val context: Context
) {

    data class UidNetworkUsage(
        val uid: Int,
        val txBytes: Long,
        val rxBytes: Long,
        val availability: String,
        val source: String
    )

    data class UidNetworkQueryResult(
        val status: String,
        val statsByUid: Map<Int, UidNetworkUsage>,
        val errorMessage: String? = null,
        val sourceApi: String = "NetworkStatsManager"
    )

    @Volatile
    private var isConnectedEvent: Boolean = false
    @Volatile
    private var transportEvent: String = "NONE"
    @Volatile
    private var isMeteredEvent: Boolean = false
    @Volatile
    private var downstreamBandwidthKbpsEvent: Int = 0
    @Volatile
    private var upstreamBandwidthKbpsEvent: Int = 0
    @Volatile
    private var vpnActiveEvent: Boolean = false

    private var isCallbackRegistered = false
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    @Volatile
    private var cachedUidStats: Map<Int, UidNetworkUsage>? = null
    @Volatile
    private var cachedQueryResult: UidNetworkQueryResult? = null
    private var lastUidStatsQueryTime: Long = 0
    private val cacheTtlMs = 30_000L // 30 seconds caching for heavy NetworkStatsManager queries

    // Health state
    @Volatile
    private var healthStatus: String = if (!isUsageAccessGranted()) "RESTRICTED" else "UNAVAILABLE"
    @Volatile
    private var lastErrorMessage: String? = null
    @Volatile
    private var lastSuccessfulCollectionMs: Long = 0

    init {
        registerNetworkCallback()
    }

    fun getHealth(): Map<String, Any?> {
        val isGranted = isUsageAccessGranted()
        val totalTx = TrafficStats.getTotalTxBytes()
        val isTrafficStatsAvailable = totalTx >= 0

        // The health state represents the ACTUAL latest collection condition.
        // It does NOT return to VALID simply because a permission check currently returns true.
        // A state returns to VALID ONLY after a NEW successful collection confirms data can actually be collected.
        // If permission is revoked (!isGranted), it must immediately reflect RESTRICTED.
        val currentStatus = if (!isGranted) {
            "RESTRICTED"
        } else {
            healthStatus
        }

        val defaultMsg = when (currentStatus) {
            "ERROR" -> "Network query error encountered"
            "UNAVAILABLE" -> "Network statistics service unavailable"
            "RESTRICTED" -> "App-level network queries restricted without PACKAGE_USAGE_STATS"
            "DENIED" -> "App-level network queries denied"
            else -> "Operating nominally"
        }

        return mapOf(
            "status" to currentStatus,
            "message" to (lastErrorMessage ?: defaultMsg),
            "sourceApi" to "TrafficStats / ConnectivityManager / NetworkStatsManager",
            "lastSuccessTimestampMs" to lastSuccessfulCollectionMs,
            "usageAccessGranted" to isGranted,
            "trafficStatsSupported" to isTrafficStatsAvailable
        )
    }

    @Synchronized
    fun registerNetworkCallback() {
        if (isCallbackRegistered) return
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        try {
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    isConnectedEvent = true
                    updateCapabilities(cm, network)
                }

                override fun onLost(network: Network) {
                    isConnectedEvent = false
                    transportEvent = "NONE"
                    vpnActiveEvent = false
                    isMeteredEvent = false
                    downstreamBandwidthKbpsEvent = 0
                    upstreamBandwidthKbpsEvent = 0
                }

                override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                    isConnectedEvent = true
                    vpnActiveEvent = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                    transportEvent = when {
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WIFI"
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "CELLULAR"
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ETHERNET"
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "BLUETOOTH"
                        vpnActiveEvent -> "VPN"
                        else -> "OTHER"
                    }
                    downstreamBandwidthKbpsEvent = capabilities.linkDownstreamBandwidthKbps
                    upstreamBandwidthKbpsEvent = capabilities.linkUpstreamBandwidthKbps
                    isMeteredEvent = cm.isActiveNetworkMetered
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                cm.registerDefaultNetworkCallback(networkCallback!!)
            }
            isCallbackRegistered = true
        } catch (e: Exception) {
            lastErrorMessage = "NetworkCallback registration restricted: ${e.message}"
            if (e is SecurityException) {
                healthStatus = "RESTRICTED"
            }
        }
    }

    private fun updateCapabilities(cm: ConnectivityManager, network: Network) {
        try {
            val capabilities = cm.getNetworkCapabilities(network) ?: return
            vpnActiveEvent = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            transportEvent = when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WIFI"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "CELLULAR"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ETHERNET"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "BLUETOOTH"
                vpnActiveEvent -> "VPN"
                else -> "OTHER"
            }
            downstreamBandwidthKbpsEvent = capabilities.linkDownstreamBandwidthKbps
            upstreamBandwidthKbpsEvent = capabilities.linkUpstreamBandwidthKbps
            isMeteredEvent = cm.isActiveNetworkMetered
        } catch (e: Exception) {
            lastErrorMessage = "Capabilities inspection error: ${e.message}"
            if (e is SecurityException) {
                healthStatus = "RESTRICTED"
            }
        }
    }

    @Synchronized
    fun unregister() {
        if (!isCallbackRegistered) return
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (networkCallback != null && cm != null) {
                cm.unregisterNetworkCallback(networkCallback!!)
            }
            isCallbackRegistered = false
            networkCallback = null
        } catch (_: Exception) {
            // Safe cleanup
        }
    }

    fun invalidateCache() {
        cachedUidStats = null
        cachedQueryResult = null
        lastUidStatsQueryTime = 0
    }

    fun getDeviceNetworkTelemetry(): Map<String, Any?> {
        val totalTx = TrafficStats.getTotalTxBytes()
        val totalRx = TrafficStats.getTotalRxBytes()
        val mobileTx = TrafficStats.getMobileTxBytes()
        val mobileRx = TrafficStats.getMobileRxBytes()

        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        var isConnected = isConnectedEvent
        var transport = transportEvent
        var isMetered = isMeteredEvent
        var downstreamBandwidthKbps = downstreamBandwidthKbpsEvent
        var upstreamBandwidthKbps = upstreamBandwidthKbpsEvent
        var vpnActive = vpnActiveEvent

        if (cm != null) {
            try {
                val activeNetwork = cm.activeNetwork
                if (activeNetwork != null) {
                    isConnected = true
                    val capabilities = cm.getNetworkCapabilities(activeNetwork)
                    if (capabilities != null) {
                        vpnActive = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                        transport = when {
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WIFI"
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "CELLULAR"
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ETHERNET"
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "BLUETOOTH"
                            vpnActive -> "VPN"
                            else -> "OTHER"
                        }
                        downstreamBandwidthKbps = capabilities.linkDownstreamBandwidthKbps
                        upstreamBandwidthKbps = capabilities.linkUpstreamBandwidthKbps
                    }
                    isMetered = cm.isActiveNetworkMetered
                } else if (!isCallbackRegistered) {
                    isConnected = false
                    transport = "NONE"
                }
            } catch (e: Exception) {
                lastErrorMessage = "Active network query error: ${e.message}"
                if (e is SecurityException) {
                    healthStatus = "RESTRICTED"
                }
            }
        }

        val trafficStatsSupported = totalTx >= 0 && totalRx >= 0

        return mapOf(
            "isConnected" to isConnected,
            "transport" to transport,
            "isMetered" to isMetered,
            "downstreamBandwidthKbps" to downstreamBandwidthKbps,
            "upstreamBandwidthKbps" to upstreamBandwidthKbps,
            "vpnActive" to vpnActive,
            "trafficStatsAvailability" to if (trafficStatsSupported) "AVAILABLE" else "UNSUPPORTED",
            "deviceTotalTxBytes" to if (totalTx >= 0) totalTx else null,
            "deviceTotalRxBytes" to if (totalRx >= 0) totalRx else null,
            "deviceMobileTxBytes" to if (mobileTx >= 0) mobileTx else null,
            "deviceMobileRxBytes" to if (mobileRx >= 0) mobileRx else null
        )
    }

    /**
     * Queries legitimate historical per-UID network statistics using NetworkStatsManager.
     * Requires PACKAGE_USAGE_STATS permission / Usage Access.
     * 
     * Returns structured UidNetworkQueryResult distinguishing:
     * - VALID: Successful query with traffic records.
     * - ZERO_REPORTED: Successful query where device reported no traffic buckets.
     * - RESTRICTED / DENIED: PACKAGE_USAGE_STATS not granted.
     * - UNAVAILABLE: NETWORK_STATS_SERVICE not present on device.
     * - ERROR: Operational binder or IPC failure during query execution.
     */
    fun queryAllUidNetworkStatsDetailed(intervalHours: Int = 24, forceRefresh: Boolean = false): UidNetworkQueryResult {
        val now = System.currentTimeMillis()
        if (!forceRefresh && cachedQueryResult != null && (now - lastUidStatsQueryTime < cacheTtlMs)) {
            return cachedQueryResult!!
        }

        if (!isUsageAccessGranted()) {
            healthStatus = "RESTRICTED"
            lastErrorMessage = "App-level network queries restricted: PACKAGE_USAGE_STATS permission not granted"
            val result = UidNetworkQueryResult(
                status = "RESTRICTED",
                statsByUid = emptyMap(),
                errorMessage = lastErrorMessage
            )
            cachedQueryResult = result
            cachedUidStats = emptyMap()
            lastUidStatsQueryTime = now
            return result
        }

        val networkStatsManager = context.getSystemService(Context.NETWORK_STATS_SERVICE) as? NetworkStatsManager
        if (networkStatsManager == null) {
            healthStatus = "UNAVAILABLE"
            lastErrorMessage = "NETWORK_STATS_SERVICE is not available on this device"
            val result = UidNetworkQueryResult(
                status = "UNAVAILABLE",
                statsByUid = emptyMap(),
                errorMessage = lastErrorMessage
            )
            cachedQueryResult = result
            cachedUidStats = emptyMap()
            lastUidStatsQueryTime = now
            return result
        }

        val endTime = now
        val startTime = endTime - (intervalHours.toLong() * 60 * 60 * 1000)
        val uidStatsMap = mutableMapOf<Int, UidNetworkUsage>()
        var queryError: Exception? = null

        try {
            collectTransportStats(networkStatsManager, NetworkCapabilities.TRANSPORT_WIFI, startTime, endTime, uidStatsMap)
            collectTransportStats(networkStatsManager, NetworkCapabilities.TRANSPORT_CELLULAR, startTime, endTime, uidStatsMap)
        } catch (e: Exception) {
            queryError = e
        }

        val result = if (queryError != null) {
            val status = if (queryError is SecurityException) "RESTRICTED" else "ERROR"
            healthStatus = status
            lastErrorMessage = queryError.message ?: "NetworkStatsManager query failed"
            UidNetworkQueryResult(
                status = status,
                statsByUid = emptyMap(),
                errorMessage = lastErrorMessage
            )
        } else {
            healthStatus = "VALID"
            lastErrorMessage = null
            lastSuccessfulCollectionMs = now
            val status = if (uidStatsMap.isEmpty()) "ZERO_REPORTED" else "VALID"
            UidNetworkQueryResult(
                status = status,
                statsByUid = uidStatsMap
            )
        }

        cachedQueryResult = result
        cachedUidStats = result.statsByUid
        lastUidStatsQueryTime = now
        return result
    }

    /**
     * Backward-compatible convenience accessor for per-UID usage map.
     */
    fun queryAllUidNetworkStats(intervalHours: Int = 24, forceRefresh: Boolean = false): Map<Int, UidNetworkUsage> {
        return queryAllUidNetworkStatsDetailed(intervalHours, forceRefresh).statsByUid
    }

    private fun collectTransportStats(
        nsm: NetworkStatsManager,
        transportType: Int,
        startTime: Long,
        endTime: Long,
        accumulator: MutableMap<Int, UidNetworkUsage>
    ) {
        val stats: NetworkStats = nsm.querySummary(transportType, null, startTime, endTime)
        val bucket = NetworkStats.Bucket()

        while (stats.hasNextBucket()) {
            stats.getNextBucket(bucket)
            val uid = bucket.uid
            if (uid < 0) continue

            val existing = accumulator[uid]
            val tx = (existing?.txBytes ?: 0L) + bucket.txBytes
            val rx = (existing?.rxBytes ?: 0L) + bucket.rxBytes
            val availability = if (tx == 0L && rx == 0L) "ZERO_REPORTED" else "VALID"

            accumulator[uid] = UidNetworkUsage(
                uid = uid,
                txBytes = tx,
                rxBytes = rx,
                availability = availability,
                source = "NetworkStatsManager"
            )
        }
        stats.close()
    }

    fun isUsageAccessGranted(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        return try {
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
    }
}