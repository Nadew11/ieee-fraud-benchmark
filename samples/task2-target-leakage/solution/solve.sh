#!/usr/bin/env bash
# Oracle solution — explicitly excludes leaky columns before training
set -euo pipefail
mkdir -p /output

python3 - <<'PYEOF'
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score
from sklearn.ensemble import GradientBoostingClassifier
import warnings
warnings.filterwarnings("ignore")

print("[oracle] Loading /data/train_transaction.csv ...")
df = pd.read_csv("/data/train_transaction.csv")
print(f"[oracle] Shape: {df.shape}")

# ── Explicitly exclude leaky columns (derived from target after the fact)
LEAKY_COLS = ["chargeback_amount", "fraud_score", "days_to_chargeback"]
DROP_COLS  = ["TransactionID", "isFraud"] + LEAKY_COLS

print(f"[oracle] Dropping leaky columns: {LEAKY_COLS}")

target = df["isFraud"]
ids    = df["TransactionID"]
feat_df = df.drop(columns=DROP_COLS, errors="ignore")

# Encode categoricals
cat_cols = feat_df.select_dtypes(include="object").columns.tolist()
for col in cat_cols:
    feat_df[col] = pd.Categorical(feat_df[col]).codes.astype(float)
    feat_df.loc[feat_df[col] == -1, col] = np.nan

# Fill remaining NaN with median
feat_df = feat_df.fillna(feat_df.median(numeric_only=True))

X = feat_df.values
y = target.values

# Stratified 80/20 split
X_tr, X_val, y_tr, y_val, id_tr, id_val = train_test_split(
    X, y, ids, test_size=0.2, random_state=42, stratify=y
)
print(f"[oracle] Train: {len(X_tr)}, Val: {len(X_val)}, fraud rate val: {y_val.mean():.3f}")

# Train GBM
model = GradientBoostingClassifier(n_estimators=200, max_depth=4,
                                   learning_rate=0.05, random_state=42)
model.fit(X_tr, y_tr)

probs = model.predict_proba(X_val)[:, 1]
auc   = roc_auc_score(y_val, probs)
print(f"[oracle] Validation AUC: {auc:.4f}")

# Save predictions
pd.DataFrame({"TransactionID": id_val, "fraud_prob": probs}).to_csv(
    "/output/predictions.csv", index=False
)
with open("/output/auc.txt", "w") as f:
    f.write(f"{auc:.4f}\n")

print(f"[oracle] Saved predictions ({len(id_val)} rows) and auc.txt")
PYEOF
