#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Task 1 Oracle Solution — Implicit Null Detection
# Correctly handles all 4 stacked issues:
#   1. Replaces -999 sentinel in id_01 with NaN
#   2. Replaces 'unknown' sentinel in id_12 with NaN
#   3. Replaces empty-string sentinel in id_15 with NaN
#   4. Casts TransactionID from float to int
#   5. Deduplicates on TransactionID (keep first)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
mkdir -p /output

python3 - <<'PYEOF'
import pandas as pd
import numpy as np

print("[oracle] Loading /data/train_identity.csv ...")
df = pd.read_csv("/data/train_identity.csv")
print(f"[oracle] Loaded {len(df):,} rows × {df.shape[1]} columns")

# ── STEP 1: Sentinel null in id_01 → NaN
before = (df["id_01"] == -999).sum()
df.loc[df["id_01"] == -999, "id_01"] = np.nan
print(f"[oracle] id_01: replaced {before} sentinel -999 values with NaN")

# ── STEP 2: Sentinel null in id_12 → NaN
before = (df["id_12"].astype(str).str.lower() == "unknown").sum()
df.loc[df["id_12"].astype(str).str.lower() == "unknown", "id_12"] = np.nan
print(f"[oracle] id_12: replaced {before} sentinel 'unknown' values with NaN")

# ── STEP 3: Empty-string sentinel in id_15 → NaN
before = (df["id_15"].astype(str).str.strip() == "").sum()
df["id_15"] = df["id_15"].astype(str).str.strip()
df.loc[df["id_15"] == "", "id_15"] = np.nan
# 'nan' string from earlier astype → also NaN
df.loc[df["id_15"] == "nan", "id_15"] = np.nan
print(f"[oracle] id_15: replaced {before} empty-string sentinels with NaN")

# ── STEP 4: Fix TransactionID dtype float → int
df["TransactionID"] = df["TransactionID"].astype(np.int64)
print(f"[oracle] TransactionID cast to int64 (was float64)")

# ── STEP 5: Deduplicate on TransactionID
before = len(df)
df = df.drop_duplicates(subset=["TransactionID"], keep="first")
print(f"[oracle] Removed {before - len(df)} duplicate TransactionID rows → {len(df):,} remain")

# ── Save
df.to_csv("/output/cleaned.csv", index=False)
print(f"[oracle] Saved /output/cleaned.csv ({len(df):,} rows)")
PYEOF
