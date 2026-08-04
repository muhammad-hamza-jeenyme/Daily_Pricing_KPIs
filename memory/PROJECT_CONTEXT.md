# Project memory — Daily Pricing KPIs

Last updated: 2026-08-04 (Snowflake digest validated + repo sync)

## Mission

Fare-integrity tracker (v1). Cloud Agent **11:30 AM PKT**; SA+JO; digest **day × AREA_CODE × UPFRONTSCENARIO × issue_type**; **29** complete days; DoD/WoW/MoM (vs 28d prior).

## Locked compare

- `PC_Surcharge_Gross = ROUND(SURCHARGE * IFF(SA, 1.15, 1.0), 2)`
- Shown = `VALUE + VAT(hailing) + PC_Surcharge_Gross`
- Norm receipt = `RR.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`
- issue_type: `matched` | `rounding` | `increase_non_issue` | `increase_pricing` | `decrease_pricing`
- Prod scenario casing: `withinA` | `withinB` | `beyondB`

## SQL

- Aggregate: `sql/fare_integrity_daily_digest.sql` ← **run this**
- Ride-level: `tables schema/draft SQL.sql`
- Validation notes: `docs/validation-run-2026-08-04.md`

## Validation (2026-08-04)

- Query succeeded on Snowflake MCP
- Window: 2026-07-06 → 2026-08-03 (~5.18M rides)
- Yesterday top `increase_pricing` areas: AMM, JED, RUH, …

## Next

DoD/WoW/MoM rollup + Slack thresholds + Cloud Agent schedule.
