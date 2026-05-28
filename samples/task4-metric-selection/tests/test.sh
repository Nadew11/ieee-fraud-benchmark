#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Task 4 Verifier — Metric Selection with Data Quality Traps
# The predictions.csv contains calibration samples (batch_id=99) and duplicate
# TransactionIDs. Naive metric computation produces WRONG results.
# 8 checks: structure, data cleaning, metrics accuracy, reasoning quality
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
mkdir -p /logs/verifier
LOG="/logs/verifier/details.txt"
REWARD="/logs/verifier/reward.txt"
log() { echo "$1" | tee -a "$LOG"; }
log "=== Task 4 Verifier — $(date -u) ==="

python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import json
import os
import re
import pandas as pd
import numpy as np
from sklearn.metrics import roc_auc_score

# ── Compute ground truth by cleaning /data/predictions.csv ──
df_raw = pd.read_csv("/data/predictions.csv")
dirty_auc = roc_auc_score(df_raw["y_true"], df_raw["y_pred_prob"])
dirty_count = len(df_raw)

# Clean: remove calibration (batch_id=99) and deduplicate
df_clean = df_raw[df_raw["batch_id"] != 99].copy()
df_clean = df_clean.sort_values("scored_at").drop_duplicates("TransactionID", keep="last")
clean_auc = roc_auc_score(df_clean["y_true"], df_clean["y_pred_prob"])
clean_count = len(df_clean)

# Also compute with keep="first" for tolerance
df_clean_first = df_raw[df_raw["batch_id"] != 99].copy()
df_clean_first = df_clean_first.drop_duplicates("TransactionID", keep="first")
clean_auc_first = roc_auc_score(df_clean_first["y_true"], df_clean_first["y_pred_prob"])

n_cal = (df_raw["batch_id"] == 99).sum()
n_dup = dirty_count - n_cal - clean_count

print(f"Ground truth: clean_auc={clean_auc:.4f}, dirty_auc={dirty_auc:.4f}, "
      f"clean_count={clean_count}, dirty_count={dirty_count}, "
      f"calibration_rows={n_cal}, duplicate_rows={n_dup}")

# ── Read agent outputs ──
def read_file(path):
    if os.path.exists(path):
        return open(path).read().strip()
    return ""

audit = read_file("/output/audit_findings.txt")
recommendation = read_file("/output/recommendation.txt")
metrics = {}
if os.path.exists("/output/metrics.json"):
    try:
        metrics = json.load(open("/output/metrics.json"))
    except:
        pass

passed = 0
total = 9

# ══════════════════════════════════════════════════════════════════════
# CHECK 1/8: All three output files exist and are non-trivial
# ══════════════════════════════════════════════════════════════════════
files_ok = True
for fname, content, min_len in [
    ("audit_findings.txt", audit, 200),
    ("metrics.json", json.dumps(metrics), 10),
    ("recommendation.txt", recommendation, 200),
]:
    if len(content) < min_len:
        files_ok = False
        print(f"FAIL [1/9] /output/{fname} missing or too short ({len(content)} chars, need {min_len})")
        break
if files_ok:
    print(f"PASS [1/9] All 3 output files exist (audit={len(audit)}, rec={len(recommendation)} chars)")
    passed += 1

# ══════════════════════════════════════════════════════════════════════
# CHECK 2/8: metrics.json has >=3 metrics with valid floats
# ══════════════════════════════════════════════════════════════════════
if metrics and len(metrics) >= 3:
    all_valid = all(isinstance(v, (int, float)) for v in metrics.values())
    if all_valid:
        print(f"PASS [2/9] metrics.json has {len(metrics)} valid metrics: {list(metrics.keys())}")
        passed += 1
    else:
        print(f"FAIL [2/9] metrics.json has non-numeric values")
elif metrics:
    print(f"FAIL [2/9] Only {len(metrics)} metrics (need >=3)")
else:
    print(f"FAIL [2/9] metrics.json empty or not found")

