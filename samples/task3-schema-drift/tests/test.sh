#!/usr/bin/env bash
set -uo pipefail
mkdir -p /logs/verifier
LOG="/logs/verifier/details.txt"
REWARD="/logs/verifier/reward.txt"
log() { echo "$1" | tee -a "$LOG"; }
log "=== Task 3 Verifier — $(date -u) ==="

pip install --break-system-packages --quiet openpyxl==3.1.5 2>/dev/null

python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import os
import pandas as pd
import numpy as np
from openpyxl import load_workbook

OUTPUT = "/output/fraud_risk.xlsx"

passed = 0
total = 5

# CHECK 1: File exists with required sheets
if not os.path.exists(OUTPUT):
    print("FAIL [1/5] /output/fraud_risk.xlsx not found")
    open("/logs/verifier/py_score.txt", "w").write("0")
    import sys; sys.exit(0)

try:
    wb = load_workbook(OUTPUT, data_only=True)
except Exception as e:
    print(f"FAIL [1/5] Cannot open xlsx: {e}")
    open("/logs/verifier/py_score.txt", "w").write("0")
    import sys; sys.exit(0)

expected_sheets = {"Predictions", "Data Quality Report"}
if expected_sheets.issubset(set(wb.sheetnames)):
    print(f"PASS [1/5] Required sheets present: {wb.sheetnames}")
    passed += 1
else:
    missing = expected_sheets - set(wb.sheetnames)
    print(f"FAIL [1/5] Missing sheets: {missing}. Found: {wb.sheetnames}")

# CHECK 2: Predictions sheet has correct row count and columns
ws_pred = wb["Predictions"] if "Predictions" in wb.sheetnames else None
if ws_pred:
    headers = {}
    for idx, cell in enumerate(ws_pred[1], start=1):
        if cell.value:
            headers[str(cell.value).strip()] = idx

    if "TransactionID" in headers and "fraud_prob" in headers:
        n_rows = 0
        for row in ws_pred.iter_rows(min_row=2, values_only=True):
            if row[0] is not None:
                n_rows += 1

        expected_rows = 2000
        if abs(n_rows - expected_rows) / expected_rows <= 0.01:
            print(f"PASS [2/5] Predictions: {n_rows} rows (expected {expected_rows}), correct columns")
            passed += 1
        else:
            print(f"FAIL [2/5] Predictions: {n_rows} rows, expected {expected_rows}")
    else:
        print(f"FAIL [2/5] Predictions missing columns. Found: {list(headers.keys())}")
else:
    print("FAIL [2/5] Predictions sheet missing")

# CHECK 3: Predictions have non-trivial variance (model actually learned)
if ws_pred:
    probs = []
    col_idx = headers.get("fraud_prob", 2)
    for row in ws_pred.iter_rows(min_row=2, values_only=True):
        if row[col_idx - 1] is not None:
            try:
                probs.append(float(row[col_idx - 1]))
            except (TypeError, ValueError):
                pass

    if probs:
        std = np.std(probs)
        mean_prob = np.mean(probs)
        if std > 0.01 and 0.001 < mean_prob < 0.5:
            print(f"PASS [3/5] fraud_prob std={std:.4f}, mean={mean_prob:.4f} — model learned")
            passed += 1
        else:
            print(f"FAIL [3/5] fraud_prob std={std:.6f}, mean={mean_prob:.4f} — "
                  f"predictions look trivial or constant. Schema drift likely not resolved.")
    else:
        print("FAIL [3/5] No valid fraud_prob values found")

# CHECK 4: Data Quality Report has correct structure and AUC
ws_dq = wb["Data Quality Report"] if "Data Quality Report" in wb.sheetnames else None
if ws_dq:
    a1 = ws_dq["A1"].value
    a4 = ws_dq["A4"].value
    b4 = ws_dq["B4"].value

    has_layout = (a1 == "total_train_rows")
    has_auc = False
    if a4 == "model_auc_on_train_holdout" and b4 is not None:
        try:
            holdout_auc = float(b4)
            if holdout_auc > 0.45:
                has_auc = True
                print(f"  Holdout AUC: {holdout_auc:.4f}")
        except (TypeError, ValueError):
            pass

    if has_layout and has_auc:
        print(f"PASS [4/5] Data Quality Report layout correct, AUC={holdout_auc:.4f} > 0.55")
        passed += 1
    else:
        issues = []
        if not has_layout: issues.append(f"A1 should be 'total_train_rows', got '{a1}'")
        if not has_auc: issues.append(f"A4 should be 'model_auc_on_train_holdout' with AUC > 0.45, got A4='{a4}' B4='{b4}'")
        print(f"FAIL [4/5] Data Quality Report issues: {issues}")
else:
    print("FAIL [4/5] Data Quality Report sheet missing")

# CHECK 5: Data Quality Report documents at least 1 data integration issue
if ws_dq:
    a6 = ws_dq["A6"].value
    has_issue_header = (a6 == "issue_number")
    n_issues = 0
    if has_issue_header:
        for row in ws_dq.iter_rows(min_row=7, values_only=True):
            if row[0] is not None:
                n_issues += 1

    if has_issue_header and n_issues >= 1:
        print(f"PASS [5/5] Data Quality Report documents {n_issues} integration issues")
        passed += 1
    else:
        issues = []
        if not has_issue_header: issues.append("A6 should be 'issue_number'")
        if n_issues < 1: issues.append(f"need >=1 documented issues, found {n_issues}")
        print(f"FAIL [5/5] {issues}")
else:
    print("FAIL [5/5] Data Quality Report sheet missing")

score = 1.0 if passed == total else 0.0
print(f"\nSCORE: {passed}/{total} — reward: {score}")
open("/logs/verifier/py_score.txt", "w").write(str(score))
PYEOF

final=$(cat /logs/verifier/py_score.txt 2>/dev/null || echo "0.0")
echo "$final" > "$REWARD"
log "=== Final reward: $final ==="
