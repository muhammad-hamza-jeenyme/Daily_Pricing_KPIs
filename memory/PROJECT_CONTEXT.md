# Project memory — Daily Pricing KPIs

Last updated: 2026-08-06 (cron digest posted via Pulsar; report_date 2026-08-05)

## Mission

Fare-integrity tracker (v1). Cloud Agent **11:00 AM PKT**; SA+JO; digest **day × AREA_CODE × UPFRONTSCENARIO × issue_type**; **29** complete days; DoD/WoW/MoM (vs 28d prior); watch vs prior **14d** avg.

## Locked compare

- `PC_Surcharge_Gross = ROUND(SURCHARGE * IFF(SA, 1.15, 1.0), 2)`
- Shown = `VALUE + VAT(hailing) + PC_Surcharge_Gross`
- Norm receipt = `RR.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`
- issue_type: `matched` | `rounding` | `increase_non_issue` | `increase_pricing` | `decrease_pricing`
- Prod scenario casing: `withinA` | `withinB` | `beyondB`

## SQL

- Aggregate: `sql/fare_integrity_daily_digest.sql`
- Slack rollup: `sql/fare_integrity_slack_rollup.sql` ← **run this for daily alert**
- Ride-level: `tables schema/draft SQL.sql`
- Validation notes: `docs/validation-run-2026-08-04.md`

## Validation (2026-08-04)

- Query succeeded on Snowflake MCP
- Window: 2026-07-06 → 2026-08-03 (~5.18M rides)
- Yesterday top `increase_pricing` areas: AMM, JED, RUH, …

## Slack / automation (locked 2026-08-05)

- Channel: `#pricing-alerts` only (ID from `SLACK_CHANNEL_ID` secret)
- Cities: RUH, JED, MAD, DMM, MEC, AMM, IRB, ZRQ
- Watch: yesterday KPI > avg of prior **14** complete days; always name Area_Code
- Poster: **Pulsar** via `PULSAR_SLACK_WEBHOOK_URL` only (never Cursor Slack send)
- Detailed report: channel Canvas (fallback: second Pulsar message)
- Spec: `docs/alert-rules.md`, `automations/DAILY_SLACK_INSTRUCTIONS.md`

## Next

1. Enable Slack Canvas write for detailed report
2. Prefer Snowflake MCP; keep SQL API PAT fallback
3. Tune watch noise (buffer / volume floor) after a few Pulsar digests
