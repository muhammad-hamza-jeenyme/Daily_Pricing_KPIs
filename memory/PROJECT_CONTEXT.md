# Project memory — Daily Pricing KPIs

Last updated: 2026-08-05 (14d watch rule + Canvas detail; live cron 11:00 AM PKT; Snowflake MCP required)

## Mission

Fare-integrity tracker (v1). Cloud Agent **11:00 AM PKT**; SA+JO; digest **day × AREA_CODE × UPFRONTSCENARIO × issue_type**; **29** complete days; DoD/WoW/MoM (vs 28d prior).

## Locked compare

- `PC_Surcharge_Gross = ROUND(SURCHARGE * IFF(SA, 1.15, 1.0), 2)`
- Shown = `VALUE + VAT(hailing) + PC_Surcharge_Gross`
- Norm receipt = `RR.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`
- issue_type: `matched` | `rounding` | `increase_non_issue` | `increase_pricing` | `decrease_pricing`
- Prod scenario casing: `withinA` | `withinB` | `beyondB`

## SQL

- Aggregate: `sql/fare_integrity_daily_digest.sql`
- Slack rollup: `sql/fare_integrity_slack_rollup.sql` ← **run this for daily alerts**
- Ride-level: `tables schema/draft SQL.sql`
- Validation notes: `docs/validation-run-2026-08-04.md`

## Validation (2026-08-04)

- Query succeeded on Snowflake MCP
- Window: 2026-07-06 → 2026-08-03 (~5.18M rides)
- Yesterday top `increase_pricing` areas: AMM, JED, RUH, …

## Slack / automation (locked 2026-08-04)

- Channel: `C0BMWLMR03T`
- Cities: RUH, JED, MAD, DMM, MEC, AMM, IRB, ZRQ
- Watch: yesterday KPI > avg of prior **14** complete days; always name Area_Code
- Detailed report: channel **Canvas** (fallback: thread with full table)
- Cron: **11:00 AM PKT** = `0 6 * * *` UTC (matches live automation trigger)
- **Requires Snowflake MCP** on the Cloud Automation (without it, post failure notice only)
- Spec: `docs/alert-rules.md`

## Next

1. Attach Snowflake MCP to Cloud Automation and re-run daily digest
2. Enable Slack Canvas create/update for detailed city report
