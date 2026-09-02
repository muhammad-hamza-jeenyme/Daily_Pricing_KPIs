# Project memory — Daily Pricing KPIs

Last updated: 2026-09-02 (discount extension into PRICESHOCKS; BI cutover pending)

## Mission

Fare-integrity tracker. Cloud Agent **11:00 AM PKT**; SA+JO; **two** channel webhook posts + 3-run canvas breakdown.  
Comparisons: DoD / WoW / MoM (vs 28d prior).

## Daily data path (efficient)

1. BI materializes `JEENY_PROD.RIDE.PRICESHOCKS` before 11:00 AM PKT
2. Agent runs **only** `sql/priceshocks_daily_digest.sql` (DoD/WoW/MoM on top of table)
3. Formats two Pulsar posts + canvas from that result

Pending v2 cutover:

1. BI extends `JEENY_PROD.RIDE.PRICESHOCKS` with `DISCOUNT` + `GATE` from
   `sql/bi_priceshocks_discount_extension.sql` (adds `AMOUNT_VALUE`,
   `AVG_VALUE`; does not change CHANNEL/SCENARIO/CAUSE_MIX)
2. Validate yesterday DISCOUNT rows + all GATE rows PASS
3. Re-paste `automations/DAILY_SLACK_INSTRUCTIONS_V2.md`
4. Agent then runs `sql/priceshocks_daily_digest_v2.sql` once per day

Do not change the active automation before DISCOUNT/GATE rows exist. Keep v1
on `sql/priceshocks_daily_digest.sql` until then.

Docs: `docs/priceshocks-table.md` · Active v1 instructions:
`automations/DAILY_SLACK_INSTRUCTIONS.md`

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
- Mandatory gates: applied formula/VAT >=99.9%, identity >=99.99%, every
  promotion config has >=50 uncapped observations. Additional exact
  reconciliation and segment-direction safety checks also fail discount output.
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
- Before BI cutover, keep v1 `DAILY_SLACK_INSTRUCTIONS.md` active.
- After BI validates the companion table, re-paste
  `DAILY_SLACK_INSTRUCTIONS_V2.md`.
