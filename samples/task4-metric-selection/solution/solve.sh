#!/usr/bin/env bash
set -euo pipefail
mkdir -p /output

python3 - <<'PYEOF'
import pandas as pd
import numpy as np
import json
from sklearn.metrics import (roc_auc_score, f1_score, recall_score,
                              precision_score, average_precision_score)

# ── Read and inspect raw data ──
df_raw = pd.read_csv("/data/predictions.csv")
draft = open("/data/draft_evaluation.txt").read()
info = open("/data/dataset_info.txt").read()

COST_PER_MISSED = 4200
COST_PER_INVESTIGATION = 35
DAILY_CAPACITY = 1500
QUARTERLY_VOLUME = 2_800_000

# ── Data quality investigation ──
n_raw = len(df_raw)
n_cal = (df_raw["batch_id"] == 99).sum()
n_unique_txn = df_raw[df_raw["batch_id"] != 99]["TransactionID"].nunique()
n_dup = (df_raw["batch_id"] != 99).sum() - n_unique_txn

dirty_auc = roc_auc_score(df_raw["y_true"], df_raw["y_pred_prob"])

# ── Clean data: remove calibration batch, deduplicate ──
df = df_raw[df_raw["batch_id"] != 99].copy()
df = df.sort_values("scored_at").drop_duplicates("TransactionID", keep="last")
n_clean = len(df)

y_true = df["y_true"].values
y_prob = df["y_pred_prob"].values
fraud_rate = y_true.mean()
n_fraud = y_true.sum()

# ── Compute clean metrics ──
auc = roc_auc_score(y_true, y_prob)
pr_auc = average_precision_score(y_true, y_prob)

# Default threshold
y_pred_50 = (y_prob >= 0.5).astype(int)
acc_50 = (y_pred_50 == y_true).mean()
recall_50 = recall_score(y_true, y_pred_50, zero_division=0)

# Find cost-optimal threshold considering capacity constraint
best_cost = float('inf')
best_thresh = 0.5
for t in np.arange(0.1, 0.9, 0.01):
    y_pred_t = (y_prob >= t).astype(int)
    recall_t = recall_score(y_true, y_pred_t, zero_division=0)
    flag_rate = y_pred_t.mean()
    daily_flags = int(flag_rate * QUARTERLY_VOLUME / 90)

    missed = int(n_fraud * (1 - recall_t) * (QUARTERLY_VOLUME / n_clean))
    investigations = int(flag_rate * QUARTERLY_VOLUME)
    total_cost = missed * COST_PER_MISSED + investigations * COST_PER_INVESTIGATION

    if daily_flags <= DAILY_CAPACITY and total_cost < best_cost:
        best_cost = total_cost
        best_thresh = round(t, 2)

y_pred_opt = (y_prob >= best_thresh).astype(int)
recall_opt = recall_score(y_true, y_pred_opt, zero_division=0)
precision_opt = precision_score(y_true, y_pred_opt, zero_division=0)
f1_opt = f1_score(y_true, y_pred_opt, zero_division=0)
daily_flags_opt = int(y_pred_opt.mean() * QUARTERLY_VOLUME / 90)

# Financial impact
quarterly_fraud = int(QUARTERLY_VOLUME * fraud_rate)
missed_50 = int(quarterly_fraud * (1 - recall_50))
cost_missed_50 = missed_50 * COST_PER_MISSED
cost_invest_50 = int(y_pred_50.mean() * QUARTERLY_VOLUME) * COST_PER_INVESTIGATION
missed_opt = int(quarterly_fraud * (1 - recall_opt))
cost_missed_opt = missed_opt * COST_PER_MISSED
cost_invest_opt = int(y_pred_opt.mean() * QUARTERLY_VOLUME) * COST_PER_INVESTIGATION

