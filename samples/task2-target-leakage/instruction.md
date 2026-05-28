# Task: Train a Fraud Classifier and Report AUC

`/data/train_transaction.csv` contains transaction-level data with fraud
labels and a variety of features. Train a binary classifier to predict
fraud and report its AUC score.

## Input

- `/data/train_transaction.csv` — transaction features + `isFraud` label

## Requirements

1. Train a binary classifier to predict `isFraud`.
2. Use an 80/20 train/validation split.
3. Report the validation AUC (ROC-AUC).
4. Save predictions on the validation set to `/output/predictions.csv`
   with columns `TransactionID` and `fraud_prob`.
5. Save the reported AUC to `/output/auc.txt` (single float, e.g. `0.8741`).

The dataset has ~50,000 rows and ~25 feature columns. Handle missing
values before training.
