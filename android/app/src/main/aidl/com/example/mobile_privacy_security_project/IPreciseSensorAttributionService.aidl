package com.example.mobile_privacy_security_project;

import com.example.mobile_privacy_security_project.ISensorAttributionListener;

/**
 * IPC control interface for Shizuku PreciseSensorAttributionUserService.
 */
interface IPreciseSensorAttributionService {
    void registerListener(ISensorAttributionListener listener);
    void unregisterListener(ISensorAttributionListener listener);
    void startWatching();
    void stopWatching();
    boolean isWatching();
    void destroy();
    String ping();
    boolean revokeSensorPermission(String packageName, String permissionName);
    boolean grantSensorPermission(String packageName, String permissionName);
    boolean checkSensorPermission(String packageName, String permissionName);
    String executeAction(String actionJson);
}
