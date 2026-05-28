#!/usr/bin/env bash
set -euo pipefail
mkdir -p /output

python3 - <<'PYEOF'
import pandas as pd
import numpy as np
from openpyxl import Workbook

df = pd.read_csv("/data/transactions.csv")
region_map = pd.read_csv("/data/region_map.csv")
fx_rates = pd.read_csv("/data/fx_rates.csv")
fee_schedule = pd.read_csv("/data/fee_schedule.csv")

# Filter Q4 only
df["transaction_date"] = pd.to_datetime(df["transaction_date"])
df = df[(df["transaction_date"] >= "2023-10-01") & (df["transaction_date"] <= "2023-12-31")]

# Exclude declined
df = df[df["settlement_status"] != "declined"]

# Deduplicate
df = df.drop_duplicates(subset=["TransactionID"], keep="first")

# FX conversion using daily rates with forward fill for gaps
fx_rates["date"] = pd.to_datetime(fx_rates["date"])
fx_pivot = fx_rates.pivot_table(index="date", columns="currency", values="rate_to_usd")
fx_pivot = fx_pivot.sort_index().ffill()

def get_fx_rate(tx_date, currency):
    if currency == "USD":
        return 1.0
    dates = fx_pivot.index[fx_pivot.index <= tx_date]
    if len(dates) == 0:
        return fx_pivot[currency].iloc[0]
    return fx_pivot.loc[dates[-1], currency]

df["fx_rate"] = df.apply(lambda r: get_fx_rate(r["transaction_date"], r["currency"]), axis=1)
df["amt_usd"] = (df["TransactionAmt"] * df["fx_rate"]).round(2)

# Separate transaction types
purchases = df[df["transaction_type"] == "purchase"].copy()
refunds = df[df["transaction_type"] == "refund"].copy()

fraud_purchases = purchases[purchases["isFraud"] == 1].copy()
fraud_refunds = refunds[refunds["isFraud"] == 1].copy()

# Processing fees
fee_map = dict(zip(fee_schedule["merchant_category"], fee_schedule["fee_rate"]))
fraud_purchases["fee_rate"] = fraud_purchases["merchant_category"].map(fee_map).fillna(0.025)
fraud_purchases["processing_fee"] = (fraud_purchases["amt_usd"] * fraud_purchases["fee_rate"]).round(2)

# Join regions
fraud_purchases = fraud_purchases.merge(region_map, on="country_code", how="left")
fraud_purchases["region"] = fraud_purchases["region"].fillna("Other")
fraud_purchases["month"] = fraud_purchases["transaction_date"].dt.strftime("%Y-%m")

fraud_refunds_m = fraud_refunds.merge(region_map, on="country_code", how="left")
fraud_refunds_m["region"] = fraud_refunds_m["region"].fillna("Other")
fraud_refunds_m["month"] = fraud_refunds_m["transaction_date"].dt.strftime("%Y-%m")

# Totals
gross_fraud = fraud_purchases["amt_usd"].sum()
total_recoveries = fraud_refunds["amt_usd"].sum()
total_fees = fraud_purchases["processing_fee"].sum()
net_fraud = gross_fraud - total_recoveries - total_fees

# Monthly Breakdown
monthly = fraud_purchases.groupby(["month", "region"]).agg(
    gross_fraud_usd=("amt_usd", "sum"),
    processing_fees=("processing_fee", "sum"),
    fraud_transaction_count=("TransactionID", "count"),
).reset_index()

refund_monthly = fraud_refunds_m.groupby(["month", "region"]).agg(
    recoveries=("amt_usd", "sum")
).reset_index()

monthly = monthly.merge(refund_monthly, on=["month", "region"], how="left")
monthly["recoveries"] = monthly["recoveries"].fillna(0)
monthly["net_fraud_usd"] = (monthly["gross_fraud_usd"] - monthly["recoveries"] - monthly["processing_fees"]).round(2)
monthly["gross_fraud_usd"] = monthly["gross_fraud_usd"].round(2)
monthly["processing_fees"] = monthly["processing_fees"].round(2)
monthly["avg_ticket_usd"] = (monthly["gross_fraud_usd"] / monthly["fraud_transaction_count"]).round(2)
monthly = monthly.sort_values(["month", "region"])

