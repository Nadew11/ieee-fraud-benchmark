#!/usr/bin/env bash
# Oracle: temporal split FIRST, then rolling features using only past data
set -euo pipefail
mkdir -p /output

python3 - <<'PYEOF'
import pandas as pd
import numpy as np
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import roc_auc_score
import warnings
warnings.filterwarnings("ignore")

print("[oracle] Loading /data/transactions.csv ...")
df = pd.read_csv("/data/transactions.csv")
df = df.sort_values("TransactionDT").reset_index(drop=True)
print(f"[oracle] {len(df):,} rows, DT range: {df['TransactionDT'].min()} – {df['TransactionDT'].max()}")

# ── STEP 1: Time-based split (80/20 chronological)
split_idx = int(len(df) * 0.80)
split_dt  = df["TransactionDT"].iloc[split_idx]
print(f"[oracle] Split at index {split_idx}, DT={split_dt}")

train_df = df.iloc[:split_idx].copy()
test_df  = df.iloc[split_idx:].copy()
print(f"[oracle] Train: {len(train_df)}, Test: {len(test_df)}")

# ── STEP 2: Rolling 7-day fraud rate — computed ONLY from past data
WINDOW_SECS = 7 * 86_400  # 7 days in seconds

def compute_rolling_fraud_rate_vectorized(df_sorted, history_df=None):
    """
    Vectorized rolling fraud rate using searchsorted on sorted DT arrays.
    For each row, count fraud in [T - WINDOW, T) using only past data.
    """
    source = history_df if history_df is not None else df_sorted
    src_dts   = source["TransactionDT"].values
    src_fraud = source["isFraud"].values
    src_cumfraud = np.cumsum(src_fraud)

    target_dts = df_sorted["TransactionDT"].values
    rates = np.empty(len(target_dts))

    for i, t in enumerate(target_dts):
        end_idx   = np.searchsorted(src_dts, t, side="left")  # strictly < t
        start_idx = np.searchsorted(src_dts, t - WINDOW_SECS, side="left")
        if end_idx > start_idx:
            fraud_count = src_cumfraud[end_idx - 1] - (src_cumfraud[start_idx - 1] if start_idx > 0 else 0)
            rates[i] = fraud_count / (end_idx - start_idx)
        else:
            rates[i] = 0.035  # global prior
    return rates

print("[oracle] Computing rolling 7-day fraud rate for train set ...")
train_df["rolling_fraud_rate"] = compute_rolling_fraud_rate_vectorized(train_df)

print("[oracle] Computing rolling 7-day fraud rate for test set (using train history) ...")
test_df["rolling_fraud_rate"] = compute_rolling_fraud_rate_vectorized(test_df, history_df=train_df)

# ── STEP 3: Features
cat_map = {v: i for i, v in enumerate(df["ProductCD"].unique())}
def prepare(d):
    X = pd.DataFrame({
        "TransactionAmt":     d["TransactionAmt"],
        "card1":              d["card1"],
        "ProductCD":          d["ProductCD"].map(cat_map).fillna(-1),
        "rolling_fraud_rate": d["rolling_fraud_rate"],
        "hour_of_day":        (d["TransactionDT"] % 86400) / 3600,
        "day_of_week":        (d["TransactionDT"] // 86400) % 7,
        "addr1":              d["addr1"] if "addr1" in d.columns else -1,
        "C1":                 d["C1"] if "C1" in d.columns else -1,
        "C2":                 d["C2"] if "C2" in d.columns else -1,
    }).fillna(-1)
    return X.values

X_tr = prepare(train_df); y_tr = train_df["isFraud"].values
X_te = prepare(test_df);  y_te = test_df["isFraud"].values

# ── STEP 4: Train
print(f"[oracle] Training GBM ...")
model = GradientBoostingClassifier(n_estimators=100, max_depth=3,
                                   learning_rate=0.05, random_state=42)
model.fit(X_tr, y_tr)
probs = model.predict_proba(X_te)[:, 1]
auc   = roc_auc_score(y_te, probs)
print(f"[oracle] Test AUC: {auc:.4f}")

with open("/output/auc.txt", "w") as f:
    f.write(f"{auc:.4f}\n")

methodology = f"""# Methodology: Time-Based Fraud Detection Model

## Rolling Feature Computation
- Feature: 7-day rolling fraud rate per transaction
- Window: 7 days of prior transactions (strictly: TransactionDT < T)
- Cold start: global fraud rate prior (0.035) for early transactions
- CRITICAL: Feature computed ONLY from past data to avoid temporal leakage

## Train/Test Split
- Split type: TEMPORAL (chronological) — NOT random shuffle
- Split point: first 80% of transactions by TransactionDT = {split_dt}
- Train: {len(train_df):,} transactions
- Test:  {len(test_df):,} transactions
- Rolling features for test set: computed using ONLY training data history

## Why Temporal Split?
Using random split would leak future fraud rates into past training examples
via the rolling feature. A transaction in "train" could see future fraud
rates from a "test" transaction that happened earlier in time.

## Model
- Algorithm: Gradient Boosting Classifier
- Features: TransactionAmt, card1, ProductCD, rolling_fraud_rate, hour_of_day,
  day_of_week, addr1, C1, C2
- Test AUC: {auc:.4f}
"""
with open("/output/methodology.txt", "w") as f:
    f.write(methodology)

print("[oracle] Saved auc.txt and methodology.txt")
PYEOF
