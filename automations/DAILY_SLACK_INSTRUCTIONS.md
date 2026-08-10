# Pulsar daily fare-integrity report (Cloud Automation)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

## Goal
Daily **11:00 AM PKT**: Snowflake → **short Pulsar channel message** + **update Canvas `F0BN0E7RJ31`**.

## Repo
`muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Tools / secrets
- Snowflake MCP
- `PULSAR_SLACK_WEBHOOK_URL` — channel post
- `PULSAR_SLACK_BOT_TOKEN` — canvas update (`canvases:read` + `canvases:write`; reinstall app after adding scopes)
- Fixed canvas: `F0BN0E7RJ31` — https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31  
  (**not** a secret)

## Steps each run

### 1) Main SQL (channel + canvas metrics)
Run `sql/fare_integrity_channel_summary.sql`  
Returns country + city/Others for yesterday with DoD/WoW/MoM / vs7d:

- `pct_increase_pricing` (+ deltas)
- `surcharge_mismatch_rides` / `pct_surcharge_mismatch` (+ deltas, major_shift flag)
- `pickup_mismatch_rides` / `pct_pickup_mismatch` (+ deltas, major_shift flag)

Optional detail for majors: `sql/fare_integrity_slack_rollup.sql`

### 2) Update Canvas `F0BN0E7RJ31`
Follow `automations/CANVAS_WATCH_TEMPLATE.md`.  
Date at top. Include watches for fare-increase %, surcharge mismatch, pickup mismatch (>100m).

### 3) Post short Slack message (Pulsar webhook)
Follow `automations/SLACK_MESSAGE_TEMPLATE.md`:

- SA / JO: fare-increase % + surcharge mismatch counts + pickup mismatch counts
- City-wise tables (majors + Others) for each
- Footer: canvas link

### 4) Failures
Snowflake fail → one webhook line.  
Canvas fail → still post channel summary; note canvas error in one line (e.g. missing_scope).

## Definitions (do not invent)

**Surcharge mismatch**  
`lower(upfrontscenario)='withina'` AND dropoff at destination  
AND `ROUND(rd.SURCHARGE + rd.INTERCITYSURCHARGE, 2) != ROUND(pc.SURCHARGE, 2)`

**Pickup mismatch**  
PriceCheck pickup lat/long vs first `ride.eventhistory` `ride_offered` location  
`ST_DISTANCE(TO_GEOGRAPHY(...), TO_GEOGRAPHY(...)) > 100` (meters)

## Hard constraints
- Existing automation only; schedule **11:00 AM PKT** (`0 6 * * *` UTC).
- Never log webhook URL / PAT / bot token.
- Channel stays short; detail on canvas.
