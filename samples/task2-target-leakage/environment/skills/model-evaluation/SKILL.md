---
name: model-evaluation
description: Select and compute appropriate evaluation metrics for classification models, especially with class imbalance. Use when evaluating fraud detection or similar rare-event models.
---

# Model Evaluation

## Class Imbalance Warning

When the positive class is rare (e.g., 3-5% fraud rate):
- **Accuracy is misleading** — a model predicting all-negative gets 95%+ accuracy.
- Use AUC-ROC, PR-AUC, F1, Precision, Recall instead.

## Metric Selection Guide

| Metric | When to use |
|--------|-------------|
| AUC-ROC | Overall ranking quality, threshold-independent |
| PR-AUC | When positive class is very rare |
| F1 | Balance of precision and recall at a fixed threshold |
| Recall | When missing fraud is costly (false negatives) |
| Precision | When false alarms are costly (false positives) |

## Leakage Detection

- If AUC > 0.99, suspect target leakage.
- Check feature-target correlations for suspiciously high values.
- Features derived from post-event data (chargebacks, scores) are leaky.
