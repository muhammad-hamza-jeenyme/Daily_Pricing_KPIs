# Agent guide — Daily Pricing KPIs

## Before any work

1. Read `memory/PROJECT_CONTEXT.md`
2. Read `docs/pricing-structure.md` and `docs/kpi-definitions.md`
3. Do not invent fare formulas; ask if unclear

## Mission

Jeeny fare-integrity tracker (v1): PriceCheck shown vs Receipts normalized; classify issue types; split by upfront scenario; digest for Slack DoD/WoW/MoM.

## Canonical SQL

- Daily aggregate: `sql/fare_integrity_daily_digest.sql`
- Slack rollup (alerts): `sql/fare_integrity_slack_rollup.sql`
- Ride-level debug: `tables schema/draft SQL.sql`
- Last MCP validation: `docs/validation-run-2026-08-04.md`

## Tools

- Snowflake MCP (`sql_exec_tool`) — **required** for daily digests (prefer rollup SQL)
- Slack post to `C0BMWLMR03T` only; detailed report in channel Canvas
- Watch rule: yesterday KPI > prior 14d average

## When user shares new facts

Update `docs/pricing-structure.md`, `docs/kpi-definitions.md`, `docs/data-sources.md`, and `memory/PROJECT_CONTEXT.md` in the same session.
