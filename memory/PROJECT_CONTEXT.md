# Project memory — Daily Pricing KPIs

Last updated: 2026-08-09 (daily Pulsar + Canvas digest)

## Mission

Fare-integrity tracker (v1). Cloud Agent **11:00 AM PKT** (`0 6 * * *` UTC); SA+JO.

- Channel (Pulsar webhook): **% fare increase only** — country + cities/Others, DoD/WoW/MoM + vs 7d avg
- Canvas `F0BN0E7RJ31`: multi-KPI watches (yesterday > prior 7d avg)
- MoM = yesterday vs 28 days before

## Locked compare

- `PC_Surcharge_Gross = ROUND(SURCHARGE * IFF(SA, 1.15, 1.0), 2)`
- Shown = `VALUE + VAT(hailing) + PC_Surcharge_Gross`
- Norm receipt = `RR.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`
- issue_type: `matched` | `rounding` | `increase_non_issue` | `increase_pricing` | `decrease_pricing`
- Prod scenario casing: `withinA` | `withinB` | `beyondB`

## SQL

- Channel summary: `sql/fare_integrity_channel_summary.sql`
- Canvas watches: `sql/fare_integrity_slack_rollup.sql` (RUH,JED,MAD,DMM,MEC,AMM,IRB,ZRQ)
- Aggregate debug: `sql/fare_integrity_daily_digest.sql`
- Ride-level: `tables schema/draft SQL.sql`

## Slack / automation

- Channel summary via **`PULSAR_SLACK_WEBHOOK_URL` only** (never Cursor `send_slack_message`)
- Canvas edit via **`PULSAR_SLACK_BOT_TOKEN`** on fixed canvas `F0BN0E7RJ31`
- URL: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31
- Templates: `automations/SLACK_MESSAGE_TEMPLATE.md`, `automations/CANVAS_WATCH_TEMPLATE.md`
- Instructions: `automations/DAILY_SLACK_INSTRUCTIONS.md`
- Spec: `docs/alert-rules.md`

## Last digest (2026-08-09 cron → report_date 2026-08-08)

- SA 16.5% fare ↑ (vs7d -0.7pp); JO 13.4% fare ↑ (vs7d -0.9pp)
- Canvas + Pulsar webhook OK
