package com.example.mobile_privacy_security_project

import android.app.KeyguardManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.FileObserver
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * Monitors photo, video, and file access/modifications across the device using MediaStore ContentObservers
 * and storage FileObservers.
 * 
 * Capabilities:
 * 1. Detects file, photo, and video access/creation events.
 * 2. Resolves actual file names (e.g. "IMG_2026.jpg", "Invoice.pdf").
 * 3. Identifies the responsible app via MediaStore OWNER_PACKAGE_NAME and UsageStats foreground correlation.
 * 4. Detects whether the device screen was LOCKED or screen was off at the time of access.
 * 5. Generates human-friendly explanations for notifications and dashboard tracking.
 * 6. Emits strongly-typed "sensor_access" events for Flutter consumption.
 */
class MediaFileAccessMonitor(
    private val context: Context
) {
    companion object {
        private const val TAG = "MediaFileAccessMonitor"
        private const val DEDUPLICATION_WINDOW_MS = 2500L
    }

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val eventListeners = CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()
    private val recentProcessedEvents = ConcurrentHashMap<String, Long>()
    private val activeFileObservers = mutableListOf<FileObserver>()

    @Volatile
    private var isWatching: Boolean = false

    private val keyguardManager by lazy {
        context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
    }

    private val powerManager by lazy {
        context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    }

    private val usageStatsManager by lazy {
        context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
    }

    private val contentObserver = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            super.onChange(selfChange, uri)
            if (uri == null) return
            backgroundExecutor.execute {
                handleUriChanged(uri)
            }
        }

        override fun onChange(selfChange: Boolean, uri: Uri?, flags: Int) {
            super.onChange(selfChange, uri, flags)
            if (uri == null) return
            backgroundExecutor.execute {
                handleUriChanged(uri)
            }
        }
    }

    fun addEventListener(listener: (Map<String, Any?>) -> Unit) {
        eventListeners.add(listener)
    }

    fun removeEventListener(listener: (Map<String, Any?>) -> Unit) {
        eventListeners.remove(listener)
    }

    @Synchronized
    fun startWatching() {
        if (isWatching) return
        val cr = context.contentResolver
        try {
            // Watch external images
            cr.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                contentObserver
            )
            // Watch external video
            cr.registerContentObserver(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                true,
                contentObserver
            )
            // Watch external audio / recordings
            cr.registerContentObserver(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                true,
                contentObserver
            )
            // Watch general files
            cr.registerContentObserver(
                MediaStore.Files.getContentUri("external"),
                true,
                contentObserver
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cr.registerContentObserver(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    true,
                    contentObserver
                )
            }

            setupFileObservers()

            isWatching = true
            Log.i(TAG, "MediaFileAccessMonitor registered successfully on MediaStore URIs & storage directories")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register MediaStore content observers: ${e.message}", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun setupFileObservers() {
        try {
            val rootDirs = mutableListOf<File>()
            val searchBases = listOfNotNull(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM),
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
                File(Environment.getExternalStorageDirectory(), "DCIM/Camera"),
                File(Environment.getExternalStorageDirectory(), "Pictures/Instagram"),
                File(Environment.getExternalStorageDirectory(), "Pictures/Screenshots"),
                File(Environment.getExternalStorageDirectory(), "Android/media/com.instagram.android"),
                File(Environment.getExternalStorageDirectory(), "Android/media/com.whatsapp")
            )

            for (base in searchBases) {
                if (!base.exists()) {
                    try { base.mkdirs() } catch (_: Throwable) {}
                }
                if (base.exists()) {
                    rootDirs.add(base)
                    try {
                        base.listFiles()?.filter { it.isDirectory && !it.name.startsWith(".") }?.forEach { sub ->
                            rootDirs.add(sub)
                        }
                    } catch (_: Throwable) {}
                }
            }

            val flags = FileObserver.OPEN or FileObserver.CLOSE_WRITE or FileObserver.CREATE or FileObserver.MOVED_TO

            for (dir in rootDirs.distinctBy { it.absolutePath }) {
                try {
                    val observer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        object : FileObserver(dir, flags) {
                            override fun onEvent(event: Int, path: String?) {
                                if (!path.isNullOrBlank()) {
                                    backgroundExecutor.execute {
                                        handleFileSystemEvent(dir, path)
                                    }
                                }
                            }
                        }
                    } else {
                        object : FileObserver(dir.absolutePath, flags) {
                            override fun onEvent(event: Int, path: String?) {
                                if (!path.isNullOrBlank()) {
                                    backgroundExecutor.execute {
                                        handleFileSystemEvent(dir, path)
                                    }
                                }
                            }
                        }
                    }
                    observer.startWatching()
                    activeFileObservers.add(observer)
                } catch (e: Exception) {
                    Log.w(TAG, "FileObserver could not watch ${dir.absolutePath}: ${e.message}")
                }
            }
            Log.i(TAG, "FileObserver initialized on ${activeFileObservers.size} directories/subdirectories")
        } catch (e: Exception) {
            Log.w(TAG, "setupFileObservers error: ${e.message}")
        }
    }

    @Synchronized
    fun stopWatching() {
        if (!isWatching) return
        try {
            context.contentResolver.unregisterContentObserver(contentObserver)
        } catch (_: Exception) {}

        for (observer in activeFileObservers) {
            try { observer.stopWatching() } catch (_: Exception) {}
        }
        activeFileObservers.clear()

        isWatching = false
        recentProcessedEvents.clear()
        Log.i(TAG, "MediaFileAccessMonitor stopped watching")
    }

    /**
     * Checks whether the device is currently screen locked or display is turned off.
     */
    fun isDeviceScreenLocked(): Boolean {
        val isLocked = keyguardManager?.isKeyguardLocked ?: false
        val isInteractive = powerManager?.isInteractive ?: true
        return isLocked || !isInteractive
    }

    private fun handleFileSystemEvent(dir: File, fileName: String) {
        val lower = fileName.lowercase()
        // Ignore hidden, transient, or thumbnail files
        if (fileName.startsWith(".") || fileName.endsWith(".tmp") || fileName.endsWith(".crdownload") || fileName.endsWith(".nomedia") || fileName.endsWith(".pending") || fileName.endsWith(".trashed")) return

        val isImage = lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".png") || lower.endsWith(".webp") || lower.endsWith(".gif") || lower.endsWith(".heic")
        val isVideo = lower.endsWith(".mp4") || lower.endsWith(".mkv") || lower.endsWith(".webm") || lower.endsWith(".mov") || lower.endsWith(".3gp")
        val isAudio = lower.endsWith(".mp3") || lower.endsWith(".wav") || lower.endsWith(".m4a") || lower.endsWith(".aac") || lower.endsWith(".ogg")
        val isDoc = lower.endsWith(".pdf") || lower.endsWith(".docx") || lower.endsWith(".xlsx") || lower.endsWith(".txt")

        if (!isImage && !isVideo && !isAudio && !isDoc) return

        val sensorType = when {
            isImage -> "PHOTOS"
            isVideo -> "VIDEOS"
            isAudio -> "AUDIO_FILES"
            else -> "FILES"
        }

        val packageName = getActiveOrForegroundPackage()
        if (packageName == context.packageName || packageName == "com.android.systemui") return

        emitMediaAccessEvent(
            sensorType = sensorType,
            fileName = fileName,
            mimeType = resolveMimeType(fileName),
            packageName = packageName
        )
    }

    private fun handleUriChanged(uri: Uri) {
        val isLocked = isDeviceScreenLocked()
        val mediaDetails = queryMediaDetails(uri) ?: queryRecentMediaFallback(uri) ?: return

        val fileName = mediaDetails.displayName ?: "File"
        val mimeType = mediaDetails.mimeType ?: "application/octet-stream"
        var packageName = mediaDetails.ownerPackage
        val sensorType = when {
            mimeType.startsWith("image/") -> "PHOTOS"
            mimeType.startsWith("video/") -> "VIDEOS"
            mimeType.startsWith("audio/") -> "AUDIO_FILES"
            else -> "FILES"
        }

        // Correlate with foreground app if owner package is not provided by MediaStore
        if (packageName.isNullOrBlank()) {
            packageName = getActiveOrForegroundPackage()
        }

        // Avoid self-reporting our own app's cache or temp writes
        if (packageName == context.packageName) {
            return
        }

        emitMediaAccessEvent(
            sensorType = sensorType,
            fileName = fileName,
            mimeType = mimeType,
            packageName = packageName
        )
    }

    private fun emitMediaAccessEvent(
        sensorType: String,
        fileName: String,
        mimeType: String,
        packageName: String?
    ) {
        val now = System.currentTimeMillis()
        val isLocked = isDeviceScreenLocked()

        // Clean up old deduplication cache entries
        recentProcessedEvents.entries.removeIf { now - it.value > 10000L }

        val dedupKey = "${sensorType}_${fileName}_$packageName"
        val lastSeen = recentProcessedEvents[dedupKey]
        if (lastSeen != null && (now - lastSeen) < DEDUPLICATION_WINDOW_MS) {
            return
        }
        recentProcessedEvents[dedupKey] = now

        val appName = resolvePackageToAppName(packageName)
        val timestamp = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
        val eventId = "MEDIA_${sensorType}_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}"

        val appLabel = appName ?: packageName ?: "An application"
        val humanExplanation = if (isLocked) {
            "⚠️ Suspicious Background Access: $appLabel accessed $sensorType ($fileName) while your screen was locked!"
        } else {
            "$appLabel accessed $sensorType: $fileName"
        }

        // CRITICAL FIX: "type" is "sensor_access" so it routes directly to sensorAccessStream
        val eventMap = mapOf(
            "type" to "sensor_access",
            "sensor" to sensorType,
            "state" to "ACTIVE",
            "fileName" to fileName,
            "mimeType" to mimeType,
            "packageName" to packageName,
            "appName" to appName,
            "isScreenLocked" to isLocked,
            "timestamp" to timestamp,
            "source" to "MEDIA_STORE",
            "confidence" to if (packageName != null) "VERIFIED" else "DERIVED",
            "attributionScope" to if (packageName != null) "APP_LEVEL" else "DEVICE_LEVEL",
            "humanExplanation" to humanExplanation,
            "eventId" to eventId
        )

        Log.i(TAG, "MEDIA_ACCESS_EVENT: sensor=$sensorType file=$fileName pkg=$packageName locked=$isLocked msg='$humanExplanation'")

        mainHandler.post {
            for (listener in eventListeners) {
                try {
                    listener(eventMap)
                } catch (e: Exception) {
                    Log.e(TAG, "Error notifying media event listener: ${e.message}")
                }
            }
        }
    }

    private data class MediaItem(
        val displayName: String?,
        val mimeType: String?,
        val ownerPackage: String?
    )

    private fun queryMediaDetails(uri: Uri): MediaItem? {
        val lastSegment = uri.lastPathSegment
        val isNumericId = lastSegment?.toLongOrNull() != null
        if (!isNumericId) {
            // Collection URI: delegate to queryRecentMediaFallback to sort by DATE_MODIFIED DESC
            return queryRecentMediaFallback(uri)
        }

        val cr = context.contentResolver
        val projection = mutableListOf(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
        }

        try {
            cr.query(uri, projection.toTypedArray(), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    val mimeIdx = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                    val ownerIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        cursor.getColumnIndex(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
                    } else -1

                    val displayName = if (nameIdx != -1) cursor.getString(nameIdx) else null
                    val mimeType = if (mimeIdx != -1) cursor.getString(mimeIdx) else null
                    val ownerPackage = if (ownerIdx != -1) cursor.getString(ownerIdx) else null

                    if (!displayName.isNullOrBlank() || !mimeType.isNullOrBlank()) {
                        return MediaItem(displayName, mimeType, ownerPackage)
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun queryRecentMediaFallback(baseUri: Uri): MediaItem? {
        val cr = context.contentResolver
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_MODIFIED
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
        }

        val sortOrder = "${MediaStore.MediaColumns.DATE_MODIFIED} DESC, ${MediaStore.MediaColumns._ID} DESC LIMIT 1"
        try {
            cr.query(baseUri, projection.toTypedArray(), null, null, sortOrder)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    val mimeIdx = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                    val ownerIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        cursor.getColumnIndex(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
                    } else -1
                    val dateModIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)

                    val dateMod = if (dateModIdx != -1) cursor.getLong(dateModIdx) else 0L
                    val nowSec = System.currentTimeMillis() / 1000L

                    val displayName = if (nameIdx != -1) cursor.getString(nameIdx) else null
                    val mimeType = if (mimeIdx != -1) cursor.getString(mimeIdx) else null
                    val ownerPackage = if (ownerIdx != -1) cursor.getString(ownerIdx) else null

                    if (!displayName.isNullOrBlank() || !mimeType.isNullOrBlank()) {
                        return MediaItem(displayName, mimeType, ownerPackage)
                    }

                    return MediaItem(displayName, mimeType, ownerPackage)
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun resolveMimeType(fileName: String): String {
        val lower = fileName.lowercase()
        return when {
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".webp") -> "image/webp"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".mp4") -> "video/mp4"
            lower.endsWith(".mkv") -> "video/x-matroska"
            lower.endsWith(".mp3") -> "audio/mpeg"
            lower.endsWith(".pdf") -> "application/pdf"
            else -> "application/octet-stream"
        }
    }

    /**
     * Finds the foreground app using UsageStatsManager.
     */
    fun getActiveOrForegroundPackage(): String? {
        val usm = usageStatsManager ?: return null
        val endTime = System.currentTimeMillis()
        val startTime = endTime - 10000L // last 10 seconds

        try {
            val usageEvents = usm.queryEvents(startTime, endTime)
            val event = UsageEvents.Event()
            var lastForegroundPackage: String? = null
            var lastEventTime: Long = 0

            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED && event.timeStamp > lastEventTime) {
                    val pkg = event.packageName
                    if (!pkg.isNullOrBlank() && pkg != context.packageName) {
                        lastForegroundPackage = pkg
                        lastEventTime = event.timeStamp
                    }
                }
            }
            if (lastForegroundPackage != null) {
                return lastForegroundPackage
            }

            // Fallback to top package in queryUsageStats
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, endTime)
            return stats
                ?.filter { it.packageName != context.packageName }
                ?.maxByOrNull { it.lastTimeUsed }
                ?.packageName
        } catch (_: Exception) {}
        return null
    }

    fun resolvePackageToAppName(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        return try {
            val pm = context.packageManager
            val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(packageName, 0)
            }
            pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            packageName
        }
    }
}
