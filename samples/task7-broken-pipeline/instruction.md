# Task: Fix This Broken Fraud Detection Pipeline

A fraud detection pipeline runs without crashing, but produces poor
results (AUC = 0.73). Find and fix all bugs in the pipeline.

## Input

- `/data/pipeline.py` — the broken pipeline code
- `/data/train_transaction.csv` — transaction data with `isFraud` label

## Requirements

1. Identify and fix all bugs in the pipeline.
2. Run the corrected pipeline.
3. Report the corrected AUC to `/output/auc.txt`.
4. Write a bug report to `/output/bug_report.txt` listing each bug found,
   why it's wrong, and how you fixed it.
