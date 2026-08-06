# Cloud Agent automations

## Why Cloud Agent

The digest must run **even when your laptop is off**. A local Cursor chat / laptop cron cannot do that reliably. Use a **Cursor Cloud Automation** (scheduled Cloud Agent) with Snowflake + Slack access.

## Planned schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:00 AM PKT** → cron `0 6 * * *` (06:00 UTC; confirm editor timezone display) |
| Job | Run fare-integrity digest → DoD/WoW/MoM + vs 14d avg → Slack via **Pulsar webhook** (+ Canvas detail) |

## Watchlist cities

`RUH`, `JED`, `MAD`, `DMM`, `MEC`, `AMM`, `IRB`, `ZRQ`

## Status

- [x] Channel ID decided (`#pricing-alerts` only; ID from `SLACK_CHANNEL_ID` secret)
- [x] Watch rule (yesterday > prior 14d avg)
- [x] DoD/WoW/MoM rollup SQL: `sql/fare_integrity_slack_rollup.sql`
- [x] Bot instructions: `automations/DAILY_SLACK_INSTRUCTIONS.md` (Pulsar webhook only)
- [x] Cloud Automation created (cron `0 6 * * *`); Snowflake MCP preferred, SQL API PAT fallback OK
- [ ] Slack Canvas write for detailed report (Pulsar follow-up fallback until enabled)

## Create automation

Open Automations editor with draft: daily cron 11:00 AM PKT, post only via Pulsar webhook to `#pricing-alerts`, instructions from `automations/DAILY_SLACK_INSTRUCTIONS.md`. Select Snowflake MCP in the editor if not prefilled.
