#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Task 7 Verifier — Broken XGBoost Pipeline
# Checks:
#   1. auc.txt exists with valid float
#   2. AUC > 0.85 (threshold for correct fix)
#   3. bug_report.txt exists and is non-trivial
#   4. Bug 1 (eval_metric) mentioned in report
#   5. Bug 2 (stratify) AND Bug 3 (scaler leakage) mentioned
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
mkdir -p /logs/verifier
LOG="/logs/verifier/details.txt"
REWARD="/logs/verifier/reward.txt"
log() { echo "$1" | tee -a "$LOG"; }
log "=== Task 7 Verifier — $(date -u) ==="

python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import os

gt = {
    "correct_auc_min": 0.85,
}

passed = 0; total = 5
auc = None
report = ""

# CHECK 1: auc.txt
if os.path.exists("/output/auc.txt"):
    try:
        auc = float(open("/output/auc.txt").read().strip())
        print(f"PASS [1/5] auc.txt = {auc:.4f}")
        passed += 1
    except Exception as e:
        print(f"FAIL [1/5] auc.txt parse error: {e}")
else:
    print("FAIL [1/5] /output/auc.txt not found")

# CHECK 2: AUC > 0.85
if auc is not None:
    thresh = gt["correct_auc_min"]
    if auc >= thresh:
        print(f"PASS [2/5] AUC {auc:.4f} ≥ {thresh} — pipeline correctly fixed")
        passed += 1
    else:
        print(f"FAIL [2/5] AUC {auc:.4f} < {thresh}. "
              f"Pipeline still has bugs. Correct implementation should exceed {thresh}.")

# CHECK 3: bug_report.txt exists
if os.path.exists("/output/bug_report.txt"):
    report = open("/output/bug_report.txt").read().lower()
    if len(report) > 100:
        print(f"PASS [3/5] bug_report.txt exists ({len(report)} chars)")
        passed += 1
    else:
        print(f"FAIL [3/5] bug_report.txt too short ({len(report)} chars)")
else:
    print("FAIL [3/5] /output/bug_report.txt not found")

# CHECK 4: Bug 1 (eval_metric / rmse) mentioned
if report:
    bug1_keywords = ["eval_metric", "rmse", "metric", "logloss", "auc metric",
                     "wrong metric", "evaluation metric"]
    if any(kw in report for kw in bug1_keywords):
        print(f"PASS [4/5] Bug 1 (eval_metric=rmse) identified in report")
        passed += 1
    else:
        print(f"FAIL [4/5] Bug 1 (eval_metric=rmse for binary classification) "
              f"not identified. This is the primary metric signal bug.")

# CHECK 5: Bug 2 (stratify) and Bug 3 (scaler leakage) mentioned
if report:
    bug2_keywords = ["stratif", "imbalanced", "class imbalance", "stratified split"]
    bug3_keywords = ["scaler", "scale", "fit_transform", "leakage", "before split",
                     "full dataset", "data leak", "train only"]
    has_bug2 = any(kw in report for kw in bug2_keywords)
    has_bug3 = any(kw in report for kw in bug3_keywords)
    if has_bug2 and has_bug3:
        print(f"PASS [5/5] Both Bug 2 (stratify) and Bug 3 (scaler leakage) identified")
        passed += 1
    elif has_bug2:
        print(f"FAIL [5/5] Bug 2 (stratify) found but Bug 3 (scaler fitted before split) missed")
    elif has_bug3:
        print(f"FAIL [5/5] Bug 3 (scaler leakage) found but Bug 2 (stratify) missed")
    else:
        print(f"FAIL [5/5] Neither Bug 2 (stratify) nor Bug 3 (scaler leakage) identified")

score = 1.0 if passed == total else 0.0
print(f"\nSCORE: {passed}/{total} — reward: {score}")
open("/logs/verifier/py_score.txt", "w").write(str(score))
PYEOF

final=$(cat /logs/verifier/py_score.txt 2>/dev/null || echo "0.0")
echo "$final" > "$REWARD"
log "=== Final reward: $final ==="
