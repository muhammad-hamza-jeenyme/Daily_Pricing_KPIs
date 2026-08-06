# Cloud Agent automations

## Why Cloud Agent

The digest must run **even when your laptop is off**. A local Cursor chat / laptop cron cannot do that reliably. Use a **Cursor Cloud Automation** (scheduled Cloud Agent) with Snowflake + Slack access.

## Planned schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:00 AM PKT** → cron `0 6 * * *` (06:00 UTC; confirm editor timezone display) |
| Job | Run fare-integrity digest → DoD/WoW/MoM + vs 7d avg → Slack `C0BMWLMR03T` (+ optional canvas) |

## Watchlist cities

`RUH`, `JED`, `MAD`, `DMM`, `MEC`, `AMM`, `IRB`, `ZRQ`

## Status

- [x] Channel ID decided (`C0BMWLMR03T` only)
- [x] Major-shift rule (yesterday > prior 7d avg)
- [x] DoD/WoW/MoM rollup SQL: `sql/fare_integrity_slack_rollup.sql`
- [x] Bot instructions: `automations/DAILY_SLACK_INSTRUCTIONS.md`
- [ ] Cloud Automation created & enabled (Snowflake MCP must be selected for Cloud Agents)

## Create automation

**Do not create a new automation.** Edit the existing **Pricing KPI Alerts Slack** automation only — see `automations/USE_EXISTING_AUTOMATION.md`.
