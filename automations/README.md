# Cloud Agent automations

## Why Cloud Agent

The digest must run **even when your laptop is off**. Use a **Cursor Cloud Automation** (scheduled Cloud Agent) with Snowflake + Slack.

## Schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:00 AM PKT** → cron `0 6 * * *` UTC |
| Job | Read `PRICESHOCKS` → two Pulsar posts + canvas |

## Status (2026-09-07)

- [x] Channel `C0BMWLMR03T`
- [x] BI table `JEENY_PROD.RIDE.PRICESHOCKS` full rebuild live
- [x] BI query: `sql/bi_priceshocks_daily.sql`
- [x] Thin digest SQL: `sql/priceshocks_daily_digest_v2.sql`
- [x] Bot instructions: `automations/DAILY_SLACK_INSTRUCTIONS_V2.md`
- [x] Yesterday GATE PASS + DISCOUNT ready (`discount_is_ready=1`)
- [ ] User re-enables **Pricing KPI Alerts Slack** after pasting v2 instructions

## Edit / enable automation

**Do not create a new automation.** Edit **Pricing KPI Alerts Slack** only — see
`automations/USE_EXISTING_AUTOMATION.md`.
