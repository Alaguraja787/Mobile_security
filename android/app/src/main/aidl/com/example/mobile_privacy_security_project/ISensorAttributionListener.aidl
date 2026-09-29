package com.example.mobile_privacy_security_project;

/**
 * IPC callback from Shizuku UserService to Privacy Sentinel application.
 */
oneway interface ISensorAttributionListener {
    void onSensorEvent(String eventJson);
}
