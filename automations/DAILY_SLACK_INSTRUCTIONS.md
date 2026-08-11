# Pulsar daily fare-integrity report (Cloud Automation)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

## Goal
Daily **11:00 AM PKT**: Snowflake → **short Pulsar channel message** + **prepend** today’s section on Canvas `F0BN0E7RJ31` (keep older days).

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

- `pct_increase_pricing` (+ deltas) — **`increase_pricing` only**
- `surcharge_mismatch_rides` / `pct_surcharge_mismatch` (+ deltas, major_shift flag)
- `pickup_mismatch_rides` / `pct_pickup_mismatch` (+ deltas, major_shift flag)
- `surge_mismatch_rides` / `pct_surge_mismatch` (+ deltas, major_shift flag)
- `pd_mismatch_rides` / `pct_pd_mismatch` (+ deltas, major_shift flag)

Optional detail for majors: `sql/fare_integrity_slack_rollup.sql`

### 2) Update Canvas `F0BN0E7RJ31` (prepend — keep history)
Follow `automations/CANVAS_WATCH_TEMPLATE.md`.

1. Read existing canvas body.
2. Prepend **today’s dated section** at the top.
3. Leave all previous days’ sections intact below (scroll for history).
4. Do **not** replace the whole canvas with only today.

Include watches for: fare-increase %, surcharge, pickup, surge, PD mismatch.

### 3) Post short Slack message (Pulsar webhook)
Follow `automations/SLACK_MESSAGE_TEMPLATE.md`:

- SA / JO: fare-increase % + surcharge + pickup + surge + PD mismatch
- City-wise tables (majors + Others + **Total**) for each — **fixed-width monospace alignment**
- Footer: canvas link

### 4) Failures
Snowflake fail → one webhook line.  
Canvas fail → still post channel summary; note canvas error in one line (e.g. missing_scope).

## Definitions (do not invent)

**% rides with fare increase**  
Share of rides where `issue_type = increase_pricing`:  
`Fare_Diff > 0.01` **and** residual after waiting/cancel `> 0.01`.  
Does **not** include `increase_non_issue` (waiting / prior cancel fine).  
Does **not** equal “all cases charged > quote.”

**Surcharge mismatch**  
`lower(upfrontscenario)='withina'` AND dropoff at destination  
AND `ROUND(rd.SURCHARGE + rd.INTERCITYSURCHARGE, 2) != ROUND(pc.SURCHARGE, 2)`

**Pickup mismatch**  
PriceCheck pickup lat/long vs first `ride.eventhistory` `ride_offered` location  
`ST_DISTANCE(TO_GEOGRAPHY(...), TO_GEOGRAPHY(...)) > 100` (meters)

**Surge mismatch**  
Both multipliers non-null AND `ROUND(pc.SURGEMULTIPLIER, 4) <> ROUND(rd.SURGEMULTIPLIER, 4)`  
(Do not coalesce NULL → 0.)

**PD mismatch**  
Both multipliers non-null AND `ROUND(pc.DISCRIMINATIONMULTIPLIER, 4) <> ROUND(rd.DISCRIMINATIONMULTIPLIER, 4)`  
(Do not coalesce NULL → 0.)

## Hard constraints
- Existing automation only; schedule **11:00 AM PKT** (`0 6 * * *` UTC).
- Never log webhook URL / PAT / bot token.
- Channel stays short; detail on canvas; canvas retains multi-day history.
