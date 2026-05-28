---
name: pandas-patterns
description: Reliable pandas patterns for data manipulation, type handling, and reproducible transforms. Use when working with DataFrames.
---

# Pandas Patterns

## Type Safety

- Always check `df.dtypes` before arithmetic.
- Cast TransactionID-like columns to int64, not float.
- Use `pd.to_numeric(errors='coerce')` for mixed columns.

## Missing Value Detection

- `df.isna()` misses sentinel values like -999, 'unknown', or empty strings.
- Always check for domain-specific sentinel values explicitly.
- Replace sentinels with `np.nan` before using `dropna()` or `fillna()`.

## Deduplication

- Use `df.drop_duplicates(subset=[key], keep='first')`.
- Always verify row count before and after dedup.

## Temporal Splits

- Sort by time column before splitting.
- Use index-based split, not `train_test_split()` (which shuffles).
- Compute rolling features only from past data (strict `<`, not `<=`).
