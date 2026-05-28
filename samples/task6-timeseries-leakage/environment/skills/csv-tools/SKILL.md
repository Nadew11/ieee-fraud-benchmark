---
name: csv-tools
description: Parse, validate, and transform CSV datasets with deterministic outputs. Use for schema checks, joins, grouped metrics, and stable exports.
---

# CSV Tools

Use this skill for reliable CSV pipelines.

## Checklist

- Validate required columns exist before calculations.
- Parse numeric fields explicitly; don't assume dtype.
- Check for duplicate keys before joins.
- Sort output rows by stable keys for deterministic output.

## Common Pitfalls

- Joining on a key with duplicates inflates row counts silently.
- Mixed types in a column (int vs float vs string) cause silent NaN.
- Empty strings are not the same as NaN — check both.
