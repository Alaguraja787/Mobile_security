package com.example.mobile_privacy_security_project


import android.app.usage.UsageStatsManager
import android.content.Context
import android.app.usage.UsageStats


class AppUsageMonitor(

    private val context: Context

) {


    fun getRunningApps(): List<Map<String, Any>> {


        val result =
            mutableListOf<Map<String, Any>>()


        val usageManager =

            context.getSystemService(

                Context.USAGE_STATS_SERVICE

            ) as UsageStatsManager



        val endTime =
            System.currentTimeMillis()


        val startTime =
            endTime - 1000 * 60 * 10



        val stats: List<UsageStats> =

            usageManager.queryUsageStats(

                UsageStatsManager.INTERVAL_DAILY,

                startTime,

                endTime

            )



        for(app in stats){


            result.add(

                mapOf(

                    "packageName" to app.packageName,


                    "lastUsed" to app.lastTimeUsed,


                    "totalTime" to app.totalTimeInForeground

                )

            )

        }


        return result

    }


}