# Cloud Agent automations

## Why Cloud Agent

The digest must run **even when your laptop is off**. A local Cursor chat / laptop cron cannot do that reliably. Use a **Cursor Cloud Automation** (scheduled Cloud Agent) with Snowflake + Slack access.

## Planned schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:00 AM PKT** → cron `0 6 * * *` (06:00 UTC) |
| Job | Channel summary (% fare ↑) via Pulsar webhook + Canvas watches detail |

## Watchlist cities

`RUH`, `JED`, `MAD`, `DMM`, `MEC`, `AMM`, `IRB`, `ZRQ` (+ Others buckets in channel summary)

## Status

- [x] Channel decided (`#pricing-alerts` only)
- [x] Major-shift rule (yesterday > prior 7d avg)
- [x] Channel summary SQL: `sql/fare_integrity_channel_summary.sql`
- [x] Rollup SQL (Canvas watches): `sql/fare_integrity_slack_rollup.sql`
- [x] Templates: `SLACK_MESSAGE_TEMPLATE.md`, `CANVAS_WATCH_TEMPLATE.md`
- [x] Bot instructions: `automations/DAILY_SLACK_INSTRUCTIONS.md`
- [ ] `PULSAR_SLACK_BOT_TOKEN` for Canvas create
- [ ] Snowflake MCP attached (SQL API + PAT fallback works)

## Create automation

Open Automations editor with draft: daily cron 11:00 AM PKT, Pulsar webhook + Canvas, instructions from `automations/DAILY_SLACK_INSTRUCTIONS.md`.