# Regional Summary
regional = fraud_purchases.groupby("region").agg(
    q4_gross=("amt_usd", "sum"),
    q4_fraud_count=("TransactionID", "count"),
    q4_fees=("processing_fee", "sum"),
).reset_index()

refund_regional = fraud_refunds_m.groupby("region")["amt_usd"].sum().reset_index()
refund_regional.columns = ["region", "region_recoveries"]
regional = regional.merge(refund_regional, on="region", how="left")
regional["region_recoveries"] = regional["region_recoveries"].fillna(0)

regional["q4_net_fraud_usd"] = (regional["q4_gross"] - regional["region_recoveries"] - regional["q4_fees"]).round(2)
regional["q4_avg_ticket_usd"] = (regional["q4_net_fraud_usd"] / regional["q4_fraud_count"]).round(2)
total_net_regional = regional["q4_net_fraud_usd"].sum()
regional["pct_of_total"] = (regional["q4_net_fraud_usd"] / total_net_regional).round(4)
regional = regional.sort_values("q4_net_fraud_usd", ascending=False)

# Build workbook
wb = Workbook()

ws1 = wb.active
ws1.title = "Monthly Breakdown"
ws1.append(["month", "region", "gross_fraud_usd", "net_fraud_usd", "processing_fees",
            "fraud_transaction_count", "avg_ticket_usd"])
for _, r in monthly.iterrows():
    ws1.append([r["month"], r["region"], round(float(r["gross_fraud_usd"]), 2),
                round(float(r["net_fraud_usd"]), 2), round(float(r["processing_fees"]), 2),
                int(r["fraud_transaction_count"]), round(float(r["avg_ticket_usd"]), 2)])

ws2 = wb.create_sheet("Regional Summary")
ws2.append(["region", "q4_net_fraud_usd", "q4_fraud_count", "q4_avg_ticket_usd", "pct_of_total"])
for _, r in regional.iterrows():
    ws2.append([r["region"], round(float(r["q4_net_fraud_usd"]), 2),
                int(r["q4_fraud_count"]), round(float(r["q4_avg_ticket_usd"]), 2),
                round(float(r["pct_of_total"]), 4)])

ws3 = wb.create_sheet("Executive Summary")
ws3["A1"] = "q4_net_fraud_total_usd"
ws3["B1"] = round(float(net_fraud), 2)
ws3["A2"] = "q4_gross_fraud_total_usd"
ws3["B2"] = round(float(gross_fraud), 2)
ws3["A3"] = "total_processing_fees"
ws3["B3"] = round(float(total_fees), 2)
ws3["A4"] = "total_recoveries"
ws3["B4"] = round(float(total_recoveries), 2)

ws3["A6"] = "assumption_number"
ws3["B6"] = "decision"
ws3["C6"] = "rationale"
assumptions = [
    [1, "Exclude declined transactions", "Declined settlements never completed — no actual loss"],
    [2, "Deduplicate on TransactionID", "Duplicate entries with different amounts are processing retries"],
    [3, "Exclude refund transactions from gross", "Refunds represent partial recoveries, subtracted from net"],
    [4, "Chargeback reversals excluded", "Reversals of refunds — do not double-count"],
    [5, "Convert to USD using daily fx_rates.csv", "Forward-fill gaps to get most recent prior rate"],
    [6, "Filter to Q4 only (Oct-Dec 2023)", "Some rows have Q3 dates that must be excluded"],
    [7, "Unmapped countries grouped as Other", "JP has no region mapping — assigned to Other"],
    [8, "Processing fees deducted from net loss", "Fee schedule applied per merchant category"],
]
for a in assumptions:
    ws3.append(a)

wb.save("/output/fraud_report.xlsx")
print(f"[oracle] Net fraud: {net_fraud:.2f}, Gross: {gross_fraud:.2f}")
print(f"[oracle] Recoveries: {total_recoveries:.2f}, Fees: {total_fees:.2f}")
PYEOF
