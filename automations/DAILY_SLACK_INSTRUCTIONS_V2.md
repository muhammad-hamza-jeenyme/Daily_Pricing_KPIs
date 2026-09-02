# Pulsar daily fare-integrity + discount exposure (Cloud Automation v2)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

Paste this file into automation **Instructions only after BI cutover**. Repo:
`muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Cutover prerequisite

Do not activate v2 until BI has extended `JEENY_PROD.RIDE.PRICESHOCKS` with
`DISCOUNT` + `GATE` rows from `sql/bi_priceshocks_discount_extension.sql`,
yesterday’s DISCOUNT rows exist, and all GATE rows for yesterday have
`rides_flagged = 1` (PASS). Until then, keep
`automations/DAILY_SLACK_INSTRUCTIONS.md` (v1).

## Goal

Daily **11:00 AM PKT** (`0 6 * * *` UTC):

1. Read **only** `JEENY_PROD.RIDE.PRICESHOCKS` (CHANNEL + SCENARIO + CAUSE_MIX +
   DISCOUNT + GATE).
2. Post **two** Pulsar webhooks (SA, then JO).
3. Update Canvas `F0BN0E7RJ31` with scenario, cause mix, and discount exposure;
   keep the newest three runs.

## Tools / secrets

- Snowflake MCP
- `PULSAR_SLACK_WEBHOOK_URL`
- `PULSAR_SLACK_BOT_TOKEN` (`canvases:read` + `canvases:write`)
- Canvas `F0BN0E7RJ31` — not a secret

## Step 1 — one Snowflake query

Run `sql/priceshocks_daily_digest_v2.sql` once.

It returns `output_kind` and a `payload` OBJECT:

- `status`: freshness + discount readiness + failed gates
- `digest`: unchanged CHANNEL, SCENARIO, and CAUSE_MIX facts
- `discount`: DISCOUNT family facts; withheld when `discount_is_ready = 0`
- `gate`: GATE family checks (`gate_status` PASS/FAIL)

Read fields from `payload` (`payload:metric_name`, `payload:pct`,
`payload:amount_value`, `payload:avg_value`, …).

Never run ride-level SQL in the automation.

### Freshness

If status `payload:is_ready = 0`, PriceShocks CHANNEL data is stale:

1. Post one PriceShocks ETL-lag webhook.
2. Skip all normal output and canvas.
3. Stop.

If DISCOUNT rows for yesterday are missing, preserve the seven fare-integrity
tables and non-discount canvas sections, post a discount ETL-lag warning, and
withhold discount output.

### Discount regression failure

If `payload:discount_is_ready = 0`:

1. Continue the seven unchanged fare-integrity tables for both markets.
2. If discount data is stale, post the ETL warning; otherwise post
   `:rotating_light: Discount regression gate failed: {failed_gates}. Discount block withheld.`
3. Do not render any discount figures.
4. Update canvas with SCENARIO + CAUSE_MIX only; omit discount tables.

## Step 2 — two country channel posts

Follow `automations/SLACK_MESSAGE_TEMPLATE.md`.

From `output_kind=digest`, `metric_family=CHANNEL`, render the seven existing
fare tables unchanged. Append the discount block only when
`discount_is_ready = 1`, using the exact DISCOUNT `metric_name` map in the
Slack template (`cap_bound_total__net_shock`, etc.).

## Step 3 — canvas

Follow `automations/CANVAS_WATCH_TEMPLATE.md`.

From the same query: SCENARIO + CAUSE_MIX always; DISCOUNT segment tables only
when `discount_is_ready = 1`. Prepend today’s section; keep three runs.

For canvas segment rows, use:

- `{segment}__ride_share.pct`
- `{segment}__gross_shock.pct` / `.amount_value`
- `{segment}__net_shock.pct` / `.amount_value` / `.avg_value` (avg d_discount)
- `{segment}__absorption.pct`

## Failures

- Snowflake failure: one webhook error line.
- CHANNEL freshness failure: ETL-lag webhook; skip all normal output.
- DISCOUNT missing / GATE fail: keep fare tables + non-discount canvas; withhold
  discount output and alert.
- Canvas failure: still post channel; add one-line canvas note.

## Hard constraints

- Existing automation only
- One Snowflake query: `sql/priceshocks_daily_digest_v2.sql`
- Never log secrets
- Never recompute ride-level fare logic
- Never sum SAR with JOD
- Never use `PROMOTIONENGINE.DISCOUNTAMOUNT` as expected quote discount
