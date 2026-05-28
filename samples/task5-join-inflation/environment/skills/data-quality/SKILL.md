---
name: data-quality
description: Detect and handle data quality issues including sentinel nulls, schema drift, duplicate records, and type corruption. Use before any modeling step.
---

# Data Quality

## Sentinel Null Detection

Standard `isna()` misses these common sentinel values:
- Numeric: -999, -1, 0, 9999
- String: 'unknown', 'N/A', 'missing', '', 'null', 'none'
- Check with value_counts() and describe() first.

## Schema Drift

- Column names may differ between train/test (underscores vs hyphens).
- Normalize column names: `df.columns = df.columns.str.replace('-', '_')`.
- Verify column count and dtypes match between datasets.

## Duplicate Detection

- Check `df.duplicated(subset=[key]).sum()` before any join or merge.
- Duplicates in join keys cause row inflation (1-to-many becomes many-to-many).
- Always deduplicate before joining.
