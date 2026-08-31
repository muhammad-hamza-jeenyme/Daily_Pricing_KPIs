# Agent guide — Daily Pricing KPIs

## Before any work

1. Read `memory/PROJECT_CONTEXT.md`
2. Read `docs/priceshocks-table.md`, `docs/pricing-structure.md`, `docs/kpi-definitions.md`, and `docs/payment-spillover-price-shocks.md`
3. Do not invent fare formulas; ask if unclear

## Mission

Jeeny fare-integrity tracker: PriceCheck shown vs Receipts normalized; **NET** price shocks (exclude digital-payment spillover recovery); Slack DoD/WoW/MoM + canvas scenario/cause-mix.

## Canonical SQL

- **Daily job (only):** `sql/priceshocks_daily_digest.sql` ← reads `RIDE.PRICESHOCKS`
- Spec: `docs/priceshocks-table.md`
- Legacy ride-level debug: `sql/fare_integrity_channel_summary.sql`, `sql/fare_integrity_canvas_breakdown.sql`, `sql/daily_price_shock_alert.sql`
- Spillover: `docs/payment-spillover-price-shocks.md`

## Tools

- Snowflake MCP (`sql_exec_tool`) — prefer PriceShocks digest (token-efficient); SQL API + PAT fallback OK
- Slack — Pulsar webhook for channel; bot token for canvas `F0BN0E7RJ31`

## When user shares new facts

Update `docs/pricing-structure.md`, `docs/kpi-definitions.md`, `docs/data-sources.md`, `docs/payment-spillover-price-shocks.md` / `docs/priceshocks-table.md` (if relevant), and `memory/PROJECT_CONTEXT.md` in the same session.
