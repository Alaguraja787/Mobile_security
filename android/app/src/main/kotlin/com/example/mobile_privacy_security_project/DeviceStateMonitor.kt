package com.example.mobile_privacy_security_project


import android.app.KeyguardManager
import android.content.Context
import android.os.PowerManager



class DeviceStateMonitor(

    private val context: Context

){



fun isScreenLocked():Boolean{


val keyguard =

context.getSystemService(

Context.KEYGUARD_SERVICE

) as KeyguardManager



return keyguard.isKeyguardLocked


}





fun isScreenOn():Boolean{


val power =

context.getSystemService(

Context.POWER_SERVICE

) as PowerManager



return power.isInteractive


}




}