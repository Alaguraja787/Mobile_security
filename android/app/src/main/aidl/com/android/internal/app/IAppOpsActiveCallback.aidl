package com.android.internal.app;

/**
 * Android 14/15/16 (API 36) compatible callback interface for AppOps active state transitions.
 * Transaction code 1 (FIRST_CALL_TRANSACTION).
 */
oneway interface IAppOpsActiveCallback {
    void opActiveChanged(
        int op, 
        int uid, 
        String packageName, 
        String attributionTag, 
        int virtualDeviceId, 
        boolean active, 
        int attributionFlags, 
        int attributionChainId
    );
}
