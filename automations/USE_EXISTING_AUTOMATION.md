# Existing automation only — Pricing KPI Alerts Slack

**Do not create a new Cloud Automation.** Edit **Pricing KPI Alerts Slack** only.

## What to change on that automation

1. Open existing automation → Edit.
2. Keep **Snowflake**. Remove Cursor Slack post-to-channel if present.
3. Replace **instructions** with contents of `automations/DAILY_SLACK_INSTRUCTIONS.md`.
4. Secrets: `PULSAR_SLACK_WEBHOOK_URL` (+ Snowflake as already set).
5. Schedule: `0 6 * * *` (11:00 AM PKT).
6. Save → Run once on **this same** automation.

## Expected output
- **Channel (Pulsar):** short SA/JO `% fare increase` + city tables + Others (bizfin-style).
- **Canvas:** detailed watches (DX-style template).
- Not a noisy multi-KPI wall of text.
