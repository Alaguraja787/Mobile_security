"""
Offline ML Training Pipeline for Privacy Sentinel AI - Local Intelligence.

IMPORTANT:
This training pipeline is intentionally disabled until real telemetry is collected
from physical Android test devices. Do NOT run with synthetic data.
"""

import sys
import os
import json
import argparse
from typing import Optional, Dict, Any

from feature_schema import FEATURE_NAMES, FEATURE_COUNT, FEATURE_DEFINITIONS
from data_validator import DatasetValidator
from data_ingestion import DataIngestionService

def compute_normalization_params(df, feature_names):
    means = {}
    stds = {}
    mins = {}
    maxs = {}
    medians = {}
    iqrs = {}
    imputation_values = {}

    for f in feature_names:
        if f in df.columns:
            s = df[f].dropna()
            mean_val = float(s.mean()) if not s.empty else 0.0
            std_val = float(s.std()) if not s.empty and s.std() > 0 else 1.0
            min_val = float(s.min()) if not s.empty else 0.0
            max_val = float(s.max()) if not s.empty else 1.0
            med_val = float(s.median()) if not s.empty else 0.0
            q75, q25 = (s.quantile(0.75), s.quantile(0.25)) if not s.empty else (1.0, 0.0)
            iqr_val = float(q75 - q25) if (q75 - q25) > 0 else 1.0

            means[f] = mean_val
            stds[f] = std_val
            mins[f] = min_val
            maxs[f] = max_val
            medians[f] = med_val
            iqrs[f] = iqr_val
            imputation_values[f] = med_val

    return {
        "schemaVersion": "1.0.0",
        "isFitted": True,
        "means": means,
        "stds": stds,
        "mins": mins,
        "maxs": maxs,
        "medians": medians,
        "iqrs": iqrs,
        "imputationValues": imputation_values,
    }

def main():
    parser = argparse.ArgumentParser(description="Privacy Sentinel AI - Model Training Pipeline")
    parser.add_argument("--dataset", type=str, help="Path to real Android telemetry dataset (JSON/CSV)", default=None)
    parser.add_argument("--output-dir", type=str, help="Output directory for ONNX model and params", default="./output")
    args = parser.parse_args()

    if not args.dataset or not os.path.exists(args.dataset):
        print("=" * 60)
        print("PHASE 2 INVARIANT: NO MODEL TRAINING WITHOUT REAL TELEMETRY")
        print("=" * 60)
        print("Training pipeline is disabled.")
        print("Please collect real telemetry from a physical Android device first.")
        print("Run with: python train_pipeline.py --dataset <path_to_real_telemetry.json>")
        sys.exit(0)

    print(f"Loading real dataset from: {args.dataset}")
    ingestion = DataIngestionService()
    if args.dataset.endswith(".json"):
        records = ingestion.load_json_records(args.dataset)
        df = ingestion.json_records_to_dataframe(records)
    else:
        import pandas as pd
        df = pd.read_csv(args.dataset)

    validator = DatasetValidator()
    is_valid, errors = validator.validate_dataframe(df)
    if not is_valid:
        print("Dataset validation failed with errors:")
        for err in errors:
            print(f" - {err}")
        sys.exit(1)

    print(f"Dataset validated successfully: {len(df)} records.")
    # Offline training logic will execute here once real telemetry is supplied

if __name__ == "__main__":
    main()