# ── Output 1: audit_findings.txt ──
audit = f"""# Audit Findings: Draft Model Evaluation

## Critical Finding 1: Data Quality Issues Not Addressed

The draft computed metrics on {n_raw:,} raw rows without data cleaning.
Two issues inflate the results:

a) **Calibration samples (batch_id=99):** {n_cal} rows are synthetic validation
   data from model development, NOT production predictions. These have
   near-perfect prediction scores and inflate AUC from {auc:.4f} to {dirty_auc:.4f}.
   The dataset_info.txt states batch 99 is for internal calibration only.

b) **Duplicate TransactionIDs:** The scoring pipeline re-processes flagged
   transactions, creating ~{n_raw - n_cal - n_clean} duplicate rows. After
   deduplication (keeping latest scored_at), we have {n_clean:,} unique
   production predictions.

The draft's reported AUC of {dirty_auc:.4f} is computed on dirty data.
The correct clean AUC is {auc:.4f}.

## Critical Finding 2: Accuracy is Misleading

The draft reports accuracy of {acc_50:.1%} as a key metric. With a fraud rate
of only {fraud_rate:.1%}, accuracy alone is not appropriate for evaluating
fraud detection. A model predicting all-legitimate achieves {1-fraud_rate:.1%}.

## Critical Finding 3: Missing Key Metrics

The draft omits Recall, Precision, F1, and PR-AUC. At threshold 0.5:
- Recall: {recall_50:.4f} (misses {1-recall_50:.0%} of fraud)
- These are essential for fraud detection deployment decisions.

## Critical Finding 4: No Cost/Capacity Analysis

The draft ignores the cost parameters ($4,200/missed fraud vs $35/investigation)
and the review team's 1,500 alerts/day capacity. The threshold should be optimized
against these constraints, not defaulted to 0.5.

## Critical Finding 5: Premature Deployment Recommendation

The draft recommends production deployment based on inflated metrics from dirty
data. This recommendation should not be acted upon.
"""
with open("/output/audit_findings.txt", "w") as f:
    f.write(audit)

# ── Output 2: metrics.json ──
metrics = {
    "roc_auc_clean": round(auc, 4),
    "pr_auc_clean": round(pr_auc, 4),
    "recall_at_0.5": round(recall_50, 4),
    f"recall_at_{best_thresh}": round(recall_opt, 4),
    f"precision_at_{best_thresh}": round(precision_opt, 4),
    f"f1_at_{best_thresh}": round(f1_opt, 4),
    "accuracy_misleading": round(acc_50, 4),
    "clean_transaction_count": n_clean,
    "dirty_auc_inflated": round(dirty_auc, 4),
}
with open("/output/metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

# ── Output 3: recommendation.txt ──
rec = f"""# Deployment Recommendation

## Decision: Do Not Deploy As-Is - Data Issues and Threshold Tuning Required

### Data Quality
The predictions export contains calibration samples (batch_id=99) and duplicate
TransactionIDs from re-scoring runs. After cleaning: {n_clean:,} production
predictions (removed {n_cal} calibration + ~{n_raw - n_cal - n_clean} duplicates).

### Corrected Performance
- Clean ROC-AUC: {auc:.4f} (draft reported {dirty_auc:.4f} on dirty data)
- Clean PR-AUC: {pr_auc:.4f}

### Recommended Threshold: {best_thresh}

The cost asymmetry ($4,200/missed fraud vs $35/investigation = 120:1 ratio)
demands a threshold that maximizes recall within the team's review capacity.

At threshold {best_thresh}:
- Recall: {recall_opt:.1%} (vs {recall_50:.1%} at default 0.5)
- Daily flagged: ~{daily_flags_opt:,} (capacity: {DAILY_CAPACITY:,}/day)
- Precision: {precision_opt:.1%}

### Quarterly Financial Impact

| Scenario | Missed Fraud Cost | Investigation Cost | Total |
|----------|------------------|--------------------|-------|
| Threshold 0.5  | ${cost_missed_50:,.0f} | ${cost_invest_50:,.0f} | ${cost_missed_50+cost_invest_50:,.0f} |
| Threshold {best_thresh} | ${cost_missed_opt:,.0f} | ${cost_invest_opt:,.0f} | ${cost_missed_opt+cost_invest_opt:,.0f} |
| Savings | ${cost_missed_50-cost_missed_opt:,.0f} | -${cost_invest_opt-cost_invest_50:,.0f} | ${(cost_missed_50+cost_invest_50)-(cost_missed_opt+cost_invest_opt):,.0f} |

### Next Steps
1. Fix scoring pipeline to exclude calibration batches from production exports
2. Implement deduplication in evaluation pipeline
3. Validate threshold {best_thresh} on time-forward holdout
4. Re-evaluate monthly as fraud patterns shift
"""
with open("/output/recommendation.txt", "w") as f:
    f.write(rec)

print(f"[oracle] Clean AUC={auc:.4f} (dirty={dirty_auc:.4f}), threshold={best_thresh}")
print(f"[oracle] Saved audit_findings.txt, metrics.json, recommendation.txt")
PYEOF
