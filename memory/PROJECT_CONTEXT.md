# Project memory — Daily Pricing KPIs

Last updated: 2026-09-07 (v2 cutover — BI full PRICESHOCKS rebuild live)

## Mission

Fare-integrity tracker. Cloud Agent **11:00 AM PKT**; SA+JO; **two** channel webhook posts + 3-run canvas breakdown.  
Comparisons: DoD / WoW / MoM (vs 28d prior).

## Daily data path (efficient) — ACTIVE

1. BI runs **one** query `sql/bi_priceshocks_daily.sql`, deletes prior
   `JEENY_PROD.RIDE.PRICESHOCKS` rows, inserts full result (30-day window)
   before 11:00 AM PKT — CHANNEL + SCENARIO + CAUSE_MIX + DISCOUNT + GATE
2. Agent runs **`sql/priceshocks_daily_digest_v2.sql`** once
3. Formats two Pulsar posts + canvas (fare tables + discount block when gates PASS)

Validated 2026-09-07 against live table + `tables schema/Ride PriceShocks.csv`:
- 30 dates through 2026-09-06; all five families present
- CHANNEL city buckets present; yesterday GATE all PASS
- Guard: `is_ready=1`, `discount_is_ready=1`

Docs: `docs/priceshocks-table.md` · BI handoff:
`docs/price-shock-discounts-bi-handoff.md` · Active instructions:
`automations/DAILY_SLACK_INSTRUCTIONS_V2.md`

## Locked compare (implemented inside BI table)

- `PC_Surcharge_Gross = ROUND(SURCHARGE * IFF(SA, 1.15, 1.0), 2)`
- Shown = `VALUE + VAT(hailing) + PC_Surcharge_Gross`
- Norm receipt = `RR.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`
- **Cumulative / Residual shocks = NET** of spillover recovery
- Prod scenario: `withinA` | `withinB` | `beyondB`

## Discount view (locked 2026-09-02)

- Keep every existing `fare_diff` headline/bucket unchanged.
- Add passenger-experienced:
  `net_fare_diff = charged_net - (pc_shown - expected_disc_gross)`.
- `d_discount = expected_disc_gross - actual_disc_gross`.
- Assert `net_fare_diff = fare_diff + d_discount` at 0.011 tolerance.
- Voucher cap is VAT-inclusive; promotion-engine inferred cap is ex-VAT.
- Build quote base component-wise; gross discount by separately rounded VAT.
- Final discountable base includes `WAITINGTIMEFEE`, excludes cancellation fine
  and wallet balance.
- Six segments: voucher/promo capped or pct-bound, discount_no_source,
  no_discount.
- Voucher takes precedence; never sum voucher + promotion engine.
- Promo campaigns pooled in DISCOUNT/GATE (no per-PROMOTIONID rows).
- Slack keeps 7 current fare tables and appends post-discount exposure per
  market. Canvas adds discount segment tables.
- Specs: `docs/price-shock-discounts-implementation-spec.md` and
  `docs/price-shock-discounts-bi-handoff.md`.

## Spillover double-count (2026-08-19)

Exclude recovery: `prev_outs > 0` AND `ABS(prev_outs − CANCELLATIONFINE) ≤ 0.02`. **LOOKBACK 30d**.  
Docs: `docs/payment-spillover-price-shocks.md`

## Slack / automation

- Channel: `C0BMWLMR03T` · Pulsar webhook + canvas `F0BN0E7RJ31`
- Existing automation only: **Pricing KPI Alerts Slack** @ 11:00 AM PKT
- **Active instructions:** `automations/DAILY_SLACK_INSTRUCTIONS_V2.md`
- Enable steps: `automations/USE_EXISTING_AUTOMATION.md`
- v1 (`DAILY_SLACK_INSTRUCTIONS.md` + `priceshocks_daily_digest.sql`) superseded
