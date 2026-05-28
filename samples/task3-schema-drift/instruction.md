# Task: Integrate Two Identity Datasets and Produce Fraud Risk Report

Two identity feature tables from different collection systems need to be merged and used for fraud prediction. Save the results to `/output/fraud_risk.xlsx`.

## Input

- `/data/train_identity.csv` — identity features with label `isFraud` (System A export)
- `/data/test_identity.csv`  — identity features without label (System B export)

Both files contain the same logical features but were exported from different systems.

## Output

The workbook needs two sheets. The names matter because our automated checks depend on them:
- Predictions
- Data Quality Report

For Predictions, use one table starting at row 1 with this header row:
TransactionID, fraud_prob

This sheet must have exactly one row per test identity record.

For Data Quality Report, use this layout:
A1 = total_train_rows, B1 = numeric count
A2 = total_test_rows, B2 = numeric count
A3 = shared_feature_count, B3 = numeric count
A4 = model_auc_on_train_holdout, B4 = numeric AUC value
Row 6 header = issue_number, description, resolution
Starting at row 7, document each data integration issue you found and how you resolved it.

Train a classifier on `train_identity.csv` and generate fraud probability predictions for every row in `test_identity.csv`. The model's AUC on a 20% holdout of the training set must exceed 0.55.

Make sure all numeric values are stored as real numbers in the cells, not text.
