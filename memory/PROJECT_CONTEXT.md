# Project memory — Daily Pricing KPIs

Last updated: 2026-08-31 (PriceShocks BI table → thin daily digest)

## Mission

Fare-integrity tracker. Cloud Agent **11:00 AM PKT**; SA+JO; **two** channel webhook posts + 3-run canvas breakdown.  
Comparisons: DoD / WoW / MoM (vs 28d prior).

## Daily data path (efficient)

1. BI materializes `JEENY_PROD.RIDE.PRICESHOCKS` before 11:00 AM PKT
2. Agent runs **only** `sql/priceshocks_daily_digest.sql` (DoD/WoW/MoM on top of table)
3. Formats two Pulsar posts + canvas from that result

Docs: `docs/priceshocks-table.md` · Instructions: `automations/DAILY_SLACK_INSTRUCTIONS.md`

## Locked compare (implemented inside BI table)

- `PC_Surcharge_Gross = ROUND(SURCHARGE * IFF(SA, 1.15, 1.0), 2)`
- Shown = `VALUE + VAT(hailing) + PC_Surcharge_Gross`
- Norm receipt = `RR.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`
- **Cumulative / Residual shocks = NET** of spillover recovery
- Prod scenario: `withinA` | `withinB` | `beyondB`

## Spillover double-count (2026-08-19)

Exclude recovery: `prev_outs > 0` AND `ABS(prev_outs − CANCELLATIONFINE) ≤ 0.02`. **LOOKBACK 30d**.  
Docs: `docs/payment-spillover-price-shocks.md`

## Slack / automation

- Channel: `C0BMWLMR03T` · Pulsar webhook + canvas `F0BN0E7RJ31`
- Existing automation only: **Pricing KPI Alerts Slack** @ 11:00 AM PKT
- After each instructions change: **re-paste** `DAILY_SLACK_INSTRUCTIONS.md` into the automation
