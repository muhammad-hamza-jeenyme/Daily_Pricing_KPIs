# Pulsar daily fare-integrity + discount exposure (Cloud Automation v2)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

Paste this file into automation **Instructions only after BI cutover**. Repo:
`muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Cutover prerequisite

Do not activate v2 until BI has deployed
`JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS` from
`sql/bi_price_shock_discounts_daily.sql`, yesterday is present, and all
`ROW_TYPE='GATE'` rows pass. Until then, keep the active instructions from
`automations/DAILY_SLACK_INSTRUCTIONS.md` (v1).

## Goal

Daily **11:00 AM PKT** (`0 6 * * *` UTC):

1. Read `JEENY_PROD.RIDE.PRICESHOCKS` and
   `JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS`.
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

- `status`: freshness for both tables and regression-gate state
- `digest`: unchanged CHANNEL, SCENARIO, and CAUSE_MIX facts
- `discount`: post-discount segment/summary facts; absent when a gate fails
- `gate`: formula, identity, config, reconciliation, and segment checks

Read fields from `payload`, for example `payload:country`,
`payload:metric_name`, `payload:pct`, and `payload:net_shock_pct`.

Never run ride-level SQL in the automation.

### Freshness

If status `payload:is_ready = 0`, `PRICESHOCKS` is stale:

1. Post one PriceShocks ETL-lag webhook.
2. Skip all normal output and canvas.
3. Stop.

If `payload:max_discount_ride_date < payload:report_date`, preserve the seven
fare-integrity tables and non-discount canvas sections, post a
PriceShockDiscounts ETL-lag warning, and withhold discount output.

### Discount regression failure

If `payload:discount_is_ready = 0`:

1. Continue the seven unchanged fare-integrity tables for both markets.
2. If discount data is stale, post the ETL warning from the prior section;
   otherwise post
   `:rotating_light: Discount regression gate failed: {failed_gates}. Discount block withheld.`
3. Do not render any discount figures.
4. Update canvas with SCENARIO + CAUSE_MIX only; omit discount tables.

The SQL withholds `output_kind=discount` rows on a gate failure, so stale
discount figures cannot be formatted accidentally.

## Step 2 — two country channel posts

Follow `automations/SLACK_MESSAGE_TEMPLATE.md`.

From `output_kind=digest`, `metric_family=CHANNEL`, render these exact metrics:

1. `cumulative_price_shocks_net`
2. `residual_fare_increase_net`
3. `rounding_error`
4. `surcharge_mismatch`
5. `pickup_mismatch`
6. `surge_mismatch`
7. `pd_mismatch`

Ignore `spillover_recovery` in channel tables.

Post exactly two payloads:

1. SA: `RUH|JED|MAD|DMM|MEC|Others|Total`
2. JO: `AMM|IRB|ZRQ|Others|Total`, then canvas link

Each table has its own balanced code fence. Rows are `%inc`, `DoD`, `WoW`,
`MoM`. Never combine SA and JO in one payload.

If `discount_is_ready = 1`, append each market's post-discount block:

- `cap_bound_total`: no-buffer rides, post-discount shock rate/share, net excess
- `pct_bound_total`: post-discount shock rides, gross→net money, absorption
- `no_discount`: comparison post-discount shock rate
- worst voucher/promo segment by `net_shock_pct`
- `promised_not_applied`: discrepancy count

Do not put `net_fare_diff` in the headline Cumulative table. Existing headline
and bucket figures remain `fare_diff`-based for comparability.

Alert markers:

- `:warning:` when cap-bound ride share rises DoD
- `:warning:` when a capped segment's net shock rate rises faster than
  `no_discount`
- `:warning:` when percentage-bound average `d_discount` moves toward zero
- `:warning:` when SA+JO promised-not-applied exceeds 200 rides

## Step 3 — canvas

Follow `automations/CANVAS_WATCH_TEMPLATE.md`. From the same query:

- `SCENARIO`: NET contribution by scenario/dropoff with DoD/WoW/MoM
- `CAUSE_MIX`: last-day GROSS exclusive mix; verify approximately 100%
- `DISCOUNT`: segment ride share, gross vs net shock, `d_discount`, money, and
  absorption, only when `discount_is_ready = 1`

Prepend today's section and retain three dated sections. Do not add narrative,
investigation lists, definitions, or alerts to the canvas.

## Failures

- Snowflake failure: one webhook error line.
- PriceShocks freshness failure: ETL-lag webhook; skip all normal output.
- PriceShockDiscounts freshness/gate failure: keep unchanged fare tables and
  non-discount canvas; withhold discount output and post the relevant alert.
- Canvas failure: still post channel; add one-line canvas failure note.

## Locked definitions

- CHANNEL Cumulative/Residual: spillover-recovery excluded.
- SCENARIO: contribution to existing Cumulative.
- CAUSE_MIX: GROSS exclusive existing `fare_diff` causes.
- DISCOUNT gross: existing `fare_diff`, spillover-recovery excluded.
- DISCOUNT net: post-discount passenger `net_fare_diff`, spillover-recovery
  excluded.
- `d_discount = expected gross discount - actual gross discount`.

Specs:

- `docs/priceshocks-table.md`
- `docs/price-shock-discounts-bi-handoff.md`
- `docs/price-shock-discounts-implementation-spec.md`
- `docs/payment-spillover-price-shocks.md`
- `docs/pricing-structure.md`

## Hard constraints

- Existing automation only
- One Snowflake query: `sql/priceshocks_daily_digest_v2.sql`
- Never log secrets
- Never recompute ride-level fare logic in the agent
- Never sum SAR with JOD
- Never use `PROMOTIONENGINE.DISCOUNTAMOUNT` as expected quote discount
