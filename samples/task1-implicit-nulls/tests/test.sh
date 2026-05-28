#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Task 1 Verifier — Implicit Null Detection
# Writes a float reward in [0.0, 1.0] to /logs/verifier/reward.txt
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REWARD_FILE="/logs/verifier/reward.txt"
OUTPUT="/output/cleaned.csv"
LOG="/logs/verifier/details.txt"

mkdir -p /logs/verifier

log() { echo "$1" | tee -a "$LOG"; }
log "=== Task 1 Verifier — $(date -u) ==="

# Quick existence check
if [[ ! -f "$OUTPUT" ]]; then
    log "FAIL: /output/cleaned.csv not found"
    echo "0.0" > "$REWARD_FILE"
    exit 0
fi
log "PASS: output file exists"

python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import pandas as pd
import sys

OUTPUT = "/output/cleaned.csv"
SCORE_FILE = "/logs/verifier/py_score.txt"

gt = {
    "clean_row_count": 10000,
    "sentinel_999_count": 0,
    "sentinel_unknown_count": 0,
    "sentinel_empty_count": 0,
    "transaction_id_dtype": "int",
}

try:
    df = pd.read_csv(OUTPUT)
except Exception as e:
    print(f"FAIL: cannot read output CSV: {e}")
    open(SCORE_FILE, "w").write("0")
    sys.exit(0)

passed = 0
total = 5

# CHECK 1: Row count (deduplication)
expected_rows = gt["clean_row_count"]
actual_rows = len(df)
tol = 0.01
if abs(actual_rows - expected_rows) / expected_rows <= tol:
    print(f"PASS [1/5] row count: {actual_rows} (expected ~{expected_rows})")
    passed += 1
else:
    print(f"FAIL [1/5] row count: {actual_rows}, expected ~{expected_rows}. "
          f"Likely missed deduplication or over-dropped rows.")

# CHECK 2: No sentinel -999 in id_01
if "id_01" in df.columns:
    sentinel_count = (df["id_01"] == -999).sum()
    if sentinel_count == 0:
        print(f"PASS [2/5] id_01 has no -999 sentinel values")
        passed += 1
    else:
        print(f"FAIL [2/5] id_01 still has {sentinel_count} rows with -999 sentinel")
else:
    print("FAIL [2/5] id_01 column missing from output")

# CHECK 3: No sentinel 'unknown' in id_12
if "id_12" in df.columns:
    sentinel_count = (df["id_12"].astype(str).str.lower() == "unknown").sum()
    if sentinel_count == 0:
        print(f"PASS [3/5] id_12 has no 'unknown' sentinel values")
        passed += 1
    else:
        print(f"FAIL [3/5] id_12 still has {sentinel_count} rows with 'unknown' sentinel")
else:
    print("FAIL [3/5] id_12 column missing from output")

# CHECK 4: No empty string in id_15
if "id_15" in df.columns:
    empty_count = (df["id_15"].astype(str).str.strip() == "").sum()
    if empty_count == 0:
        print(f"PASS [4/5] id_15 has no empty-string sentinels")
        passed += 1
    else:
        print(f"FAIL [4/5] id_15 still has {empty_count} empty-string rows")
else:
    print("FAIL [4/5] id_15 column missing from output")

# CHECK 5: TransactionID is integer type (not float)
if "TransactionID" in df.columns:
    dtype = str(df["TransactionID"].dtype)
    if "float" not in dtype.lower():
        print(f"PASS [5/5] TransactionID dtype is {dtype} (correct)")
        passed += 1
    else:
        print(f"FAIL [5/5] TransactionID dtype is {dtype} — should be integer.")
else:
    print("FAIL [5/5] TransactionID column missing from output")

score = 1.0 if passed == total else 0.0
print(f"\nSCORE: {passed}/{total} — reward: {score}")
open(SCORE_FILE, "w").write(str(score))
PYEOF

# Read python score
if [[ -f /logs/verifier/py_score.txt ]]; then
    final_score=$(cat /logs/verifier/py_score.txt)
else
    final_score="0.0"
fi

echo "$final_score" > "$REWARD_FILE"
log "=== Final reward: $final_score ==="
