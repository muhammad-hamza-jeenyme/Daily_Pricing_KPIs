# Pulsar daily fare-integrity report (Cloud Automation)

## Goal
Every day at **11:00 AM PKT**, run Snowflake rollup for 8 major cities, summarize DoD/WoW/MoM + watch (vs 14d avg), and post **as Pulsar** via Incoming Webhook only.

## Repo
`muhammad-hamza-jeenyme/Daily_Pricing_KPIs` branch `main`.

## Tools
- **Snowflake MCP** — run SQL (`sql_exec_tool` or equivalent).
- **Do not** use Cursor’s built-in Slack “post to channel” action.
- **Do not** DM users or post to any channel except via the Pulsar webhook.

## Secrets (Cloud My Secrets)
- `PULSAR_SLACK_WEBHOOK_URL` — Pulsar Incoming Webhook (already bound to `C0BMWLMR03T`).
- Snowflake PAT / MCP auth as configured for Cloud Agents.

## Steps each run
1. Run `sql/fare_integrity_slack_rollup.sql` on Snowflake.
2. Build a **short** Slack message:
   - Header: `Pulsar · Pricing fare-integrity · {report_date}`
   - Snapshot: one bullet per city (RUH, JED, MAD, DMM, MEC, AMM, IRB, ZRQ) with rides, `%inc_pricing` + DoD/WoW/MoM, `%withinB`, key fields.
   - **Watch:** any KPI where yesterday > prior **14-day** average — list `Area_Code`, KPI, yesterday, 14d avg, deltas.
3. POST summary to Pulsar webhook:
   - URL = environment variable `PULSAR_SLACK_WEBHOOK_URL`
   - Body JSON: `{"text": "<full message markdown>"}`  
   - Use `curl` or equivalent HTTP POST from the Cloud Agent environment.
4. Publish **detailed report** to the channel Canvas when Canvas write is available. If Canvas API is unavailable, POST a second Pulsar message with the full city table (mark as Canvas pending fallback).
5. If Snowflake fails: POST one short failure line to the same webhook only. Do not invent KPI numbers.

## Hard constraints
- Post **only** via `PULSAR_SLACK_WEBHOOK_URL` (Pulsar bot). Never Cursor Slack send.
- Never print or log the webhook URL or PAT in the Slack message.
- Token-efficient: rollup SQL only, no ride-level dumps.
- Watch rule: yesterday > avg of prior 14 complete days.
- Spec: `docs/alert-rules.md`, `automations/DAILY_SLACK_INSTRUCTIONS.md`.
