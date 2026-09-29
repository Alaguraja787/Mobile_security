package com.example.mobile_privacy_security_project

import android.app.AppOpsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.PermissionInfo
import android.os.Build
import java.util.concurrent.ConcurrentHashMap

/**
 * Collects legitimate application inventory and permission metadata from Android PackageManager.
 * 
 * Frequency Tiers:
 * - STATIC_CACHED: Package metadata and permission protection levels.
 * - EVENT-DRIVEN: Cache invalidated immediately upon ACTION_PACKAGE_ADDED, REMOVED, REPLACED broadcasts.
 * 
 * Capabilities:
 * - Requested permissions vs Granted permissions vs Denied permissions.
 * - Dangerous Requested permissions vs Dangerous Granted permissions.
 * - Dynamic dangerous permission classification via PermissionInfo.PROTECTION_DANGEROUS (no hardcoded keywords).
 * - Per-package AppOps (SYSTEM_ALERT_WINDOW, GET_USAGE_STATS).
 * - Installation and update timestamps, installer package source.
 */
class PermissionMonitor(
    private val context: Context
) {

    // Cache permission protection level to avoid repetitive PackageManager queries
    private val permissionProtectionCache = ConcurrentHashMap<String, Boolean>()
    
    // In-memory cache for package inventory
    @Volatile
    private var cachedAppList: List<Map<String, Any?>>? = null
    private var lastCacheTimestamp: Long = 0
    private val cacheTtlMs = 60_000L // 60 seconds default TTL (event-driven invalidated on package changes)

    // Health state
    @Volatile
    private var healthStatus: String = "VALID"
    @Volatile
    private var lastErrorMessage: String? = null
    @Volatile
    private var lastSuccessfulCollectionMs: Long = 0

    private var isReceiverRegistered = false
    private var onPackageChangeListener: (() -> Unit)? = null

    private val packageChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            invalidateCache()
            onPackageChangeListener?.invoke()
        }
    }

    init {
        registerPackageReceiver()
    }

    fun getHealth(): Map<String, Any?> {
        return mapOf(
            "status" to healthStatus,
            "message" to (lastErrorMessage ?: "Operating nominally"),
            "sourceApi" to "PackageManager.getInstalledPackages",
            "lastSuccessTimestampMs" to lastSuccessfulCollectionMs,
            "cachedAppCount" to (cachedAppList?.size ?: 0)
        )
    }

    fun setOnPackageChangeListener(listener: () -> Unit) {
        onPackageChangeListener = listener
    }

    @Synchronized
    fun registerPackageReceiver() {
        if (isReceiverRegistered) return
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_PACKAGE_ADDED)
                addAction(Intent.ACTION_PACKAGE_REMOVED)
                addAction(Intent.ACTION_PACKAGE_REPLACED)
                addDataScheme("package")
            }
            context.registerReceiver(packageChangeReceiver, filter)
            isReceiverRegistered = true
        } catch (e: Exception) {
            lastErrorMessage = "PackageReceiver registration warning: ${e.message}"
        }
    }

    @Synchronized
    fun unregisterPackageReceiver() {
        if (!isReceiverRegistered) return
        try {
            context.unregisterReceiver(packageChangeReceiver)
            isReceiverRegistered = false
        } catch (_: Exception) {
            // Safe cleanup
        }
    }

    fun invalidateCache() {
        cachedAppList = null
        lastCacheTimestamp = 0
    }

    fun getInstalledAppPermissions(forceRefresh: Boolean = false): List<Map<String, Any?>> {
        val now = System.currentTimeMillis()
        if (!forceRefresh && cachedAppList != null && (now - lastCacheTimestamp < cacheTtlMs)) {
            return cachedAppList!!
        }

        val result = mutableListOf<Map<String, Any?>>()
        val pm = context.packageManager

        try {
            val flags = PackageManager.GET_PERMISSIONS.toLong()
            val packages: List<PackageInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(flags))
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)
            }

            val appOpsManager = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager

            for (pkg in packages) {
                val appInfo = pkg.applicationInfo ?: continue
                val packageName = pkg.packageName ?: continue

                val appName = try {
                    pm.getApplicationLabel(appInfo).toString()
                } catch (_: Exception) {
                    packageName
                }

                val isSystemApp = ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0) ||
                        ((appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0)
                val isEnabled = appInfo.enabled
                val uid = appInfo.uid
                val targetSdkVersion = appInfo.targetSdkVersion
                val minSdkVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    appInfo.minSdkVersion
                } else {
                    0
                }
                val appCategory = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appInfo.category
                } else {
                    -1
                }

                val versionName = pkg.versionName ?: ""
                val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    pkg.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    pkg.versionCode.toLong()
                }
                val firstInstallTime = pkg.firstInstallTime
                val lastUpdateTime = pkg.lastUpdateTime

                val installerPackage = try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        pm.getInstallSourceInfo(packageName).installingPackageName ?: ""
                    } else {
                        @Suppress("DEPRECATION")
                        pm.getInstallerPackageName(packageName) ?: ""
                    }
                } catch (_: Exception) {
                    ""
                }

                val requestedPermissions = pkg.requestedPermissions?.toList() ?: emptyList()
                val requestedFlags = pkg.requestedPermissionsFlags

                val grantedPermissions = mutableListOf<String>()
                val deniedPermissions = mutableListOf<String>()
                val dangerousGrantedPermissions = mutableListOf<String>()
                val dangerousRequestedPermissions = mutableListOf<String>()

                if (requestedFlags != null && requestedFlags.size == requestedPermissions.size) {
                    for (i in requestedPermissions.indices) {
                        val perm = requestedPermissions[i]
                        val isGranted = (requestedFlags[i] and PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0
                        val isDangerous = isDangerousPermissionDynamic(pm, perm)

                        if (isDangerous) {
                            dangerousRequestedPermissions.add(perm)
                        }

                        if (isGranted) {
                            grantedPermissions.add(perm)
                            if (isDangerous) {
                                dangerousGrantedPermissions.add(perm)
                            }
                        } else {
                            deniedPermissions.add(perm)
                        }
                    }
                } else {
                    // Fallback to checkPermission
                    for (perm in requestedPermissions) {
                        val isGranted = try {
                            pm.checkPermission(perm, packageName) == PackageManager.PERMISSION_GRANTED
                        } catch (_: Exception) {
                            false
                        }
                        val isDangerous = isDangerousPermissionDynamic(pm, perm)

                        if (isDangerous) {
                            dangerousRequestedPermissions.add(perm)
                        }

                        if (isGranted) {
                            grantedPermissions.add(perm)
                            if (isDangerous) {
                                dangerousGrantedPermissions.add(perm)
                            }
                        } else {
                            deniedPermissions.add(perm)
                        }
                    }
                }

                // Check per-app special AppOps
                val hasOverlayOp = checkAppOp(appOpsManager, AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW, uid, packageName)
                val hasUsageOp = checkAppOp(appOpsManager, AppOpsManager.OPSTR_GET_USAGE_STATS, uid, packageName)

                result.add(
                    mapOf(
                        "appName" to appName,
                        "packageName" to packageName,
                        "isSystemApp" to isSystemApp,
                        "isEnabled" to isEnabled,
                        "uid" to uid,
                        "targetSdkVersion" to targetSdkVersion,
                        "minSdkVersion" to minSdkVersion,
                        "versionName" to versionName,
                        "versionCode" to versionCode,
                        "firstInstallTime" to firstInstallTime,
                        "lastUpdateTime" to lastUpdateTime,
                        "installerPackage" to installerPackage,
                        "requestedPermissions" to requestedPermissions,
                        "grantedPermissions" to grantedPermissions,
                        "deniedPermissions" to deniedPermissions,
                        "dangerousGrantedPermissions" to dangerousGrantedPermissions,
                        "dangerousRequestedPermissions" to dangerousRequestedPermissions,
                        "hasOverlayOp" to hasOverlayOp,
                        "hasUsageAccessOp" to hasUsageOp,
                        "appCategory" to appCategory
                    )
                )
            }

            healthStatus = "VALID"
            lastErrorMessage = null
            lastSuccessfulCollectionMs = now
        } catch (e: Exception) {
            healthStatus = if (e is SecurityException) "RESTRICTED" else "ERROR"
            lastErrorMessage = e.message ?: "Failed to query PackageManager"
        }

        cachedAppList = result
        lastCacheTimestamp = now
        return result
    }

    /**
     * Dynamically determines whether a permission is dangerous by querying
     * Android's PackageManager permission protection level.
     * 
     * Never uses hardcoded string matching.
     */
    private fun isDangerousPermissionDynamic(pm: PackageManager, permission: String): Boolean {
        return permissionProtectionCache.getOrPut(permission) {
            try {
                val permInfo = pm.getPermissionInfo(permission, 0)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    (permInfo.protection and PermissionInfo.PROTECTION_MASK_BASE) == PermissionInfo.PROTECTION_DANGEROUS
                } else {
                    @Suppress("DEPRECATION")
                    (permInfo.protectionLevel and PermissionInfo.PROTECTION_MASK_BASE) == PermissionInfo.PROTECTION_DANGEROUS
                }
            } catch (_: Exception) {
                // Not a system-defined permission or unavailable
                false
            }
        }
    }

    private fun checkAppOp(appOpsManager: AppOpsManager?, opStr: String, uid: Int, packageName: String): Boolean? {
        if (appOpsManager == null) return null
        return try {
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOpsManager.unsafeCheckOpNoThrow(opStr, uid, packageName)
            } else {
                @Suppress("DEPRECATION")
                appOpsManager.checkOpNoThrow(opStr, uid, packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            null
        }
    }
}