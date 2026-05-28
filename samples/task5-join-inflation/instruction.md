# Task: Join Tables and Compute Fraud Loss by Device Type

Two tables are provided:

## Input

- `/data/transactions.csv` — `TransactionID`, `isFraud`, `TransactionAmt`
- `/data/identity.csv`     — `TransactionID`, `DeviceType`, `DeviceInfo`

## Requirements

1. Join the two tables on `TransactionID`.
2. Compute the total fraud amount (sum of `TransactionAmt` where `isFraud=1`)
   broken down by `DeviceType`.
3. Save results to `/output/fraud_by_device.csv` with columns:
   `DeviceType`, `total_fraud_amount`, `fraud_transaction_count`.
4. Save the overall total fraud amount to `/output/total_fraud.txt`
   (single float, e.g. `142857.32`).

Some transactions may not have identity records — handle this appropriately.
