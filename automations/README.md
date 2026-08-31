# Cloud Agent automations

## Why Cloud Agent

The digest must run **even when your laptop is off**. Use a **Cursor Cloud Automation** (scheduled Cloud Agent) with Snowflake + Slack.

## Schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:00 AM PKT** → cron `0 6 * * *` UTC |
| Job | Read `PRICESHOCKS` → format DoD/WoW/MoM → two Pulsar posts + canvas |

## Status

- [x] Channel `C0BMWLMR03T`
- [x] BI table `JEENY_PROD.RIDE.PRICESHOCKS` (refresh before 11:00 AM PKT)
- [x] Thin digest SQL: `sql/priceshocks_daily_digest.sql`
- [x] Bot instructions: `automations/DAILY_SLACK_INSTRUCTIONS.md`
- [ ] Re-paste instructions into **Pricing KPI Alerts Slack** after this change

## Edit automation

**Do not create a new automation.** Edit **Pricing KPI Alerts Slack** only — see `automations/USE_EXISTING_AUTOMATION.md`.
