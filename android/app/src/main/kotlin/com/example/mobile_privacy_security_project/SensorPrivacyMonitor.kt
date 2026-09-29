package com.example.mobile_privacy_security_project

import android.content.Context
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Monitors hardware sensor privacy states (Camera and Microphone) at the device level.
 * 
 * Frequency Tiers:
 * - EVENT-DRIVEN: Camera hardware availability (CameraManager.AvailabilityCallback)
 * - EVENT-DRIVEN & PERIODIC: Microphone recording configurations (AudioManager.AudioRecordingCallback on API 29+)
 * 
 * Important Privacy & Platform Notice:
 * - Android does NOT expose which specific third-party application is currently recording audio or 
 *   using the camera to unprivileged applications.
 * - Therefore, this collector reports DEVICE-LEVEL hardware occupancy (cameraHardwareInUse, 
 *   microphoneHardwareInUse) and never invents app-level attribution.
 */
class SensorPrivacyMonitor(
    private val context: Context
) {

    // Health state
    @Volatile
    private var healthStatus: String = "UNAVAILABLE"
    @Volatile
    private var lastErrorMessage: String? = null
    @Volatile
    private var lastSuccessfulCollectionMs: Long = 0

    private val unavailableCameraIds = mutableSetOf<String>()

    private val cameraCallback = object : CameraManager.AvailabilityCallback() {
        override fun onCameraAvailable(cameraId: String) {
            synchronized(unavailableCameraIds) {
                unavailableCameraIds.remove(cameraId)
            }
        }

        override fun onCameraUnavailable(cameraId: String) {
            synchronized(unavailableCameraIds) {
                unavailableCameraIds.add(cameraId)
            }
        }
    }

    @Volatile
    private var isCameraRegistered: Boolean = false

    @Volatile
    private var isMicrophoneInUseEvent: Boolean = false
    @Volatile
    private var activeRecordingsCountEvent: Int = 0

    private var audioRecordingCallback: AudioManager.AudioRecordingCallback? = null
    @Volatile
    private var isAudioCallbackRegistered: Boolean = false

    init {
        registerCameraCallback()
        registerAudioCallback()
    }

    @Synchronized
    fun registerCameraCallback() {
        if (isCameraRegistered) return
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        if (cameraManager == null) {
            isCameraRegistered = false
            healthStatus = "UNAVAILABLE"
            lastErrorMessage = "Camera service unavailable on this device"
            return
        }
        try {
            cameraManager.registerAvailabilityCallback(cameraCallback, Handler(Looper.getMainLooper()))
            isCameraRegistered = true
            val requiresAudioCallback = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager == null) {
                healthStatus = "UNAVAILABLE"
                lastErrorMessage = "Audio service unavailable on this device"
            } else if (requiresAudioCallback && !isAudioCallbackRegistered) {
                if (healthStatus != "RESTRICTED" && healthStatus != "ERROR") {
                    healthStatus = "UNAVAILABLE"
                }
            } else {
                healthStatus = "VALID"
                lastErrorMessage = null
            }
        } catch (e: SecurityException) {
            isCameraRegistered = false
            healthStatus = "RESTRICTED"
            lastErrorMessage = "Camera callback registration restricted: ${e.message}"
        } catch (e: Exception) {
            isCameraRegistered = false
            healthStatus = "ERROR"
            lastErrorMessage = "Camera callback registration failed: ${e.message}"
        }
    }

    @Synchronized
    fun registerAudioCallback() {
        if (isAudioCallbackRegistered) return
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager == null) {
            healthStatus = "UNAVAILABLE"
            lastErrorMessage = "Audio service unavailable on this device"
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                audioRecordingCallback = object : AudioManager.AudioRecordingCallback() {
                    override fun onRecordingConfigChanged(configs: List<AudioRecordingConfiguration>) {
                        activeRecordingsCountEvent = configs.size
                        isMicrophoneInUseEvent = configs.isNotEmpty()
                    }
                }
                audioManager.registerAudioRecordingCallback(audioRecordingCallback!!, Handler(Looper.getMainLooper()))
                isAudioCallbackRegistered = true
                if (isCameraRegistered) {
                    healthStatus = "VALID"
                    lastErrorMessage = null
                } else if (healthStatus != "RESTRICTED" && healthStatus != "ERROR") {
                    healthStatus = "UNAVAILABLE"
                }
            } catch (e: SecurityException) {
                isAudioCallbackRegistered = false
                healthStatus = "RESTRICTED"
                lastErrorMessage = "Audio recording callback registration restricted: ${e.message}"
            } catch (e: Exception) {
                isAudioCallbackRegistered = false
                healthStatus = "ERROR"
                lastErrorMessage = "Audio recording callback registration failed: ${e.message}"
            }
        } else {
            if (isCameraRegistered) {
                healthStatus = "VALID"
                lastErrorMessage = null
            }
        }
    }

    @Synchronized
    fun unregister() {
        if (isCameraRegistered) {
            try {
                val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                cameraManager?.unregisterAvailabilityCallback(cameraCallback)
            } catch (_: Exception) {
                // Safe cleanup
            } finally {
                isCameraRegistered = false
            }
        }
        if (isAudioCallbackRegistered && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioRecordingCallback != null && audioManager != null) {
                    audioManager.unregisterAudioRecordingCallback(audioRecordingCallback!!)
                }
            } catch (_: Exception) {
                // Safe cleanup
            } finally {
                isAudioCallbackRegistered = false
                audioRecordingCallback = null
            }
        }
    }

    fun isCameraUnavailable(): Boolean? = if (isCameraRegistered) synchronized(unavailableCameraIds) { unavailableCameraIds.isNotEmpty() } else null

    fun isCameraHardwareInUse(): Boolean? = null // AvailabilityCallback indicates availability, not verified in-use state

    /**
     * Inspects device-level audio recording state using AudioManager.
     * Available on API 24+ via getActiveRecordingConfigurations().
     */
    fun isMicrophoneHardwareInUse(): Boolean? {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager == null) {
            healthStatus = "UNAVAILABLE"
            lastErrorMessage = "Audio service unavailable on this device"
            return null
        }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val configs: List<AudioRecordingConfiguration> = audioManager.activeRecordingConfigurations
                configs.isNotEmpty() || isMicrophoneInUseEvent
            } else {
                audioManager.mode == AudioManager.MODE_IN_CALL || audioManager.mode == AudioManager.MODE_IN_COMMUNICATION
            }
        } catch (e: SecurityException) {
            healthStatus = "RESTRICTED"
            lastErrorMessage = "Microphone hardware query restricted: ${e.message}"
            null
        } catch (e: Exception) {
            healthStatus = "ERROR"
            lastErrorMessage = "Microphone hardware query failed: ${e.message}"
            null
        }
    }

    fun getHealth(): Map<String, Any?> {
        val cm = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val requiresAudioCallback = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

        val status = when {
            healthStatus == "ERROR" -> "ERROR"
            healthStatus == "RESTRICTED" -> "RESTRICTED"
            cm == null || am == null -> "UNAVAILABLE"
            healthStatus == "UNAVAILABLE" -> "UNAVAILABLE"
            !isCameraRegistered -> "ERROR"
            requiresAudioCallback && !isAudioCallbackRegistered -> "ERROR"
            else -> healthStatus
        }
        val defaultMsg = when (status) {
            "ERROR" -> (lastErrorMessage ?: "Sensor callback registration or collection error")
            "RESTRICTED" -> (lastErrorMessage ?: "Sensor access restricted by security policy")
            "UNAVAILABLE" -> (lastErrorMessage ?: "Sensor monitoring capability unavailable")
            "VALID" -> "Operating nominally (Camera & Audio callbacks active)"
            else -> (lastErrorMessage ?: "Operating nominally")
        }
        return mapOf(
            "status" to status,
            "message" to (lastErrorMessage ?: defaultMsg),
            "sourceApi" to "CameraManager.AvailabilityCallback / AudioManager.AudioRecordingCallback",
            "lastSuccessTimestampMs" to lastSuccessfulCollectionMs,
            "cameraRegistered" to isCameraRegistered,
            "audioRegistered" to isAudioCallbackRegistered
        )
    }

    fun getSensorTelemetry(): Map<String, Any?> {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val requiresAudioCallback = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

        var isMicInUse: Boolean? = null
        var isMicMuted: Boolean? = null
        var audioMode = "UNKNOWN"
        var activeRecordingsCount: Int? = null
        var collectionExceptionOccurred = false

        if (cameraManager == null || audioManager == null) {
            healthStatus = "UNAVAILABLE"
            if (lastErrorMessage == null) {
                lastErrorMessage = if (cameraManager == null && audioManager == null) {
                    "Camera and Audio services unavailable on this device"
                } else if (cameraManager == null) {
                    "Camera service unavailable on this device"
                } else {
                    "Audio service unavailable on this device"
                }
            }
        } else if (!isCameraRegistered || (requiresAudioCallback && !isAudioCallbackRegistered)) {
            if (healthStatus != "RESTRICTED" && healthStatus != "UNAVAILABLE") {
                healthStatus = "ERROR"
                if (lastErrorMessage == null) {
                    lastErrorMessage = if (!isCameraRegistered) {
                        "Camera callback registration failed or is not active"
                    } else {
                        "Audio recording callback registration failed or is not active"
                    }
                }
            }
        }

        if (audioManager != null) {
            try {
                isMicInUse = isMicrophoneHardwareInUse()
                isMicMuted = audioManager.isMicrophoneMute
                audioMode = when (audioManager.mode) {
                    AudioManager.MODE_NORMAL -> "NORMAL"
                    AudioManager.MODE_RINGTONE -> "RINGTONE"
                    AudioManager.MODE_IN_CALL -> "IN_CALL"
                    AudioManager.MODE_IN_COMMUNICATION -> "IN_COMMUNICATION"
                    else -> "UNKNOWN"
                }

                activeRecordingsCount = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    try {
                        audioManager.activeRecordingConfigurations.size
                    } catch (e: SecurityException) {
                        healthStatus = "RESTRICTED"
                        lastErrorMessage = "Audio recording configurations restricted: ${e.message}"
                        collectionExceptionOccurred = true
                        null
                    } catch (e: Exception) {
                        healthStatus = "ERROR"
                        lastErrorMessage = "Audio recording configurations query failed: ${e.message}"
                        collectionExceptionOccurred = true
                        null
                    }
                } else {
                    if (isMicInUse == true) 1 else 0
                }
            } catch (e: SecurityException) {
                healthStatus = "RESTRICTED"
                lastErrorMessage = "Sensor telemetry query restricted: ${e.message}"
                collectionExceptionOccurred = true
            } catch (e: Exception) {
                healthStatus = "ERROR"
                lastErrorMessage = "Sensor telemetry query failed: ${e.message}"
                collectionExceptionOccurred = true
            }
        }

        val isRegistrationHealthy = isCameraRegistered && (!requiresAudioCallback || isAudioCallbackRegistered)

        val availability = when {
            healthStatus == "ERROR" -> "ERROR"
            healthStatus == "RESTRICTED" -> "RESTRICTED"
            cameraManager == null || audioManager == null -> "UNAVAILABLE"
            healthStatus == "UNAVAILABLE" -> "UNAVAILABLE"
            !isCameraRegistered -> "ERROR"
            requiresAudioCallback && !isAudioCallbackRegistered -> "ERROR"
            collectionExceptionOccurred -> "ERROR"
            !isRegistrationHealthy -> "ERROR"
            else -> "VALID"
        }

        if (availability == "VALID") {
            lastSuccessfulCollectionMs = System.currentTimeMillis()
            healthStatus = "VALID"
            lastErrorMessage = null
        }

        val isCamUnavailable = if (availability == "VALID") synchronized(unavailableCameraIds) { unavailableCameraIds.isNotEmpty() } else null
        val unavailCount = if (availability == "VALID") synchronized(unavailableCameraIds) { unavailableCameraIds.size } else null

        return mapOf(
            "cameraUnavailable" to isCamUnavailable,
            "cameraHardwareInUse" to null,
            "unavailableCamerasCount" to unavailCount,
            "microphoneHardwareInUse" to if (availability == "VALID") isMicInUse else null,
            "activeAudioRecordingsCount" to if (availability == "VALID") activeRecordingsCount else null,
            "isMicrophoneMuted" to if (availability == "VALID") isMicMuted else null,
            "audioMode" to if (availability == "VALID") audioMode else "UNKNOWN",
            "attributionScope" to "DEVICE_LEVEL_ONLY",
            "sensorAvailability" to availability
        )
    }
}


