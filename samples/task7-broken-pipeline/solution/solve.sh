#!/usr/bin/env bash
# Oracle: identify and fix all 3 bugs
set -euo pipefail
mkdir -p /output

python3 - <<'PYEOF'
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score
import xgboost as xgb
import warnings
warnings.filterwarnings("ignore")

print("[oracle] Loading /data/train_transaction.csv ...")
df = pd.read_csv("/data/train_transaction.csv")

TARGET = "isFraud"
DROP   = ["TransactionID", TARGET, "ProductCD", "card4", "card6"]
features = [c for c in df.columns if c not in DROP]

X = df[features].fillna(-999).values
y = df[TARGET].values

# FIX 2: Stratified split for imbalanced data
X_train, X_val, y_train, y_val = train_test_split(
    X, y, test_size=0.2, random_state=42,
    stratify=y  # ← FIX: ensures both splits have same fraud rate
)
print(f"[oracle] Train fraud rate: {y_train.mean():.4f}, Val fraud rate: {y_val.mean():.4f}")

# FIX 3: Fit scaler ONLY on training data, then transform both
# (XGBoost is tree-based and doesn't actually need scaling, but fixing the order
#  is the correct pattern for any pipeline that does scale)
scaler = StandardScaler()
X_train = scaler.fit_transform(X_train)   # ← FIX: fit on train only
X_val   = scaler.transform(X_val)         # ← FIX: transform test with train params

# FIX 1: Correct eval_metric for binary classification
model = xgb.XGBClassifier(
    objective="binary:logistic",
    eval_metric="auc",            # ← FIX: was 'rmse', should be 'auc' or 'logloss'
    n_estimators=300,
    max_depth=6,
    learning_rate=0.05,
    subsample=0.8,
    colsample_bytree=0.8,
    random_state=42,
    use_label_encoder=False,
    verbosity=0,
    early_stopping_rounds=20,
)
model.fit(
    X_train, y_train,
    eval_set=[(X_val, y_val)],
    verbose=False,
)

probs = model.predict_proba(X_val)[:, 1]
auc   = roc_auc_score(y_val, probs)
print(f"[oracle] Corrected Validation AUC: {auc:.4f}")

with open("/output/auc.txt", "w") as f:
    f.write(f"{auc:.4f}\n")

bug_report = f"""# Bug Report: Fraud Detection Pipeline v1.2

## Overview
Three bugs were identified that collectively degraded model performance.
After fixes, AUC improved from ~0.73 to {auc:.4f}.

---

## BUG 1 — Wrong eval_metric (Critical)

**Location**: `model = xgb.XGBClassifier(..., eval_metric="rmse", ...)`

**Problem**: The model uses `objective="binary:logistic"` (binary classification)
but evaluates with `eval_metric="rmse"` (regression metric). XGBoost uses the
eval_metric internally for early stopping and tree split scoring. RMSE on 0/1
labels doesn't reflect classification quality — it drives trees toward predicting
the mean (~0.035) rather than discriminating boundaries. This silently degrades
AUC without any error or warning.

**Fix**: Change to `eval_metric="auc"` (or `"logloss"`) to align metric with
the actual learning objective.

---

## BUG 2 — Missing Stratified Split (Important)

**Location**: `train_test_split(X, y, test_size=0.2, random_state=42)`

**Problem**: With only 3.5% fraud rate, a random split can produce a validation
fold with very few positive examples (by chance). This makes AUC estimates
unreliable and can cause the model to not see enough fraud examples during
hyperparameter selection. The missing `stratify=y` argument means class
proportions are not guaranteed to be preserved.

**Fix**: Add `stratify=y` to ensure both train and validation sets maintain
the ~3.5% fraud rate.

---

## BUG 3 — StandardScaler Fitted Before Split (Data Leakage)

**Location**: `scaler = StandardScaler(); X = scaler.fit_transform(X)` (before split)

**Problem**: The scaler is fitted on the FULL dataset including the test set,
then the scaled data is split. This means the scaler's mean/std parameters
are computed using test set statistics — a form of data leakage. At real
inference time, the test data is not available when computing scale parameters,
so this pattern would produce different (and wrong) results in production.

**Fix**: Fit the scaler only on `X_train`, then call `.transform()` (not
`.fit_transform()`) on `X_val`. Alternatively, use a sklearn Pipeline that
applies the scaler correctly within cross-validation.

---

## Summary of Fixes Applied
| Bug | Original | Fixed |
|-----|----------|-------|
| eval_metric | "rmse" | "auc" |
| stratified split | missing | stratify=y |
| scaler scope | fit on full data | fit on train only |

Corrected AUC: {auc:.4f}
"""

with open("/output/bug_report.txt", "w") as f:
    f.write(bug_report)
print("[oracle] Saved auc.txt and bug_report.txt")
PYEOF
