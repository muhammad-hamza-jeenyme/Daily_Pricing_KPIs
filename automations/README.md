# Cloud Agent automations

## Why Cloud Agent

The digest must run **even when your laptop is off**. A local Cursor chat / laptop cron cannot do that reliably. Use a **Cursor Cloud Automation** (scheduled Cloud Agent) with Snowflake + Slack access.

## Planned schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:30 AM PKT** → cron `30 6 * * *` (06:30 UTC; confirm editor timezone display) |
| Job | Run fare-integrity rollup → DoD/WoW/MoM + vs 14d avg → Slack `C0BMWLMR03T` + Canvas detail |

## Watchlist cities

SA: `RUH`, `JED`, `MAD`, `DMM`, `MEC`  
JO: `AMM`, `IRB`, `ZRQ`

## Status

- [x] Channel ID decided (`C0BMWLMR03T` only)
- [x] Watch rule (yesterday > prior 14d avg)
- [x] DoD/WoW/MoM rollup SQL: `sql/fare_integrity_slack_rollup.sql`
- [x] Bot instructions: `automations/DAILY_SLACK_INSTRUCTIONS.md`
- [x] Canvas detail requirement documented
- [ ] Cloud Automation has **Snowflake MCP** selected and enabled
- [ ] Slack Canvas create/update available to the automation

## Create / fix automation

1. Open Automations editor for this job.
2. Schedule: daily **11:30 AM PKT** (`30 6 * * *` UTC).
3. Instructions: `automations/DAILY_SLACK_INSTRUCTIONS.md`.
4. **Select Snowflake MCP** (`sql_exec_tool`) — required. Without it the agent can only post a failure notice.
5. Slack destination must remain `#pricing-alerts` / `C0BMWLMR03T` only.
6. Prefer enabling Slack Canvas write so members can open the detailed report from the channel Canvas section.
