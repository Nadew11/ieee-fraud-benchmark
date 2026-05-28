#!/usr/bin/env bash
set -euo pipefail
mkdir -p /output

python3 - <<'PYEOF'
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score
from openpyxl import Workbook
import warnings
warnings.filterwarnings("ignore")

train = pd.read_csv("/data/train_identity.csv")
test  = pd.read_csv("/data/test_identity.csv")

# Detect and normalise schema drift
def normalise_cols(df):
    return df.rename(columns={c: c.replace("-", "_") for c in df.columns})

train = normalise_cols(train)
test  = normalise_cols(test)

TARGET = "isFraud"
DROP   = ["TransactionID", TARGET]
feat_cols = [c for c in train.columns if c not in DROP and c in test.columns]

def encode_and_fill(df, feat_cols, fit_encoders=None):
    out = df[feat_cols].copy()
    encoders = fit_encoders or {}
    for col in out.select_dtypes(include="object").columns:
        out[col] = out[col].fillna("__missing__")
        if col not in encoders:
            le = LabelEncoder()
            out[col] = le.fit_transform(out[col].astype(str))
            encoders[col] = le
        else:
            le = encoders[col]
            out[col] = out[col].astype(str).map(
                lambda x, le=le: le.transform([x])[0] if x in le.classes_ else -1
            )
    out = out.fillna(-999)
    return out.astype(float), encoders

X_all, encoders = encode_and_fill(train, feat_cols)
y_all = train[TARGET].values

# Holdout AUC
X_tr, X_ho, y_tr, y_ho = train_test_split(X_all, y_all, test_size=0.2, random_state=42, stratify=y_all)
model = RandomForestClassifier(n_estimators=100, max_depth=8, random_state=42, n_jobs=-1)
model.fit(X_tr, y_tr)
holdout_auc = roc_auc_score(y_ho, model.predict_proba(X_ho)[:, 1])

# Retrain on all training data
model.fit(X_all, y_all)
X_test, _ = encode_and_fill(test, feat_cols, fit_encoders=encoders)
probs = model.predict_proba(X_test)[:, 1]

# Build workbook
wb = Workbook()
ws1 = wb.active
ws1.title = "Predictions"
ws1.append(["TransactionID", "fraud_prob"])
for tid, p in zip(test["TransactionID"].values, probs):
    ws1.append([int(tid), round(float(p), 4)])

ws2 = wb.create_sheet("Data Quality Report")
ws2["A1"] = "total_train_rows"
ws2["B1"] = len(train)
ws2["A2"] = "total_test_rows"
ws2["B2"] = len(test)
ws2["A3"] = "shared_feature_count"
ws2["B3"] = len(feat_cols)
ws2["A4"] = "model_auc_on_train_holdout"
ws2["B4"] = round(holdout_auc, 4)

ws2["A6"] = "issue_number"
ws2["B6"] = "description"
ws2["C6"] = "resolution"
ws2.append([1, "Column naming drift: train uses underscores (id_01) but test uses hyphens (id-01)",
            "Normalized all column names by replacing hyphens with underscores"])
ws2.append([2, "Missing values present in both datasets across multiple identity columns",
            "Filled categorical NaN with '__missing__' sentinel, numeric NaN with -999"])

wb.save("/output/fraud_risk.xlsx")
print(f"[oracle] Saved fraud_risk.xlsx. Holdout AUC: {holdout_auc:.4f}, {len(probs)} predictions")
PYEOF
