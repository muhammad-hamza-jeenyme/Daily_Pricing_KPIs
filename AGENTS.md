# Agent guide — Daily Pricing KPIs

## Before any work

1. Read `memory/PROJECT_CONTEXT.md`
2. Read `docs/pricing-structure.md`, `docs/kpi-definitions.md`, and `docs/payment-spillover-price-shocks.md`
3. Do not invent fare formulas; ask if unclear

## Mission

Jeeny fare-integrity tracker: PriceCheck shown vs Receipts normalized; **NET** price shocks (exclude digital-payment spillover recovery); Slack DoD/WoW/MoM + canvas exceptions.

## Canonical SQL

- Daily channel + canvas: `sql/fare_integrity_channel_summary.sql` ← **run this**
- Headline net shocks: `sql/daily_price_shock_alert.sql`
- Ride-level debug: `tables schema/draft SQL.sql`
- Spillover: `docs/payment-spillover-price-shocks.md`

## Tools

- Snowflake MCP (`sql_exec_tool`) — prefer aggregate digests (token-efficient)
- Slack MCP — Pulsar channel + canvas

## When user shares new facts

Update `docs/pricing-structure.md`, `docs/kpi-definitions.md`, `docs/data-sources.md`, `docs/payment-spillover-price-shocks.md` (if payment), and `memory/PROJECT_CONTEXT.md` in the same session.
