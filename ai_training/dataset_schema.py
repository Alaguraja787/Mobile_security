"""
Dataset Schema and Data Contract for Real Android Telemetry in Python.
"""

from typing import Dict, List, Any

DATASET_SCHEMA_VERSION = "1.0.0"

REQUIRED_METADATA_FIELDS = [
    "record_id",
    "device_id_hash",
    "android_version",
    "sdk_int",
    "timestamp",
    "package_name",
    "collector_health_status",
]
