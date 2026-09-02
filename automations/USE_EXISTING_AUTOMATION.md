# Existing automation only — Pricing KPI Alerts Slack

**Do not create a new Cloud Automation.** Edit **Pricing KPI Alerts Slack** only.

## What to change on that automation

1. Open existing automation → Edit.
2. Keep **Snowflake**. Remove Cursor Slack post-to-channel if present.
3. Confirm BI has MERGEd `DISCOUNT` + `GATE` into `JEENY_PROD.RIDE.PRICESHOCKS`,
   yesterday exists, and every GATE row passes (`rides_flagged = 1`).
4. **Replace Instructions** with full contents of
   `automations/DAILY_SLACK_INSTRUCTIONS_V2.md` (single-table thin-digest flow).
5. Secrets: `PULSAR_SLACK_WEBHOOK_URL`, `PULSAR_SLACK_BOT_TOKEN` (+ Snowflake as already set).
6. Schedule: `0 6 * * *` (11:00 AM PKT).
7. Save → Run once on **this same** automation to validate the cutover.

## Expected output

- **Channel (Pulsar):** **two** messages — SA then JO — each with 7
  unchanged monospace KPI tables plus its post-discount exposure block.
- **Canvas `F0BN0E7RJ31`:** last 3 runs; scenario×dropoff NET tables,
  last-day exclusive cause mix, and discount-segment table.
- Data from `JEENY_PROD.RIDE.PRICESHOCKS` via `sql/priceshocks_daily_digest_v2.sql`
  — **not** ride-level recompute.

Do not re-paste before DISCOUNT/GATE rows exist. The currently active
instructions may remain on `sql/priceshocks_daily_digest.sql` until then.
