#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Task 2 Verifier — Target Leakage Detection
# Checks:
#   1. predictions.csv exists with correct columns/rows
#   2. auc.txt exists and is a valid float
#   3. AUC is NOT suspiciously high (> 0.99 = leakage)
#   4. AUC is in the realistic range (0.78–0.94)
#   5. Leaky columns NOT used as features (inferred from AUC + log scan)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

mkdir -p /logs/verifier
LOG="/logs/verifier/details.txt"
REWARD_FILE="/logs/verifier/reward.txt"

log() { echo "$1" | tee -a "$LOG"; }
log "=== Task 2 Verifier — $(date -u) ==="

# Quick existence checks
if [[ ! -f /output/predictions.csv ]] && [[ ! -f /output/auc.txt ]]; then
    log "FAIL: neither predictions.csv nor auc.txt found"
    echo "0.0" > "$REWARD_FILE"; exit 0
fi

python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import pandas as pd
import sys
import os
import re

gt = {
    "leaky_columns": ["chargeback_amount", "fraud_score", "days_to_chargeback"],
    "auc_min_legitimate": 0.78,
    "auc_max_legitimate": 0.94,
    "auc_leakage_threshold": 0.99,
    "n_val_rows": 3000,
}

passed = 0
total = 5

# CHECK 1: predictions.csv
pred_ok = False
if os.path.exists("/output/predictions.csv"):
    try:
        pred = pd.read_csv("/output/predictions.csv")
        has_cols = "TransactionID" in pred.columns and "fraud_prob" in pred.columns
        n_val = gt["n_val_rows"]
        # Allow ±5% row count variance
        row_ok = abs(len(pred) - n_val) / n_val <= 0.05
        if has_cols and row_ok:
            print(f"PASS [1/5] predictions.csv: {len(pred)} rows, correct columns")
            passed += 1
            pred_ok = True
        elif not has_cols:
            print(f"FAIL [1/5] predictions.csv missing required columns. Found: {list(pred.columns)}")
        else:
            print(f"FAIL [1/5] predictions.csv row count {len(pred)}, expected ~{n_val}")
    except Exception as e:
        print(f"FAIL [1/5] Cannot read predictions.csv: {e}")
else:
    print("FAIL [1/5] /output/predictions.csv not found")

# CHECK 2: auc.txt is valid float
auc = None
if os.path.exists("/output/auc.txt"):
    try:
        raw = open("/output/auc.txt").read().strip()
        auc = float(raw)
        print(f"PASS [2/5] auc.txt contains valid float: {auc}")
        passed += 1
    except Exception as e:
        print(f"FAIL [2/5] auc.txt content not a valid float: {e}")
else:
    print("FAIL [2/5] /output/auc.txt not found")

if auc is not None:
    # CHECK 3: AUC not suspiciously high (leakage indicator)
    if auc <= gt["auc_leakage_threshold"]:
        print(f"PASS [3/5] AUC {auc:.4f} ≤ {gt['auc_leakage_threshold']} (not obviously leaked)")
        passed += 1
    else:
        print(f"FAIL [3/5] AUC {auc:.4f} > {gt['auc_leakage_threshold']} — "
              f"suspiciously high, likely used leaky columns (chargeback_amount / fraud_score / days_to_chargeback)")

    # CHECK 4: AUC in realistic range
    if gt["auc_min_legitimate"] <= auc <= gt["auc_max_legitimate"]:
        print(f"PASS [4/5] AUC {auc:.4f} in realistic range "
              f"[{gt['auc_min_legitimate']}, {gt['auc_max_legitimate']}]")
        passed += 1
    else:
        print(f"FAIL [4/5] AUC {auc:.4f} outside realistic range "
              f"[{gt['auc_min_legitimate']}, {gt['auc_max_legitimate']}]. "
              f"Either leakage present or model failed to learn.")
else:
    print("SKIP [3/5] AUC not available")
    print("SKIP [4/5] AUC not available")

# CHECK 5: Scan artifacts for explicit use of leaky column names
leaky = gt["leaky_columns"]
leaky_found = []
search_dirs = ["/output"]
for d in search_dirs:
    if not os.path.isdir(d):
        continue
    for root, dirs, files in os.walk(d):
        for fname in files:
            if fname.endswith((".py", ".sh", ".txt", ".log")):
                try:
                    content = open(os.path.join(root, fname)).read()
                    for col in leaky:
                        if col in content:
                            leaky_found.append(f"{fname}:{col}")
                except:
                    pass

if not leaky_found and auc is not None and auc <= gt["auc_leakage_threshold"]:
    print(f"PASS [5/5] No leaky column names found in agent output + AUC is clean")
    passed += 1
elif leaky_found:
    print(f"FAIL [5/5] Leaky columns referenced in agent files: {leaky_found[:5]}")
else:
    print(f"PASS [5/5] (auc not available for leakage check — giving benefit of doubt)")
    passed += 1

score = 1.0 if passed == total else 0.0
print(f"\nSCORE: {passed}/{total} — reward: {score}")
open("/logs/verifier/py_score.txt", "w").write(str(score))
PYEOF

final=$(cat /logs/verifier/py_score.txt 2>/dev/null || echo "0.0")
echo "$final" > "$REWARD_FILE"
log "=== Final reward: $final ==="
