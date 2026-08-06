# Pulsar daily fare-integrity report (Cloud Automation)

## Goal
Every day at **11:00 AM PKT**: Snowflake → short Pulsar channel message (**% fare increase only**) + Slack Canvas for detailed watches.

## Repo
`muhammad-hamza-jeenyme/Daily_Pricing_KPIs` branch `main`.

## Tools
- **Snowflake MCP** — run SQL (`sql_exec_tool` or equivalent). Fallback: Snowflake SQL API + PAT.
- **Slack Canvas create** — detailed watches; share link in channel footer.
- **Do not** use Cursor’s built-in Slack “post to channel” for the digest body.
- Post channel summary via **`PULSAR_SLACK_WEBHOOK_URL` only**.

## Secrets
- `PULSAR_SLACK_WEBHOOK_URL` — Pulsar Incoming Webhook (bound to `#pricing-alerts`).
- `PULSAR_SLACK_BOT_TOKEN` — Canvas create/update (required for watches Canvas).
- Snowflake PAT / MCP auth as configured for Cloud Agents.

## Steps each run
1. Run `sql/fare_integrity_channel_summary.sql` → country + city/Others % fare increase with DoD/WoW/MoM and vs 7d avg.
2. Run `sql/fare_integrity_slack_rollup.sql` → 8 major cities multi-KPI detail for Canvas watches.
3. Create Canvas per `automations/CANVAS_WATCH_TEMPLATE.md` (title `Pricing Fare Integrity Daily — {report_date}`).
4. POST short channel message via Pulsar webhook per `automations/SLACK_MESSAGE_TEMPLATE.md` (include Canvas link or unavailable note).
5. If Snowflake fails: one short Pulsar failure line. Do not invent numbers.
6. If Canvas fails: still post the short channel summary; note canvas unavailable in one line. Do **not** dump multi-KPI watches into the channel.

## Hard constraints
- Channel message = % fare increase country + cities/Others only.
- Watches detail = Canvas, not channel noise.
- Major shift = yesterday > prior 7-day average.
- Never log webhook URL / PAT.
- Never post outside Pulsar webhook / the pricing channel.
- Spec: `docs/alert-rules.md`, templates under `automations/`.
