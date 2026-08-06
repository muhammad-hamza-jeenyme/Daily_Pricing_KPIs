# Pulsar daily fare-integrity report (Cloud Automation)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

## Goal
Daily **11:00 AM PKT**: Snowflake → **short channel message** (fare-increase % only) as **Pulsar** + **update fixed Canvas** for detailed watches.

## Repo
`muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Tools
- **Snowflake MCP** — SQL.
- **Slack Canvas** — **update** existing canvas `F0BN0E7RJ31` (do not create a new canvas each day).
- **Do not** use Cursor Slack “post to channel” for the digest body.
- Post channel summary via **`PULSAR_SLACK_WEBHOOK_URL`** only.

## Secrets (sensitive only)
- `PULSAR_SLACK_WEBHOOK_URL` — channel summary (Pulsar)
- `PULSAR_SLACK_BOT_TOKEN` — Bot User OAuth Token `xoxb-…` with `canvases:read` + `canvases:write` (required to update canvas)
- Snowflake PAT / MCP for Cloud  

**Not a secret:** Canvas ID `F0BN0E7RJ31` / URL (keep in instructions).

### Why canvas failed before
Incoming Webhook can post the short channel message but **cannot** edit canvases. Without `PULSAR_SLACK_BOT_TOKEN`, you get: `Canvas update failed (bot token missing).`
## Fixed Canvas (Pricing Alerts channel)
- ID: `F0BN0E7RJ31`
- URL: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31
- Always put **report date at the top** of the canvas for easy reading.

## Steps each run

### 1) Channel summary SQL
Run `sql/fare_integrity_channel_summary.sql`  
→ country + city/Others `% rides with fare increase` with DoD/WoW/MoM and vs 7d avg.

### 2) Detailed watches SQL
Run `sql/fare_integrity_slack_rollup.sql` (8 major cities) for canvas watches / multi-KPI detail.

### 3) Update Canvas `F0BN0E7RJ31`
Follow `automations/CANVAS_WATCH_TEMPLATE.md` (DX style).

1. Use Bot Token from env `PULSAR_SLACK_BOT_TOKEN` (Authorization: `Bearer xoxb-…`).
2. Read canvas `F0BN0E7RJ31` (Slack canvases API / Slack MCP if available with that token).
3. Replace content with today’s watches/alerts.
4. Top must show date clearly, e.g. `# Pricing Fare Integrity Daily — YYYY-MM-DD` and `Report date: YYYY-MM-DD`.
5. Do **not** use the webhook for canvas edits.
### 4) Post short Slack message (Pulsar webhook)
Follow `automations/SLACK_MESSAGE_TEMPLATE.md` (bizfin-style):

- **SA** / **JO** country `% fare increase` + DoD/WoW/MoM + vs 7d avg
- City-wise tables (majors + Others)
- Footer link: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31

No long multi-KPI dumps in the channel.

### 5) Failures
If Snowflake fails: one short Pulsar webhook line. Do not invent numbers.  
If Canvas update fails: still post the short channel summary; note canvas update failed in one line.

## Hard constraints
- Existing automation only.
- Channel message = **% fare increase** country + cities/Others only.
- Watches detail = **Canvas `F0BN0E7RJ31`**, not channel noise.
- Major shift = yesterday > prior **7-day** average.
- Never log webhook URL / PAT.
- Never post outside Pulsar webhook / the pricing channel.
