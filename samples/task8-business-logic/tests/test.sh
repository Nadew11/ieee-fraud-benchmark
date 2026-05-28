#!/usr/bin/env bash
set -uo pipefail
mkdir -p /logs/verifier
LOG="/logs/verifier/details.txt"
REWARD="/logs/verifier/reward.txt"
log() { echo "$1" | tee -a "$LOG"; }
log "=== Task 8 Verifier — $(date -u) ==="

pip install --break-system-packages --quiet openpyxl==3.1.5 2>/dev/null

python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import os
import json
import pandas as pd
from openpyxl import load_workbook

OUTPUT = "/output/fraud_report.xlsx"

# Load ground truth
with open("/data/ground_truth.json") as f:
    gt = json.load(f)

passed = 0
total = 5

# CHECK 1: File exists and has required sheets
if not os.path.exists(OUTPUT):
    print("FAIL [1/5] /output/fraud_report.xlsx not found")
    open("/logs/verifier/py_score.txt", "w").write("0")
    import sys; sys.exit(0)

try:
    wb = load_workbook(OUTPUT, data_only=True)
except Exception as e:
    print(f"FAIL [1/5] Cannot open xlsx: {e}")
    open("/logs/verifier/py_score.txt", "w").write("0")
    import sys; sys.exit(0)

expected_sheets = {"Monthly Breakdown", "Regional Summary", "Executive Summary"}
if expected_sheets.issubset(set(wb.sheetnames)):
    print(f"PASS [1/5] All 3 required sheets present: {wb.sheetnames}")
    passed += 1
else:
    missing = expected_sheets - set(wb.sheetnames)
    print(f"FAIL [1/5] Missing sheets: {missing}. Found: {wb.sheetnames}")

# CHECK 2: Executive Summary net fraud total within tolerance
ws_exec = wb["Executive Summary"] if "Executive Summary" in wb.sheetnames else None
net_total_reported = None
if ws_exec:
    label = ws_exec["A1"].value
    val = ws_exec["B1"].value
    if label == "q4_net_fraud_total_usd" and val is not None:
        try:
            net_total_reported = float(val)
            expected = gt["q4_net_fraud_total_usd"]
            tol = gt["tolerance_pct"] / 100.0
            pct_err = abs(net_total_reported - expected) / expected
            if pct_err <= tol:
                print(f"PASS [2/5] Net fraud total {net_total_reported:.2f} within "
                      f"{gt['tolerance_pct']}% of expected {expected:.2f} (err: {pct_err:.1%})")
                passed += 1
            else:
                print(f"FAIL [2/5] Net fraud total {net_total_reported:.2f} is {pct_err:.1%} off "
                      f"from expected {expected:.2f}. Tolerance: {gt['tolerance_pct']}%")
        except (TypeError, ValueError) as e:
            print(f"FAIL [2/5] B1 is not a number: {val} ({e})")
    else:
        print(f"FAIL [2/5] A1 should be 'q4_net_fraud_total_usd', got '{label}'. B1={val}")
else:
    print("FAIL [2/5] Executive Summary sheet missing")

# CHECK 3: Regional Summary has correct regions and structure
ws_reg = wb["Regional Summary"] if "Regional Summary" in wb.sheetnames else None
if ws_reg:
    headers = {}
    for idx, cell in enumerate(ws_reg[1], start=1):
        if cell.value:
            headers[str(cell.value).strip()] = idx

    req_cols = {"region", "q4_net_fraud_usd", "q4_fraud_count", "q4_avg_ticket_usd", "pct_of_total"}
    if req_cols.issubset(set(headers.keys())):
        regions_found = set()
        for row in ws_reg.iter_rows(min_row=2, values_only=True):
            if row[headers["region"] - 1]:
                regions_found.add(str(row[headers["region"] - 1]))

        expected_regions = set(gt["expected_regions"])
        if expected_regions.issubset(regions_found):
            print(f"PASS [3/5] Regional Summary has required columns and regions: {sorted(regions_found)}")
            passed += 1
        else:
            missing = expected_regions - regions_found
            print(f"FAIL [3/5] Missing regions: {missing}. Found: {sorted(regions_found)}")
    else:
        missing_cols = req_cols - set(headers.keys())
        print(f"FAIL [3/5] Regional Summary missing columns: {missing_cols}. Found: {list(headers.keys())}")
