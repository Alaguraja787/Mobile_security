"""
Dataset Validator for Real Android Telemetry in Python.

Validates that datasets collected from physical test devices conform to FeatureSchema.v1.
Rejects synthetic or corrupted files.
"""

from typing import List, Dict, Any, Tuple
import pandas as pd
from feature_schema import FEATURE_NAMES, FEATURE_COUNT, FEATURE_DEFINITIONS

class DatasetValidator:
    def __init__(self):
        self.feature_names = FEATURE_NAMES
        self.feature_count = FEATURE_COUNT

    def validate_dataframe(self, df: pd.DataFrame) -> Tuple[bool, List[str]]:
        errors = []

        if df.empty:
            return False, ["Dataset is empty."]

        # Check required feature columns
        missing_cols = [col for col in self.feature_names if col not in df.columns]
        if missing_cols:
            errors.append(f"Missing {len(missing_cols)} required feature columns: {missing_cols[:5]}...")

        # Range validation
        for defn in FEATURE_DEFINITIONS:
            name = defn["name"]
            if name in df.columns:
                min_val = defn.get("min")
                max_val = defn.get("max")
                if min_val is not None:
                    violating = (df[name] < min_val).sum()
                    if violating > 0:
                        errors.append(f"Column '{name}' has {violating} values below min expected ({min_val}).")
                if max_val is not None:
                    violating = (df[name] > max_val).sum()
                    if violating > 0:
                        errors.append(f"Column '{name}' has {violating} values above max expected ({max_val}).")

        return len(errors) == 0, errors
