# Agent guide — Daily Pricing KPIs

## Before any work

1. Read `memory/PROJECT_CONTEXT.md`.
2. Read relevant files under `docs/` (especially `pricing-structure.md` and `kpi-definitions.md`).
3. Do not invent pricing mechanics, Snowflake objects, or alert thresholds.

## Mission

Help Jeeny Pricing monitor daily KPIs via Snowflake analysis and Slack alerts (DoD, WoW, MoM = vs 28 days prior), after first documenting how pricing works.

## Tools

- **Snowflake MCP**: explore and validate queries once table guidance exists.
- **Slack MCP**: send digests/alerts only when channel + format are agreed.
- **Cloud Agent**: scheduled daily at 11:30 AM PKT (config TBD in `automations/`).

## When the user shares new pricing context

Update in the same session:

1. `docs/pricing-structure.md` — mechanics
2. `docs/kpi-definitions.md` — metrics
3. `docs/data-sources.md` — tables/queries if mentioned
4. `docs/alert-rules.md` — thresholds if mentioned
5. `memory/PROJECT_CONTEXT.md` — confirmed facts + open items

## Output preferences

- Prefer concise, actionable digests for Slack.
- Flag TBDs explicitly.
- Keep GitHub repo and local docs in sync when asked to commit/push.
