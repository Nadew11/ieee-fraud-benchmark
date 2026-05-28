# Task: Audit a Fraud Model Evaluation Before Quarterly Review

A junior analyst prepared a draft evaluation of our fraud detection model
for the quarterly business review. The fraud operations team needs to
decide whether to deploy this model to production. Your job is to audit
the analyst's draft, identify any errors or gaps in the evaluation, and
produce a corrected analysis with a deployment recommendation.

## Input

- `/data/predictions.csv` — model predictions on a held-out test set.
  Key columns: `TransactionID`, `y_true`, `y_pred_prob`. The scoring
  pipeline export may include additional metadata columns.
- `/data/dataset_info.txt` — technical details about the scoring pipeline
- `/data/draft_evaluation.txt` — the junior analyst's draft report
- `/data/cost_assumptions.txt` — financial parameters from the fraud ops team

## Deliverables

You must produce three output files:

### 1. `/output/audit_findings.txt`

Review the junior analyst's draft evaluation. Identify specific errors,
misleading claims, or missing analysis. For each finding, explain what
is wrong and why it matters. Be specific — cite the claim from the draft
and explain the correct interpretation.

### 2. `/output/metrics.json`

Compute a corrected set of performance metrics. Save as a JSON object
with metric names as keys and float values. Include at least three
metrics that you believe are appropriate for this use case. Show your
work — the fraud ops team will scrutinize these numbers.

### 3. `/output/recommendation.txt`

Write a deployment recommendation for the fraud ops team. Address:
- Whether the model should be deployed as-is, tuned, or rejected
- What classification threshold you recommend and why
- The expected financial impact per quarter (use the cost parameters
  provided in `cost_assumptions.txt`)
- How many transactions would be flagged daily at your recommended
  threshold, and whether that fits within the team's review capacity
