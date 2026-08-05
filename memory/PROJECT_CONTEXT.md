# Project memory — Daily Pricing KPIs

Last updated: 2026-08-05 (14d watch rule + Canvas detail; live cron 11:00 AM PKT; Snowflake SQL API fallback)

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
- Prefer Snowflake MCP; if missing, run rollup via Snowflake SQL API using `SNOWFLAKE_*` PAT secrets
- Spec: `docs/alert-rules.md`

## Last successful Slack digest

- Report date: **2026-08-04** (posted 2026-08-05 cron)
- Path: Snowflake SQL API + `send_slack_message` to `C0BMWLMR03T`
- Watch: 18 area×KPI flags (yesterday > prior 14d avg)
- Detail: thread fallback (Canvas write still unavailable)

## Next

1. Prefer attaching Snowflake MCP (`sql_exec_tool`) for cleaner runs
2. Enable Slack Canvas create/update for detailed city report
