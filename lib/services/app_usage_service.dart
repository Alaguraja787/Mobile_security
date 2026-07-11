package com.example.mobile_privacy_security_project


import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity: FlutterActivity() {


    private val CHANNEL =
        "privacy_sentinel"


    override fun configureFlutterEngine(

        flutterEngine: FlutterEngine

    ) {


        super.configureFlutterEngine(
            flutterEngine
        )


        MethodChannel(

            flutterEngine.dartExecutor.binaryMessenger,

            CHANNEL

        ).setMethodCallHandler {


            call,

            result ->


            when(call.method){



                "getPermissions" -> {


                    val monitor =

                        PermissionMonitor(this)



                    result.success(

                        monitor
                            .getInstalledAppPermissions()

                    )


                }




                "getAppUsage" -> {


                    val usage =

                        AppUsageMonitor(this)



                    result.success(

                        usage.getRunningApps()

                    )


                }



                else -> {


                    result.notImplemented()


                }


            }


        }


    }


}