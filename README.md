# Daily Pricing KPIs — Jeeny Alert System

Slack-based daily digest and alert bot for Jeeny Pricing KPIs.

A Cursor Cloud Agent runs Snowflake queries every day at **11:30 AM PKT**, analyses Day-over-Day (DoD), Week-over-Week (WoW), and Month-over-Month (MoM) movements, and posts a report to Slack when there is a major shift, alert, or warning.

## Goals

1. **Understand pricing** — document how Jeeny pricing works (structure, levers, KPIs).
2. **Automate monitoring** — daily Snowflake → analysis → Slack alerts.
3. **Surface risk early** — flag material DoD / WoW / MoM changes vs baselines.

## Comparison windows

| Label | Meaning |
|-------|---------|
| **DoD** | Yesterday vs the day before (or agreed prior day baseline) |
| **WoW** | Yesterday vs the same weekday 7 days earlier |
| **MoM** | Yesterday vs **28 days before** (4-week lookback, as defined for this project) |

> MoM here is explicitly **yesterday vs 28 days prior**, not calendar-month averages, unless pricing docs say otherwise later.

## Stack

| Component | Role |
|-----------|------|
| **Snowflake** (MCP) | Source of truth for Pricing KPI queries |
| **Slack** (MCP) | Channel delivery via bot |
| **Cursor Cloud Agent** | Scheduled run at 11:30 AM PKT; query, analyse, alert |
| **This repo** | Specs, memory, query notes, alert rules, runbooks |

## Repo layout

```
docs/
  pricing-structure.md    # How pricing works (to be filled)
  kpi-definitions.md      # KPI defs, formulas, owners
  alert-rules.md          # Thresholds: major shift / alert / warning
  data-sources.md         # Snowflake tables, grains, freshness
memory/
  PROJECT_CONTEXT.md      # Durable project memory for agents
.cursor/rules/            # Always-on Cursor rules for this repo
automations/              # Cloud agent / schedule notes (later)
sql/                      # Snowflake query drafts (later)
```

## Current status

- [x] Project scaffold and memory
- [ ] Pricing structure documented (awaiting SME input)
- [ ] KPI catalogue and thresholds agreed
- [ ] Snowflake queries validated
- [ ] Slack channel + bot message format
- [ ] Cloud Agent schedule (11:30 AM PKT) live

## Next input needed

Pricing structure details from the team (how pricing works, levers, KPI definitions, and which tables/metrics matter).

## Related

- GitHub: https://github.com/muhammad-hamza-jeenyme/Daily_Pricing_KPIs
