# Project memory — Daily Pricing KPIs

Last updated: 2026-08-02

## What this project is

Jeeny (ride-hailing) is building a **daily Pricing KPI alert system**. A Cursor **Cloud Agent** will:

1. Run Snowflake queries daily at **11:30 AM PKT**
2. Analyse Pricing KPI movements: **DoD**, **WoW**, and **MoM**
3. Post to a **Slack** channel via bot when there is a **major shift**, **alert**, or **warning**

Primary near-term goal: **understand how pricing works** before locking queries and thresholds.

## Stakeholders / owner context

- Repo owner / product contact: Muhammad Hamza
- GitHub: https://github.com/muhammad-hamza-jeenyme/Daily_Pricing_KPIs
- Local workspace: `Daily Digest Pricing`

## Integrations already available

- **Snowflake MCP** — run analytics queries (`sql_exec_tool`)
- **Slack MCP** — send alerts / digests to the target channel

## Comparison definitions (confirmed)

| Window | Definition for this project |
|--------|-----------------------------|
| DoD | Yesterday’s performance vs prior day (exact prior-day rule TBD with pricing) |
| WoW | Yesterday vs same point ~7 days earlier (exact weekday alignment TBD) |
| MoM | Yesterday’s performance compared to **28 days before it** |

## Delivery principles

- Prefer **signal over noise**: only escalate major shift / alert / warning (thresholds TBD).
- Ground every KPI in documented pricing mechanics (see `docs/pricing-structure.md`).
- Keep SQL, thresholds, and Slack copy versioned in this repo.
- Do not invent table names, KPI formulas, or alert thresholds — wait for pricing structure and SME detail.

## Open items (fill as details arrive)

- [ ] Pricing structure (fares, surge, commissions, incentives, geo/service types, etc.)
- [ ] Canonical KPI list + formulas
- [ ] Snowflake schemas / tables / grains / timezone
- [ ] Alert severity thresholds and ownership
- [ ] Slack workspace, channel, bot identity, message template
- [ ] Cloud Agent automation config (schedule 11:30 AM PKT)

## Working agreement with agents

1. Read this file + `docs/` before proposing queries or alerts.
2. When new pricing facts are shared in chat, update `docs/pricing-structure.md`, `docs/kpi-definitions.md`, and this memory.
3. Prefer documenting unknowns as explicit TBD rather than guessing.
4. Use Snowflake MCP only for exploration once table guidance is provided; never invent schemas.
5. Use Slack MCP for delivery only after channel + format are agreed.
