# Pulsar daily fare-integrity report (Cloud Automation v1 — active until BI cutover)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

This is the current paste-ready v1 instruction file. Keep it active until BI
deploys `JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS`. For the post-deployment cutover,
use `automations/DAILY_SLACK_INSTRUCTIONS_V2.md`.

Repo: `muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Goal

Daily **11:00 AM PKT** (`0 6 * * *` UTC):

1. Read pre-aggregated `JEENY_PROD.RIDE.PRICESHOCKS`.
2. Post **two** Pulsar webhooks (SA, then JO).
3. Update Canvas `F0BN0E7RJ31` with scenario + cause mix; keep three runs.

## Tools / secrets

- Snowflake MCP
- `PULSAR_SLACK_WEBHOOK_URL`
- `PULSAR_SLACK_BOT_TOKEN` (`canvases:read` + `canvases:write`)
- Canvas `F0BN0E7RJ31` — not a secret

## Step 1 — one thin Snowflake query

Run `sql/priceshocks_daily_digest.sql` once.

It returns:

- `output_kind=status`: `is_ready`, `max_ride_date`, `max_computed_at`
- `metric_family=CHANNEL`: seven Slack KPIs + spillover monitor
- `metric_family=SCENARIO`: canvas NET contribution
- `metric_family=CAUSE_MIX`: canvas exclusive GROSS mix

Do not run `fare_integrity_channel_summary.sql` or
`fare_integrity_canvas_breakdown.sql`.

If `is_ready=0` or `max_ride_date < CURRENT_DATE()-1`, post one ETL-lag
webhook, skip canvas, and stop.

## Step 2 — channel

Follow `automations/SLACK_MESSAGE_TEMPLATE.md`, but while v1 is active ignore
its discount section because `output_kind=discount` does not yet exist.

Use `metric_family=CHANNEL` and these exact metrics:

1. `cumulative_price_shocks_net`
2. `residual_fare_increase_net`
3. `rounding_error`
4. `surcharge_mismatch`
5. `pickup_mismatch`
6. `surge_mismatch`
7. `pd_mismatch`

Ignore `spillover_recovery` in Slack tables.

Post exactly two webhook messages:

1. SA only: header + seven tables; `RUH|JED|MAD|DMM|MEC|Others|Total`
2. JO only: header + seven tables; `AMM|IRB|ZRQ|Others|Total` + canvas link

Never combine markets. Each table has its own balanced code fence. Rows:
`%inc`, `DoD`, `WoW`, `MoM`.

## Step 3 — canvas

Use `SCENARIO` + `CAUSE_MIX` from the same digest. While v1 is active, ignore
the discount section in `automations/CANVAS_WATCH_TEMPLATE.md`.

Prepend today's section, retain three runs, and include only:

- SA/JO scenario tables
- SA/JO cause-mix tables

## Failures

- Snowflake fail: one webhook error line.
- Canvas fail: still post channel; add one-line canvas note.
- PriceShocks stale: ETL-lag webhook; skip canvas.

## Hard constraints

- Existing automation only
- One Snowflake query: `sql/priceshocks_daily_digest.sql`
- Two channel webhooks
- Never log secrets
- Format aggregates only
- Do not recompute ride-level fare logic in the agent