# ══════════════════════════════════════════════════════════════════════
# CHECK 3/8: AUC within +/-0.01 of CLEAN ground truth
# This FAILS if agent computed on dirty data (calibration inflates AUC)
# ══════════════════════════════════════════════════════════════════════
auc_ok = False
agent_auc = None
for k, v in metrics.items():
    kl = k.lower()
    if "auc" in kl or "roc" in kl:
        agent_auc = v
        # Accept if close to either dedup strategy
        if abs(v - clean_auc) < 0.01 or abs(v - clean_auc_first) < 0.01:
            print(f"PASS [3/9] AUC '{k}'={v:.4f} matches clean ground truth "
                  f"(expected ~{clean_auc:.4f})")
            passed += 1
            auc_ok = True
        else:
            diff = abs(v - clean_auc)
            if abs(v - dirty_auc) < 0.01:
                print(f"FAIL [3/9] AUC '{k}'={v:.4f} matches DIRTY data "
                      f"(includes anomalous rows). Clean AUC={clean_auc:.4f}. "
                      f"Did you investigate and remove outlier rows?")
            else:
                print(f"FAIL [3/9] AUC '{k}'={v:.4f} off by {diff:.4f} from "
                      f"clean value {clean_auc:.4f}")
        break
if agent_auc is None:
    print(f"FAIL [3/9] No AUC/ROC metric in metrics.json. Keys: {list(metrics.keys())}")

# ══════════════════════════════════════════════════════════════════════
# CHECK 4/8: Agent identifies data quality issues
# Must mention BOTH: calibration/anomalous rows AND duplicates
# ══════════════════════════════════════════════════════════════════════
all_text = (audit + " " + recommendation).lower()

found_calibration = any(re.search(pat, all_text) for pat in [
    r"batch.?99", r"calibration", r"calib.*sample",
    r"non.?production", r"anomal",
    r"synthetic", r"inflat.*auc",
    r"outlier.*(?:row|record|transaction)",
    r"(?:remov|exclud|filter|drop).*batch",
    r"suspicious.*(?:row|record|transaction|pattern|batch)",
    r"unusual.*(?:fraud|rate|distribution|pattern)",
    r"(?:50|fifty)\s*%.*fraud",
    r"contamina", r"test.*data",
])
found_duplicates = any(re.search(pat, all_text) for pat in [
    r"duplicate.*transaction", r"duplicate.*id",
    r"re.?scor", r"dedup", r"de.?duplicate",
    r"transaction.*appear.*(?:more|multiple|twice)",
    r"(?:remov|drop|exclud).*duplicate",
    r"duplicate.*(?:row|record|entri)",
])

issues_found = int(found_calibration) + int(found_duplicates)
if issues_found == 2:
    print(f"PASS [4/9] Agent identifies both data quality issues "
          f"(calibration={found_calibration}, duplicates={found_duplicates})")
    passed += 1
elif issues_found == 1:
    missing = "duplicates" if found_calibration else "calibration/anomalous rows"
    print(f"FAIL [4/9] Agent found 1/2 data issues. Missing: {missing}")
else:
    print(f"FAIL [4/9] Agent did not identify data quality issues "
          f"(calibration rows, duplicate TransactionIDs)")

# ══════════════════════════════════════════════════════════════════════
# CHECK 5/8: Audit identifies accuracy as misleading
# ══════════════════════════════════════════════════════════════════════
audit_lower = audit.lower()
accuracy_critique = any(re.search(pat, audit_lower) for pat in [
    r"accuracy.*mislead", r"accuracy.*not.*(?:appropriate|suitable|meaningful|reliable)",
    r"accuracy.*paradox", r"accuracy alone",
    r"mislead.*accuracy", r"accuracy.*trap",
    r"accuracy.*(?:meaningless|irrelevant|insufficient|inadequate)",
])
if accuracy_critique:
    print(f"PASS [5/9] Audit correctly identifies accuracy as misleading")
    passed += 1
else:
    print(f"FAIL [5/9] Audit does not identify accuracy as misleading for imbalanced data")

