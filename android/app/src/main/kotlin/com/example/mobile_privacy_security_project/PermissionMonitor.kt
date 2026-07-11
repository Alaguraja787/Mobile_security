package com.example.mobile_privacy_security_project

import android.content.Context
import android.content.pm.PackageManager


class PermissionMonitor(
    private val context: Context
) {


    fun getInstalledAppPermissions(): List<Map<String, Any>> {


        val result =
            mutableListOf<Map<String, Any>>()


        val pm =
            context.packageManager


        val packages =
            pm.getInstalledPackages(
                PackageManager.GET_PERMISSIONS
            )


        for(pkg in packages){


            val appInfo =
                pkg.applicationInfo


            val appName =
                if(appInfo != null){

                    pm.getApplicationLabel(
                        appInfo
                    ).toString()

                } else {

                    pkg.packageName

                }



            val permissions =
                pkg.requestedPermissions
                    ?.toList()
                    ?: emptyList()



            result.add(

                mapOf(

                    "appName" to appName,

                    "packageName" to pkg.packageName,

                    "permissions" to permissions

                )

            )


        }


        return result


    }


}