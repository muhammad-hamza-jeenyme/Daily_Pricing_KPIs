# Agent guide — Daily Pricing KPIs

## Before any work

1. Read `memory/PROJECT_CONTEXT.md`
2. Read `docs/pricing-structure.md`, `docs/kpi-definitions.md`,
   `docs/payment-spillover-price-shocks.md`, and
   `docs/price-shock-discounts-implementation-spec.md`
3. Do not invent fare formulas; ask if unclear

## Mission

Jeeny fare-integrity tracker: preserve the normalized-receipt `fare_diff`
headline, exclude digital-payment spillover recovery, and add post-discount
passenger exposure (`net_fare_diff`, `d_discount`, cap segments) to Slack and
canvas.

## Canonical data path (daily automation)

1. **BI tables:** `JEENY_PROD.RIDE.PRICESHOCKS` plus, after BI cutover,
   `JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS`
   Docs: `docs/priceshocks-table.md` and
   `docs/price-shock-discounts-bi-handoff.md`
2. **Thin consumer SQL:** current v1
   `sql/priceshocks_daily_digest.sql`; v2 after companion deployment
   `sql/priceshocks_daily_digest_v2.sql`
   v2 returns CHANNEL + SCENARIO + CAUSE_MIX + DISCOUNT + regression gates
3. **Agent instructions:** v1
   `automations/DAILY_SLACK_INSTRUCTIONS.md`; v2 after BI cutover
   `automations/DAILY_SLACK_INSTRUCTIONS_V2.md`

### Legacy / debug only (do not use in daily job)

- `sql/fare_integrity_channel_summary.sql`
- `sql/fare_integrity_canvas_breakdown.sql`
- `sql/bi_fare_integrity_daily_facts.sql` (original BI handoff)
- `sql/bi_price_shock_discounts_daily.sql` (BI build/backfill only; never daily agent)
- `sql/daily_price_shock_alert.sql`
- Ride-level debug: `tables schema/draft SQL.sql`

## Tools

- Snowflake MCP (`sql_exec_tool`) — prefer `PRICESHOCKS` digest (token-efficient)
- Slack MCP — Pulsar channel + canvas

## When user shares new facts

Update `docs/pricing-structure.md`, `docs/kpi-definitions.md`, `docs/data-sources.md`, `docs/payment-spillover-price-shocks.md` (if payment), `docs/priceshocks-table.md` (if BI table changes), and `memory/PROJECT_CONTEXT.md` in the same session.
