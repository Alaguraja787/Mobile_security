package com.example.mobile_privacy_security_project



import android.content.Context

import java.time.LocalDateTime



class AndroidTelemetryCollector(

private val context:Context

){



private val permissionMonitor=

PermissionMonitor(context)



private val deviceMonitor=

DeviceStateMonitor(context)



private val networkMonitor=

NetworkMonitor()





fun collectTelemetry():

Map<String,Any>{



val apps=

permissionMonitor

.getInstalledAppPermissions()



return mapOf(


"timestamp" to

LocalDateTime.now().toString(),



"screenLocked" to

deviceMonitor.isScreenLocked(),



"screenOn" to

deviceMonitor.isScreenOn(),



"uploadBytes" to

networkMonitor.getTotalUploadBytes(),



"downloadBytes" to

networkMonitor.getTotalDownloadBytes(),



"apps" to apps


)



}



}