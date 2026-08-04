# Cloud Agent automations

## Planned schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:30 AM PKT** (UTC+5 → 06:30 UTC) |
| Job | Run `sql/fare_integrity_daily_digest.sql` → DoD/WoW/MoM → Slack |

## Status

- SQL validated on Snowflake MCP (2026-08-04)
- Automation config not yet created
- Next: schedule + Slack message template + alert thresholds (`docs/alert-rules.md`)
