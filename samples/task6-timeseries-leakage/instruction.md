# Task: Build a Fraud Detection Model with Engineered Features

Transaction data with temporal ordering is provided. Build a fraud classifier
that uses engineered features to improve prediction accuracy.

## Input

- `/data/transactions.csv` — `TransactionID`, `TransactionDT`, `isFraud`,
  `TransactionAmt`, `card1`, `ProductCD`, `addr1`, `C1`, `C2`

The `TransactionDT` column represents seconds elapsed from a reference point.
Transactions span approximately 6 months.

## Requirements

1. Engineer at least one feature derived from historical transaction patterns.
2. Split the data appropriately for model evaluation.
3. Train a binary classifier on the training portion.
4. Report test set AUC to `/output/auc.txt` (single float).
5. Save a methodology note to `/output/methodology.txt` explaining your
   feature engineering approach and evaluation strategy.

Choose a split strategy that reflects how the model would be deployed
in production — the model must predict future transactions it has never seen.
