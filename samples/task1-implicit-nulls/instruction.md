# Task: Clean Fraud Identity Dataset for Modeling

`/data/train_identity.csv` contains identity features from a fraud detection
system. Clean this dataset and prepare it for downstream machine learning.

## Input

- `/data/train_identity.csv` — raw identity data with 41 columns

## Requirements

1. Handle all missing values appropriately.
2. Ensure correct data types for every column before saving.
3. Remove any duplicate records based on `TransactionID`.
4. Output the cleaned dataset to `/output/cleaned.csv`.

## Output

- `/output/cleaned.csv` — cleaned dataset, same schema as input

Do not drop columns. Do not drop rows unless they are true duplicates.
Preserve all legitimate records.
