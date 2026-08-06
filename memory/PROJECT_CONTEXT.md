# Project memory — Daily Pricing KPIs

Last updated: 2026-08-06 (channel summary + Canvas watches path)

## Mission

Fare-integrity tracker (v1). Cloud Agent **11:00 AM PKT**; SA+JO.
Channel: **% fare increase only** (country + cities/Others). Watches detail: **Canvas**.

## Locked compare

- `PC_Surcharge_Gross = ROUND(SURCHARGE * IFF(SA, 1.15, 1.0), 2)`
- Shown = `VALUE + VAT(hailing) + PC_Surcharge_Gross`
- Norm receipt = `RR.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`
- issue_type: `matched` | `rounding` | `increase_non_issue` | `increase_pricing` | `decrease_pricing`
- Prod scenario casing: `withinA` | `withinB` | `beyondB`

## SQL

- Channel summary: `sql/fare_integrity_channel_summary.sql`
- Canvas watches rollup: `sql/fare_integrity_slack_rollup.sql`
- Full grain digest: `sql/fare_integrity_daily_digest.sql`
- Ride-level: `tables schema/draft SQL.sql`

## Slack / automation (locked 2026-08-06)

- Channel: `#pricing-alerts` via **Pulsar webhook only**
- Templates: `automations/SLACK_MESSAGE_TEMPLATE.md`, `automations/CANVAS_WATCH_TEMPLATE.md`
- Cities SA: RUH, JED, MAD, DMM, MEC + Others | JO: AMM, IRB, ZRQ + Others
- Major shift / Watch: yesterday > prior **7** complete days average
- Canvas needs `PULSAR_SLACK_BOT_TOKEN` (missing as of 2026-08-06)

## Last cron run (2026-08-06)

- report_date **2026-08-05**
- Snowflake SQL API OK (MCP still not attached)
- Pulsar short channel summary posted
- Canvas skipped (no bot token); watches not dumped to channel