# ══════════════════════════════════════════════════════════════════════
# CHECK 6/8: Recommendation does NOT endorse deploying as-is
# ══════════════════════════════════════════════════════════════════════
rec_lower = recommendation.lower()
pushes_back = any(re.search(pat, rec_lower) for pat in [
    r"not.*ready", r"should not.*deploy", r"do not.*deploy",
    r"not.*deploy.*as[- ]is", r"don'?t deploy",
    r"further.*tuning", r"need.*improv", r"recommend.*against",
    r"caution", r"threshold.*adjust", r"reject", r"retrain",
    r"not.*recommend.*deploy", r"additional.*work",
    r"tune", r"adjust.*threshold", r"lower.*threshold",
    r"optimize", r"not.*recommend.*production",
])
endorses_deploy = not pushes_back and any(re.search(pat, rec_lower) for pat in [
    r"ready for.*production", r"recommend.*deploy",
    r"model is ready", r"approve.*deploy",
    r"deploy.*immediately",
])
if pushes_back:
    print(f"PASS [6/9] Recommendation pushes back on deploy-as-is")
    passed += 1
elif endorses_deploy:
    print(f"FAIL [6/9] Recommendation endorses deploying as-is")
else:
    print(f"FAIL [6/9] Recommendation unclear on deployment decision")

# ══════════════════════════════════════════════════════════════════════
# CHECK 7/8: Financial impact analysis with dollar amounts
# ══════════════════════════════════════════════════════════════════════
dollar_amounts = re.findall(r'\$[\d,]+(?:\.\d+)?', audit + " " + recommendation)
has_cost_terms = any(t in all_text for t in [
    "cost", "loss", "financial impact", "savings",
    "quarterly", "per quarter", "annual",
])
if len(dollar_amounts) >= 2 and has_cost_terms:
    print(f"PASS [7/9] Financial impact analysis present ({len(dollar_amounts)} dollar amounts)")
    passed += 1
elif has_cost_terms:
    print(f"FAIL [7/9] Cost discussion found but no specific dollar amounts")
else:
    print(f"FAIL [7/9] No financial impact analysis found")

# ══════════════════════════════════════════════════════════════════════
# CHECK 8/9: Agent reports correct cleaned row count (exactly 5000)
# ══════════════════════════════════════════════════════════════════════
# Look for the number 5000 or 5,000 in outputs or metrics
all_output = audit + " " + recommendation + " " + json.dumps(metrics)
count_patterns = re.findall(r'5[,.]?000', all_output)
# Also check if metrics.json has a count-like key with value 5000
has_count_metric = any(
    isinstance(v, (int, float)) and abs(v - clean_count) < 2
    for k, v in metrics.items()
    if any(t in k.lower() for t in ["count", "rows", "size", "transactions", "clean", "total", "n_"])
)
if count_patterns or has_count_metric:
    print(f"PASS [8/9] Agent reports correct cleaned dataset size (~{clean_count})")
    passed += 1
else:
    print(f"FAIL [8/9] Agent does not report cleaned row count. "
          f"Expected {clean_count:,} after removing calibration + deduplication")

# ══════════════════════════════════════════════════════════════════════
# CHECK 9/9: Non-default threshold recommendation with justification
# ══════════════════════════════════════════════════════════════════════
threshold_vals = re.findall(r'threshold.*?(?:of\s+|=\s*|:\s*)(0\.\d+)', rec_lower)
if not threshold_vals:
    threshold_vals = re.findall(r'(0\.\d+).*?threshold', rec_lower)

non_default = any(abs(float(t) - 0.5) > 0.02 for t in threshold_vals) if threshold_vals else False
has_justification = any(t in rec_lower for t in [
    "recall", "precision", "false negative", "false positive",
    "cost", "trade-off", "tradeoff", "capacity", "flagged",
    "missed fraud", "alert",
])
if non_default and has_justification:
    print(f"PASS [9/9] Non-default threshold recommended ({threshold_vals}) with justification")
    passed += 1
elif non_default:
    print(f"FAIL [9/9] Threshold found but no justification")
else:
    print(f"FAIL [9/9] No non-default threshold recommended")

score = 1.0 if passed == total else 0.0
print(f"\nSCORE: {passed}/{total} = {score}")
open("/logs/verifier/py_score.txt", "w").write(str(score))
PYEOF

final=$(cat /logs/verifier/py_score.txt 2>/dev/null || echo "0.0")
echo "$final" > "$REWARD"
log "=== Final reward: $final ==="
