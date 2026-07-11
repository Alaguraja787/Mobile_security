package com.example.mobile_privacy_security_project


import android.net.TrafficStats



class NetworkMonitor {



fun getTotalUploadBytes():Long{


return TrafficStats.getTotalTxBytes()


}



fun getTotalDownloadBytes():Long{


return TrafficStats.getTotalRxBytes()


}



}