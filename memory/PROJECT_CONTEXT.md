# Project memory — Daily Pricing KPIs

Last updated: 2026-08-06 (cron #3 — Canvas update succeeded)

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
- Canvas: `PULSAR_SLACK_BOT_TOKEN` with `canvases:read` + `canvases:write` (working as of cron #3)

## Last cron run (2026-08-06, branch `cursor/pricing-fare-integrity-daily-5122`)

- report_date **2026-08-05**
- Snowflake SQL API OK (MCP still not attached)
- Pulsar short channel summary posted (HTTP 200)
- Canvas `F0BN0E7RJ31` updated successfully via `canvases.edit` `insert_at_start`

## Pulsar + Canvas (locked 2026-08-06)

- Schedule: **11:00 AM PKT** (`0 6 * * *` UTC)
- Channel summary SQL: `sql/fare_integrity_channel_summary.sql` (% fare ↑ only)
- Watches SQL: `sql/fare_integrity_slack_rollup.sql`
- Channel post: `PULSAR_SLACK_WEBHOOK_URL` only (never Cursor send_slack_message for digest)
- Fixed Canvas: `F0BN0E7RJ31` — https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31
- Canvas edit: `PULSAR_SLACK_BOT_TOKEN` → `canvases.sections.lookup` + `canvases.edit`
