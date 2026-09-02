# Cloud Agent automations

## Why Cloud Agent

The digest must run **even when your laptop is off**. Use a **Cursor Cloud Automation** (scheduled Cloud Agent) with Snowflake + Slack.

## Schedule

| Item | Value |
|------|-------|
| Cadence | Daily |
| Time | **11:00 AM PKT** → cron `0 6 * * *` UTC |
| Job | Read `PRICESHOCKS` + discount companion → two Pulsar posts + canvas |

## Status

- [x] Channel `C0BMWLMR03T`
- [x] BI table `JEENY_PROD.RIDE.PRICESHOCKS` (refresh before 11:00 AM PKT)
- [x] Thin digest SQL: `sql/priceshocks_daily_digest.sql`
- [x] Discount BI handoff:
  `sql/bi_price_shock_discounts_daily.sql` +
  `docs/price-shock-discounts-bi-handoff.md`
- [x] v2 thin digest SQL: `sql/priceshocks_daily_digest_v2.sql`
- [x] v2 bot instructions: `automations/DAILY_SLACK_INSTRUCTIONS_V2.md`
- [ ] BI deploy `JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS` and pass all gates
- [ ] Re-paste v2 instructions into **Pricing KPI Alerts Slack** only after BI cutover

## Edit automation

**Do not create a new automation.** Edit **Pricing KPI Alerts Slack** only — see `automations/USE_EXISTING_AUTOMATION.md`.
