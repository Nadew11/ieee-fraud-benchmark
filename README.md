# IEEE Fraud Detection Benchmark

An 8-task evaluation suite that measures whether LLM coding agents can detect, diagnose, and fix **silent data-science bugs** — pipelines that run without error but report inflated or meaningless metrics. Built on the [IEEE-CIS Fraud Detection dataset](https://www.kaggle.com/c/ieee-fraud-detection).

---

## Why silent bugs?

Noisy bugs throw exceptions. Silent bugs ship to production. A pipeline that trains, evaluates, and produces a confidence score — but leaks the label through a post-event feature, or inflates a revenue total via a many-to-many join — is far harder to catch than a `KeyError`. This benchmark targets exactly those: **deterministic defects with seeded verifiers**, each stacked behind a plausible-looking pipeline that a junior engineer (or an LLM agent) would mark as complete.

---

## The 8 Tasks

| # | Task | Bug Type | Primary Trap |
|---|------|----------|--------------|
| 1 | Implicit Nulls | Data Cleaning | Sentinel values (`-999`, `"unknown"`, `""`) hiding in clean-looking columns |
| 2 | Target Leakage | Modeling | Post-event features (`chargeback_amount`, `fraud_score`) included in training |
| 3 | Schema Drift | Integration | Hyphen-vs-underscore column naming + type mismatches across two upstream sources |
| 4 | Metric Selection | Evaluation | Accuracy on 3% fraud-rate data; calibration rows and duplicate IDs ignored |
| 5 | Join Inflation | Analytics | Many-to-many merge on non-unique key silently fans out a financial total |
| 6 | Time-Series Leakage | Modeling | Random train/test split on temporally-ordered transaction data |
| 7 | Broken Pipeline | Debugging | Three independent bugs: wrong `eval_metric`, missing `stratify`, scaler fit on full data |
| 8 | Business Logic | Reporting | FX conversion + refund/fee exclusion + unmapped-region handling in a revenue rollup |

---

## Evaluation Methodology

- **Harness:** [Harbor](https://github.com/xtreamsrl/harbor) / terminus-2
- **Agent under test:** `gemini/gemini-3.5-flash`
- **Verifier:** Binary reward — each task ships a `tests/test.sh` with deterministic, seeded assertions (exact numeric outputs, specific AUC thresholds, required column names)
- **Trials:** 3 per task (24 total trajectories)
- **Sanity gates:** Oracle agent passes 8/8 at reward 1.0; nop agent fails 8/8 at reward 0.0

---

## Results

| Task | pass@1 | pass@3 |
|------|--------|--------|
| 1 — Implicit Nulls | 1.00 | 1.00 |
| 2 — Target Leakage | 1.00 | 1.00 |
| 3 — Schema Drift | 0.67 | 0.96 |
| 4 — Metric Selection | 0.00 | **0.00** |
| 5 — Join Inflation | 1.00 | 1.00 |
| 6 — Time-Series Leakage | 1.00 | 1.00 |
| 7 — Broken Pipeline | 0.33 | 0.70 |
| 8 — Business Logic | 0.33 | 0.70 |
| **Overall** | **62.9%** | **87.5% (7/8 tasks)** |

### 5 Failure Mechanisms Identified

1. **No "outside view" on data quality** — agent processes dirty evaluation data without auditing it first (Task 4, 0/3)
2. **Incomplete bug reporting** — agent *fixes* all bugs in code but fails to enumerate them in its written output (Task 7, 2/3 trials)
3. **Fragile multi-step execution** — agent can complete Task 8 correctly but crashes before producing output in 2/3 trials
4. **Non-deterministic schema resolution** — column harmonization approach varies across runs; 1/3 trials fail silently (Task 3)
5. **Confidence without skepticism** — agent reports high-confidence metrics on corrupted inputs without questioning them

---

## What This Is Useful For

- **Benchmarking LLM coding agents** on tabular data science work beyond "does it run?"
- **Identifying capability gaps** between models on judgment tasks vs. coding tasks
- **Regression testing** model generations — gemini-3.5-flash solved tasks 2.5-flash failed; the hard tasks (4, 7, 8) remain unsolved
- **Research on agent reliability** — the 5 failure modes are stable across trials and grounded in agent-eval literature (DAB, MMTU, AutoDCWorkflow, Shankar et al.)

---

## Repo Structure

```
├── samples/           # 8 task directories (instruction, tests, environment, oracle solution)
├── logs/              # 24 trial directories (full agent trajectory + result.json)
└── report/
    ├── report.md      # Full evaluation report with failure analysis
    ├── difficulty_profile.png
    ├── difficulty_distribution.png
    └── failure_modes.png
```

---

## Scaling Plan

The suite is parameterized to scale to ~1000 tasks across 5 axes: **failure mode × domain × data shape × skill emphasis × difficulty band** (10×10×5×4×3 = 6000 cells). Each task is template-driven with seeded data generators, automated rubric validation, and oracle/nop gating before inclusion.

---

*Author: Nadew Alem · Dataset: [IEEE-CIS Fraud Detection](https://www.kaggle.com/c/ieee-fraud-detection)*
