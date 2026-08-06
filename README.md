# Daily Pricing KPIs — Jeeny Fare Integrity Tracker

Slack-oriented daily digest for Jeeny **Pricing fare integrity** (PriceCheck shown vs final charged fare under upfront pricing).

A Cursor Cloud Agent will run Snowflake at **11:00 AM PKT**, analyse **DoD / WoW / MoM** (MoM = yesterday vs 28 days prior), and alert on major shifts.

## v1 scope

- Universe: boarded rides, destination known (`ORIGINALESTIMATEFARE IS NOT NULL`), countries **SA + JO**
- Compare: PriceCheck shown vs Receipts normalized (discount add-back)
- Classify: `matched` | `rounding` | `increase_non_issue` | `increase_pricing` | `decrease_pricing`
- Split by upfront scenario: `withinA` | `withinB` | `beyondB` (Snowflake casing)
- Digest grain: **day × area_code × upfrontscenario × issue_type**, last **29** complete days

## Run this query

Primary (daily / MCP): [`sql/fare_integrity_daily_digest.sql`](sql/fare_integrity_daily_digest.sql)

Ride-level debug: [`tables schema/draft SQL.sql`](tables%20schema/draft%20SQL.sql)

## Docs

| Doc | Purpose |
|-----|---------|
| [`docs/pricing-structure.md`](docs/pricing-structure.md) | How upfront / PriceCheck / Receipts fare works |
| [`docs/kpi-definitions.md`](docs/kpi-definitions.md) | KPI catalogue & issue taxonomy |
| [`docs/data-sources.md`](docs/data-sources.md) | Snowflake objects |
| [`docs/alert-rules.md`](docs/alert-rules.md) | Slack severity (thresholds TBD) |
| [`docs/validation-run-2026-08-04.md`](docs/validation-run-2026-08-04.md) | First Snowflake MCP validation snapshot |
| [`memory/PROJECT_CONTEXT.md`](memory/PROJECT_CONTEXT.md) | Agent memory |
| [`AGENTS.md`](AGENTS.md) | Working agreements |

## Stack

| Component | Role |
|-----------|------|
| Snowflake MCP | `sql_exec_tool` |
| Slack MCP | Channel alerts (next) |
| Cloud Agent | **11:00 AM PKT** daily (`0 6 * * *` UTC) |

## Status

- [x] Pricing structure documented
- [x] Fare-integrity SQL (aggregate + ride-level)
- [x] Snowflake MCP validation (2026-08-04)
- [ ] DoD/WoW/MoM rollup query + Slack alert thresholds
- [ ] Cloud Agent automation live

## Repo

https://github.com/muhammad-hamza-jeenyme/Daily_Pricing_KPIs