else:
    print("FAIL [3/5] Regional Summary sheet missing")

# CHECK 4: Monthly Breakdown has 3 months × regions with correct structure
ws_mon = wb["Monthly Breakdown"] if "Monthly Breakdown" in wb.sheetnames else None
if ws_mon:
    headers = {}
    for idx, cell in enumerate(ws_mon[1], start=1):
        if cell.value:
            headers[str(cell.value).strip()] = idx

    req_cols = {"month", "region", "gross_fraud_usd", "net_fraud_usd",
                "processing_fees", "fraud_transaction_count", "avg_ticket_usd"}
    if req_cols.issubset(set(headers.keys())):
        months_found = set()
        for row in ws_mon.iter_rows(min_row=2, values_only=True):
            m = row[headers["month"] - 1]
            if m:
                months_found.add(str(m))

        expected_months = set(gt["expected_months"])
        if expected_months.issubset(months_found):
            print(f"PASS [4/5] Monthly Breakdown has required columns and months: {sorted(months_found)}")
            passed += 1
        else:
            missing = expected_months - months_found
            print(f"FAIL [4/5] Missing months: {missing}. Found: {sorted(months_found)}")
    else:
        missing_cols = req_cols - set(headers.keys())
        print(f"FAIL [4/5] Monthly Breakdown missing columns: {missing_cols}. Found: {list(headers.keys())}")
else:
    print("FAIL [4/5] Monthly Breakdown sheet missing")

# CHECK 5: Executive Summary has gross, fees, recoveries AND assumptions
if ws_exec:
    gross_label = ws_exec["A2"].value
    fees_label = ws_exec["A3"].value
    recov_label = ws_exec["A4"].value

    has_gross = gross_label == "q4_gross_fraud_total_usd" and ws_exec["B2"].value is not None
    has_fees = fees_label == "total_processing_fees" and ws_exec["B3"].value is not None
    has_recov = recov_label == "total_recoveries" and ws_exec["B4"].value is not None

    # Check assumptions table exists (row 6 header, row 7+ data)
    assumption_header = ws_exec["A6"].value
    has_assumptions = assumption_header == "assumption_number"
    n_assumptions = 0
    if has_assumptions:
        for row in ws_exec.iter_rows(min_row=7, values_only=True):
            if row[0] is not None:
                n_assumptions += 1

    all_exec_ok = has_gross and has_fees and has_recov and has_assumptions and n_assumptions >= 4
    if all_exec_ok:
        print(f"PASS [5/5] Executive Summary has gross/fees/recoveries labels "
              f"and {n_assumptions} documented assumptions")
        passed += 1
    else:
        issues = []
        if not has_gross: issues.append("A2 not 'q4_gross_fraud_total_usd'")
        if not has_fees: issues.append("A3 not 'total_processing_fees'")
        if not has_recov: issues.append("A4 not 'total_recoveries'")
        if not has_assumptions: issues.append("A6 not 'assumption_number'")
        if n_assumptions < 4: issues.append(f"only {n_assumptions} assumptions (need >=4)")
        print(f"FAIL [5/5] Executive Summary issues: {issues}")
else:
    print("FAIL [5/5] Executive Summary sheet missing")

score = 1.0 if passed == total else 0.0
print(f"\nSCORE: {passed}/{total} — reward: {score}")
open("/logs/verifier/py_score.txt", "w").write(str(score))
PYEOF

final=$(cat /logs/verifier/py_score.txt 2>/dev/null || echo "0.0")
echo "$final" > "$REWARD"
log "=== Final reward: $final ==="
