#!/usr/bin/env bash
# Oracle: deduplicate identity before join
set -euo pipefail
mkdir -p /output

python3 - <<'PYEOF'
import pandas as pd
import numpy as np

print("[oracle] Loading data ...")
tx    = pd.read_csv("/data/transactions.csv")
ident = pd.read_csv("/data/identity.csv")

print(f"[oracle] Transactions: {len(tx):,}, Identity: {len(ident):,}")

# ── Key insight: check for duplicates in identity before joining
n_dupes = ident.duplicated(subset=["TransactionID"]).sum()
print(f"[oracle] Duplicate TransactionIDs in identity: {n_dupes}")

# Deduplicate identity on TransactionID (keep first occurrence)
ident_deduped = ident.drop_duplicates(subset=["TransactionID"], keep="first")
print(f"[oracle] After dedup: {len(ident_deduped):,} identity rows")

# Left join (keep all transactions, match identity where available)
merged = tx.merge(ident_deduped, on="TransactionID", how="left")
print(f"[oracle] Merged rows: {len(merged):,} (should equal {len(tx):,})")

# Compute fraud by device type
fraud_df = merged[merged["isFraud"] == 1].copy()
result = (fraud_df
          .groupby("DeviceType", dropna=False)
          .agg(
              total_fraud_amount=("TransactionAmt", "sum"),
              fraud_transaction_count=("TransactionID", "count")
          )
          .reset_index())
result["total_fraud_amount"] = result["total_fraud_amount"].round(2)

result.to_csv("/output/fraud_by_device.csv", index=False)
print(f"[oracle] fraud_by_device.csv:\n{result}")

total = fraud_df["TransactionAmt"].sum()
with open("/output/total_fraud.txt", "w") as f:
    f.write(f"{total:.2f}\n")
print(f"[oracle] Total fraud amount: ${total:,.2f}")
PYEOF
