# Existing automation only — Pricing KPI Alerts Slack

**Do not create a new Cloud Automation.** Edit **Pricing KPI Alerts Slack** only.

## What to change on that automation

1. Open existing automation → Edit.
2. Keep **Snowflake**. Remove Cursor Slack post-to-channel if present.
3. **Replace Instructions** with full contents of `automations/DAILY_SLACK_INSTRUCTIONS.md` (PriceShocks thin-digest flow).
4. Secrets: `PULSAR_SLACK_WEBHOOK_URL`, `PULSAR_SLACK_BOT_TOKEN` (+ Snowflake as already set).
5. Schedule: `0 6 * * *` (11:00 AM PKT).
6. Save → optional Run once on **this same** automation (after BI table has yesterday).

## Expected output

- **Channel (Pulsar):** **two** messages — SA then JO — each with 7 monospace KPI tables (`%inc` / DoD / WoW / MoM).
- **Canvas `F0BN0E7RJ31`:** last 3 runs; scenario×dropoff NET tables + last-day exclusive cause mix only.
- Data from `JEENY_PROD.RIDE.PRICESHOCKS` via `sql/priceshocks_daily_digest.sql` — **not** ride-level recompute.
