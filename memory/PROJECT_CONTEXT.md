# Project memory — Daily Pricing KPIs

Last updated: 2026-08-20 (spillover NET price shocks)

## Mission

Fare-integrity tracker. Cloud Agent **11:00 AM PKT**; SA+JO; channel tables + 3-run canvas.  
Comparisons: DoD / WoW / MoM (vs 28d prior) + 7d avg (channel warn) + 28d±2σ (canvas).

## Locked compare

- `PC_Surcharge_Gross = ROUND(SURCHARGE * IFF(SA, 1.15, 1.0), 2)`
- Shown = `VALUE + VAT(hailing) + PC_Surcharge_Gross`
- Norm receipt = `RR.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`
- **Cumulative / Residual shocks = NET** of spillover recovery (see below)
- issue_type (gross taxonomy still useful): matched / rounding / increase_non_issue / increase_pricing / decrease_pricing
- Prod scenario: `withinA` | `withinB` | `beyondB`
- `withinA` = A-band **or** `ACTUALTIME − APPLIEDESTIMATETIME ≤ MAXWITHINMINUTESVARIANCE`
- `FIXEDSPEEDCAP` / `MAXWITHINMINUTESVARIANCE` on `UPFRONT`

## Spillover double-count (2026-08-19)

Digital pay (ApplePay / CreditCard; cash exempt): underpay ≤ ~1 SAR / ~0.1 JOD → `OUTSTANDINGBALANCE` → recovered next ride as `CANCELLATIONFINE`.  
Exclude recovery: `prev_outs > 0` AND `ABS(prev_outs − CANCELLATIONFINE) ≤ 0.02`. **LOOKBACK 30d** (load-bearing).  
Docs: `docs/payment-spillover-price-shocks.md`

## SQL

- Channel + canvas: `sql/fare_integrity_channel_summary.sql` ← **daily automation**
- Headline net shocks: `sql/daily_price_shock_alert.sql`
- Specs: `docs/alert-rules.md`, `automations/DAILY_SLACK_INSTRUCTIONS.md`

## Slack / automation

- Channel: `C0BMWLMR03T` · Pulsar webhook + canvas `F0BN0E7RJ31`
- Existing automation only: **Pricing KPI Alerts Slack** @ 11:00 AM PKT
