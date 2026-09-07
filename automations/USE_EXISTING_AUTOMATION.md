# Existing automation only — Pricing KPI Alerts Slack

**Do not create a new Cloud Automation.** Edit **Pricing KPI Alerts Slack** only.

## Cutover complete (2026-09-07)

BI full rebuild of `JEENY_PROD.RIDE.PRICESHOCKS` is live
(`sql/bi_priceshocks_daily.sql`: CHANNEL + SCENARIO + CAUSE_MIX + DISCOUNT + GATE).
Yesterday (2026-09-06) validated: city CHANNEL rows present; all GATE rows PASS.

## What to change on that automation

1. Open existing automation → Edit.
2. Keep **Snowflake**. Remove Cursor Slack post-to-channel if present.
3. **Replace Instructions** with full contents of
   `automations/DAILY_SLACK_INSTRUCTIONS_V2.md`.
4. Secrets: `PULSAR_SLACK_WEBHOOK_URL`, `PULSAR_SLACK_BOT_TOKEN` (+ Snowflake as already set).
5. Schedule: `0 6 * * *` (11:00 AM PKT).
6. **Re-enable** the automation (it was paused for the BI cutover).
7. Optional: **Run once** on this same automation to validate before waiting for schedule.

## Expected output

- **Channel (Pulsar):** **two** messages — SA then JO — each with 7
  city-level monospace KPI tables plus post-discount exposure block.
- **Canvas `F0BN0E7RJ31`:** last 3 runs; scenario×dropoff NET tables,
  last-day exclusive cause mix, and discount-segment table.
- Data from `JEENY_PROD.RIDE.PRICESHOCKS` via `sql/priceshocks_daily_digest_v2.sql`
  — **not** ride-level recompute.

## Do not use

- `automations/DAILY_SLACK_INSTRUCTIONS.md` (v1 — superseded)
- `sql/priceshocks_daily_digest.sql` (v1 — superseded for daily job)
- Any ride-level fare SQL in the automation
