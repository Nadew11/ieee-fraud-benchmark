# Task: Q4 2023 Fraud Loss Workbook for Board Presentation

The CFO needs the quarterly fraud loss workbook for the October board meeting. Save it to `/output/fraud_report.xlsx`.

Reporting period is Q4 2023: October 1 through December 31. The fiscal calendar follows standard US quarters.

All input files are under `/data`:
- `transactions.csv` — raw transaction ledger
- `region_map.csv` — maps country codes to reporting regions
- `fx_rates.csv` — daily exchange rates to USD
- `fee_schedule.csv` — processing fee rates by merchant category

The workbook needs three sheets. The names matter because our automated checks depend on them:
- Monthly Breakdown
- Regional Summary
- Executive Summary

For Monthly Breakdown, use one table starting at row 1 with this header row:
month, region, gross_fraud_usd, net_fraud_usd, processing_fees, fraud_transaction_count, avg_ticket_usd

For Regional Summary, use one table starting at row 1 with this header row:
region, q4_net_fraud_usd, q4_fraud_count, q4_avg_ticket_usd, pct_of_total

For Executive Summary, keep this layout:
A1 = q4_net_fraud_total_usd, B1 = numeric total
A2 = q4_gross_fraud_total_usd, B2 = numeric total
A3 = total_processing_fees, B3 = numeric total
A4 = total_recoveries, B4 = numeric total
Row 6 header = assumption_number, decision, rationale
Starting at row 7, list each business decision you made with a brief rationale.

Net fraud loss is defined as: gross fraud amount minus recoveries (refunds, chargebacks reversed) minus processing fees on fraud transactions. All amounts must be converted to USD using the daily rate from `fx_rates.csv` matching the transaction date. Where no exact date match exists, use the most recent prior rate.

Processing fees are computed per-transaction using the rates in `fee_schedule.csv` matched on `merchant_category`. Apply the fee rate to the USD-converted transaction amount.

Transactions with `settlement_status = 'declined'` should be excluded entirely — declined transactions never settled and represent no actual loss.

Make sure all cost and percentage values are stored as real numbers in the cells, not text.
