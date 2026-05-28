#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Task 5 Verifier — Join Inflation
# Checks:
#   1. fraud_by_device.csv exists
#   2. total_fraud.txt exists with valid float
#   3. Total fraud within 5% of correct (not inflated) value
#   4. Total fraud NOT matching the inflated (wrong) value
#   5. fraud_by_device has expected columns and non-trivial data
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
mkdir -p /logs/verifier
LOG="/logs/verifier/details.txt"
REWARD="/logs/verifier/reward.txt"
log() { echo "$1" | tee -a "$LOG"; }
log "=== Task 5 Verifier — $(date -u) ==="

python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import os
import pandas as pd

# Compute ground truth from the actual data files in the container
tx = pd.read_csv("/data/transactions.csv")
ident = pd.read_csv("/data/identity.csv")

# Correct answer: deduplicate identity first, then join
ident_clean = ident.drop_duplicates(subset=["TransactionID"], keep="first")
merged_clean = tx.merge(ident_clean, on="TransactionID", how="left")
fraud_clean = merged_clean[merged_clean["isFraud"] == 1]
correct_total = float(fraud_clean["TransactionAmt"].sum())

# Wrong answer: naive join without dedup (inflated)
merged_inflated = tx.merge(ident, on="TransactionID", how="left")
fraud_inflated = merged_inflated[merged_inflated["isFraud"] == 1]
inflated_total = float(fraud_inflated["TransactionAmt"].sum())

gt = {
    "correct_total_fraud": round(correct_total, 2),
    "inflated_total_fraud": round(inflated_total, 2),
    "tolerance_pct": 5.0,
}

passed = 0; total = 5
correct = gt["correct_total_fraud"]
inflated = gt["inflated_total_fraud"]
tol_pct  = gt["tolerance_pct"] / 100.0

# CHECK 1: fraud_by_device.csv exists
if os.path.exists("/output/fraud_by_device.csv"):
    try:
        dev_df = pd.read_csv("/output/fraud_by_device.csv")
        print(f"PASS [1/5] fraud_by_device.csv exists ({len(dev_df)} rows)")
        passed += 1
    except Exception as e:
        dev_df = None
        print(f"FAIL [1/5] Cannot read fraud_by_device.csv: {e}")
else:
    dev_df = None
    print("FAIL [1/5] /output/fraud_by_device.csv not found")

# CHECK 2: total_fraud.txt valid float
total_reported = None
if os.path.exists("/output/total_fraud.txt"):
    try:
        total_reported = float(open("/output/total_fraud.txt").read().strip())
        print(f"PASS [2/5] total_fraud.txt = {total_reported:,.2f}")
        passed += 1
    except Exception as e:
        print(f"FAIL [2/5] total_fraud.txt parse error: {e}")
else:
    print("FAIL [2/5] /output/total_fraud.txt not found")

if total_reported is not None:
    # CHECK 3: Within 5% of CORRECT (non-inflated) total
    pct_err = abs(total_reported - correct) / correct
    if pct_err <= tol_pct:
        print(f"PASS [3/5] Total fraud ${total_reported:,.2f} within {tol_pct:.0%} "
              f"of correct ${correct:,.2f} (error: {pct_err:.1%})")
        passed += 1
    else:
        print(f"FAIL [3/5] Total fraud ${total_reported:,.2f} is {pct_err:.1%} off "
              f"from correct ${correct:,.2f}. "
              f"(Inflated wrong answer would be ~${inflated:,.2f})")

    # CHECK 4: NOT matching the inflated wrong answer
    pct_err_inflated = abs(total_reported - inflated) / inflated
    if pct_err_inflated > tol_pct:
        print(f"PASS [4/5] Result does NOT match inflated wrong answer "
              f"(${inflated:,.2f}), diff={pct_err_inflated:.1%}")
        passed += 1
    else:
        print(f"FAIL [4/5] Result matches the INFLATED wrong answer ${inflated:,.2f}. "
              f"Naive join without deduplication was used. "
              f"Agent did not verify row count after join.")
else:
    print("SKIP [3/5] total_fraud.txt unavailable")
    print("SKIP [4/5] total_fraud.txt unavailable")

# CHECK 5: fraud_by_device.csv has correct structure
if dev_df is not None:
    required_cols = {"DeviceType", "total_fraud_amount", "fraud_transaction_count"}
    has_cols = required_cols.issubset(set(dev_df.columns))
    has_data = len(dev_df) >= 1 and dev_df["total_fraud_amount"].sum() > 0
    if has_cols and has_data:
        print(f"PASS [5/5] fraud_by_device.csv has required columns and non-zero data")
        passed += 1
    elif not has_cols:
        print(f"FAIL [5/5] fraud_by_device.csv missing columns. "
              f"Found: {list(dev_df.columns)}, need: {required_cols}")
    else:
        print(f"FAIL [5/5] fraud_by_device.csv has zero fraud amounts — "
              f"join or filter logic failed")

score = 1.0 if passed == total else 0.0
print(f"\nSCORE: {passed}/{total} — reward: {score}")
open("/logs/verifier/py_score.txt", "w").write(str(score))
PYEOF

final=$(cat /logs/verifier/py_score.txt 2>/dev/null || echo "0.0")
echo "$final" > "$REWARD"
log "=== Final reward: $final ==="
