"""
Feature Schema v1 for Privacy Sentinel AI - Local Intelligence (Phase 2).

Defines the canonical, deterministic 32-feature contract matching the Flutter/Dart
FeatureSchema.v1 specification.
"""

from typing import Dict, List, Any, Optional

FEATURE_SCHEMA_VERSION = "1.0.0"

FEATURE_DEFINITIONS: List[Dict[str, Any]] = [
    # Category 1: Application Identity & Installation
    {"index": 0, "name": "app_is_system_app", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "app_identity"},
    {"index": 1, "name": "app_is_enabled", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "app_identity"},
    {"index": 2, "name": "app_target_sdk_version", "type": "numeric", "min": 0.0, "max": 36.0, "norm": "min_max", "cat": "app_identity"},
    {"index": 3, "name": "app_min_sdk_version", "type": "numeric", "min": 0.0, "max": 36.0, "norm": "min_max", "cat": "app_identity"},
    {"index": 4, "name": "app_age_days", "type": "numeric", "min": 0.0, "max": None, "norm": "standard", "cat": "app_identity"},

    # Category 2: Dynamic Permissions & Dangerous Classification
    {"index": 5, "name": "app_requested_permissions_count", "type": "count", "min": 0.0, "max": 200.0, "norm": "standard", "cat": "permissions"},
    {"index": 6, "name": "app_granted_permissions_count", "type": "count", "min": 0.0, "max": 200.0, "norm": "standard", "cat": "permissions"},
    {"index": 7, "name": "app_denied_permissions_count", "type": "count", "min": 0.0, "max": 200.0, "norm": "standard", "cat": "permissions"},
    {"index": 8, "name": "app_dangerous_granted_count", "type": "count", "min": 0.0, "max": 50.0, "norm": "standard", "cat": "permissions"},
    {"index": 9, "name": "app_dangerous_requested_count", "type": "count", "min": 0.0, "max": 50.0, "norm": "standard", "cat": "permissions"},
    {"index": 10, "name": "app_perm_camera_granted", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "permissions"},
    {"index": 11, "name": "app_perm_record_audio_granted", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "permissions"},
    {"index": 12, "name": "app_perm_fine_location_granted", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "permissions"},
    {"index": 13, "name": "app_perm_contacts_granted", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "permissions"},
    {"index": 14, "name": "app_perm_storage_granted", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "permissions"},
    {"index": 15, "name": "app_perm_sms_granted", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "permissions"},

    # Category 3: Special Capabilities & AppOps
    {"index": 16, "name": "app_has_overlay_op", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "app_ops"},
    {"index": 17, "name": "app_has_usage_access_op", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "app_ops"},

    # Category 4: Usage & Foreground Dynamics
    {"index": 18, "name": "app_foreground_duration_ms_24h", "type": "numeric", "min": 0.0, "max": 86400000.0, "norm": "log_scale", "cat": "usage"},
    {"index": 19, "name": "app_foreground_transitions_24h", "type": "count", "min": 0.0, "max": 10000.0, "norm": "standard", "cat": "usage"},
    {"index": 20, "name": "app_is_currently_foreground", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "usage"},
    {"index": 21, "name": "app_is_recently_used", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "usage"},

    # Category 5: Per-Application Network Traffic
    {"index": 22, "name": "app_upload_bytes_24h", "type": "numeric", "min": 0.0, "max": None, "norm": "log_scale", "cat": "network"},
    {"index": 23, "name": "app_download_bytes_24h", "type": "numeric", "min": 0.0, "max": None, "norm": "log_scale", "cat": "network"},

    # Category 6: Device Environment & Security Context
    {"index": 24, "name": "device_screen_locked", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "device_security"},
    {"index": 25, "name": "device_screen_on", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "device_security"},
    {"index": 26, "name": "device_is_secure", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "device_security"},
    {"index": 27, "name": "device_vpn_active", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "device_security"},
    {"index": 28, "name": "device_developer_options_enabled", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "device_security"},
    {"index": 29, "name": "device_adb_enabled", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "device_security"},
    {"index": 30, "name": "device_accessibility_enabled", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "device_security"},
    {"index": 31, "name": "device_root_heuristic_detected", "type": "boolean", "min": 0.0, "max": 1.0, "norm": "none", "cat": "device_security"},
]

FEATURE_NAMES: List[str] = [f["name"] for f in FEATURE_DEFINITIONS]
FEATURE_COUNT: int = len(FEATURE_DEFINITIONS) # 32 semantic features
MISSING_MASK_COUNT: int = FEATURE_COUNT # 32 missingness indicators
MODEL_INPUT_DIMENSION: int = FEATURE_COUNT + MISSING_MASK_COUNT # 64 model input values
MODEL_INPUT_SHAPE: List[int] = [1, MODEL_INPUT_DIMENSION]
NAME_TO_INDEX: Dict[str, int] = {f["name"]: f["index"] for f in FEATURE_DEFINITIONS}
