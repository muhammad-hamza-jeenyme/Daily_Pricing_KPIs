# Cloud Agent automations

## Planned schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:30 AM PKT** (UTC+5 → 06:30 UTC) |
| Job | Query Snowflake → analyse DoD/WoW/MoM → Slack digest/alerts |

## Status

Automation config not yet created. Will add Cursor Cloud Agent / automation definition here once pricing KPIs and queries are agreed.

## Expected inputs

- Validated SQL under `sql/`
- Thresholds from `docs/alert-rules.md`
- Slack channel + bot target
- Snowflake MCP credentials available to the Cloud Agent
