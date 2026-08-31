# Agent guide — Daily Pricing KPIs

## Before any work

1. Read `memory/PROJECT_CONTEXT.md`
2. Read `docs/pricing-structure.md`, `docs/kpi-definitions.md`, and `docs/payment-spillover-price-shocks.md`
3. Do not invent fare formulas; ask if unclear

## Mission

Jeeny fare-integrity tracker: PriceCheck shown vs Receipts normalized; **NET** price shocks (exclude digital-payment spillover recovery); Slack DoD/WoW/MoM + canvas scenario/cause-mix breakdown.

## Canonical data path (daily automation)

1. **BI table (source of truth for digests):** `JEENY_PROD.RIDE.PRICESHOCKS`  
   Docs: `docs/priceshocks-table.md`
2. **Thin consumer SQL (run this):** `sql/priceshocks_daily_digest.sql`  
   One query → CHANNEL + SCENARIO + CAUSE_MIX + DoD/WoW/MoM
3. **Agent instructions:** `automations/DAILY_SLACK_INSTRUCTIONS.md`

### Legacy / debug only (do not use in daily job)

- `sql/fare_integrity_channel_summary.sql`
- `sql/fare_integrity_canvas_breakdown.sql`
- `sql/bi_fare_integrity_daily_facts.sql` (original BI handoff)
- `sql/daily_price_shock_alert.sql`
- Ride-level debug: `tables schema/draft SQL.sql`

## Tools

- Snowflake MCP (`sql_exec_tool`) — prefer `PRICESHOCKS` digest (token-efficient)
- Slack MCP — Pulsar channel + canvas

## When user shares new facts

Update `docs/pricing-structure.md`, `docs/kpi-definitions.md`, `docs/data-sources.md`, `docs/payment-spillover-price-shocks.md` (if payment), `docs/priceshocks-table.md` (if BI table changes), and `memory/PROJECT_CONTEXT.md` in the same session.
