"""
Data Ingestion Service for loading real Android device telemetry exports (JSON / CSV).
"""

import json
import os
from typing import List, Dict, Any, Optional
import pandas as pd
from feature_schema import FEATURE_NAMES

class DataIngestionService:
    def load_json_records(self, file_path: str) -> List[Dict[str, Any]]:
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"Telemetry export file not found: {file_path}")

        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        if not isinstance(data, list):
            raise ValueError("Expected JSON file to contain a list of records.")

        return data

    def json_records_to_dataframe(self, records: List[Dict[str, Any]]) -> pd.DataFrame:
        rows = []
        for rec in records:
            feat_vec = rec.get("featureVector", {})
            values = feat_vec.get("values", [])
            row = {
                "record_id": rec.get("recordId"),
                "package_name": rec.get("packageName"),
                "timestamp": rec.get("timestamp"),
                "label": rec.get("label"),
            }
            for v in values:
                fname = v.get("featureName")
                num_val = v.get("numericValue")
                if fname:
                    row[fname] = num_val
            rows.append(row)

        return pd.DataFrame(rows)
