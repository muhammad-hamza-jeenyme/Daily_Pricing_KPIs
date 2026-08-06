# Pulsar daily fare-integrity report (Cloud Automation)

## Goal
Every day at **11:00 AM PKT** (`0 6 * * *` UTC): Snowflake → short Pulsar channel message (**% fare increase only**) + update fixed Canvas for detailed watches.

## Repo
`muhammad-hamza-jeenyme/Daily_Pricing_KPIs` branch `main`.

## Tools
- **Snowflake MCP** — run SQL (`sql_exec_tool` or equivalent). Fallback: Snowflake SQL API + PAT.
- **Slack Canvas** — update existing canvas `F0BN0E7RJ31` only (never create a new canvas each day).
- **Do not** use Cursor’s built-in Slack “post to channel” for the digest body.
- Post channel summary via **`PULSAR_SLACK_WEBHOOK_URL` only**.

## Fixed Canvas (Pricing Alerts channel)
- ID: `F0BN0E7RJ31` (not a secret — keep in instructions)
- URL: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31

## Secrets
- `PULSAR_SLACK_WEBHOOK_URL` — Pulsar Incoming Webhook (channel summary only).
- `PULSAR_SLACK_BOT_TOKEN` — required to edit Canvas `F0BN0E7RJ31` (`canvases:write`).
- Snowflake PAT / MCP auth as configured for Cloud Agents.

## Steps each run
1. Run `sql/fare_integrity_channel_summary.sql` → country + city/Others % fare increase with DoD/WoW/MoM and vs 7d avg.
2. Run `sql/fare_integrity_slack_rollup.sql` → 8 major cities multi-KPI detail for Canvas watches.
3. Update Canvas `F0BN0E7RJ31` per `automations/CANVAS_WATCH_TEMPLATE.md` (read section IDs; put report date at top).
4. POST short channel message via Pulsar webhook per `automations/SLACK_MESSAGE_TEMPLATE.md`.
5. If Snowflake fails: one short Pulsar failure line. Do not invent numbers.
6. If Canvas update fails: still post the short channel summary; note canvas update failed in one line. Do **not** dump multi-KPI watches into the channel.

## Hard constraints
- Existing automation only (Pricing KPI Alerts Slack).
- Channel message = % fare increase country + cities/Others only.
- Watches detail = Canvas `F0BN0E7RJ31`, not channel noise.
- Major shift = yesterday > prior 7-day average.
- Never log webhook URL / PAT.
- Never post outside Pulsar webhook / the pricing channel.
- Spec: `docs/alert-rules.md`, templates under `automations/`.
