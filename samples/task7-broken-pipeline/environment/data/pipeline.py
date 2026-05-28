#!/usr/bin/env python3
"""
Fraud Detection Pipeline — v1.2
Author: junior_engineer@payments.co
"""
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score
import xgboost as xgb
import warnings
warnings.filterwarnings("ignore")

# Load data
print("Loading data...")
df = pd.read_csv("/data/train_transaction.csv")
print(f"Shape: {df.shape}")

# Features / target
TARGET = "isFraud"
DROP = ["TransactionID", TARGET, "ProductCD", "card4", "card6"]
features = [c for c in df.columns if c not in DROP]

X = df[features].fillna(-999).values
y = df[TARGET].values

# Scale features for better model performance
scaler = StandardScaler()
X = scaler.fit_transform(X)

# Split into train and validation
X_train, X_val, y_train, y_val = train_test_split(
    X, y, test_size=0.2, random_state=42
)
print(f"Train: {len(X_train)}, Val: {len(X_val)}")
print(f"Val fraud rate: {y_val.mean():.4f}")

# Train XGBoost
model = xgb.XGBClassifier(
    objective="binary:logistic",
    eval_metric="rmse",
    n_estimators=300,
    max_depth=6,
    learning_rate=0.05,
    subsample=0.8,
    colsample_bytree=0.8,
    random_state=42,
    use_label_encoder=False,
    verbosity=0,
)
model.fit(
    X_train, y_train,
    eval_set=[(X_val, y_val)],
    verbose=False,
)

probs = model.predict_proba(X_val)[:, 1]
auc   = roc_auc_score(y_val, probs)
print(f"\nValidation AUC: {auc:.4f}")
print("Note: AUC seems low — unclear why model isn't learning better")
