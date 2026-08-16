# Pulsar daily fare-integrity report (Cloud Automation)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

Paste this entire file into the automation **Instructions**. Repo source of truth: `muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Goal
Daily **11:00 AM PKT** (`0 6 * * *` UTC): run Snowflake → post **tables-only** Pulsar channel message → update Canvas `F0BN0E7RJ31` (3 runs max, exceptions-only).

## Tools / secrets
- Snowflake MCP
- `PULSAR_SLACK_WEBHOOK_URL` — channel post as Pulsar
- `PULSAR_SLACK_BOT_TOKEN` — canvas (`canvases:read` + `canvases:write`)
- Canvas ID `F0BN0E7RJ31` (https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31) — **not** a secret

## Step 1 — SQL
Run `sql/fare_integrity_channel_summary.sql` from repo `main`.

Use rows `grain=country` and `grain=city` for report date. Key fields:

| Field | Use |
|-------|-----|
| `pct_cumulative_shock` + DoD/WoW/MoM deltas | Cumulative PriceShocks % table |
| `pct_increase_pricing` + deltas | Residual fare increase % table |
| `pct_rounding` + deltas | Rounding error % table |
| `pct_*_mismatch` + deltas | Surcharge / Pickup / Surge / PD tables |
| `exception_28d_2sd_*` | Canvas exceptions (country + city) |
| `cum_trend_t1/t2`, `res_trend_t1/t2` | Country trend strip (with today’s pct as t0) |

## Step 2 — Channel message (Pulsar webhook)
Follow `automations/SLACK_MESSAGE_TEMPLATE.md` exactly.

**Must:**
- SA then JO
- Header only (`:flag-sa: *SA Fare Integrity (date | weekday)*`) then **tables** — **no** prose KPI blocks before tables
- Table order: Cumulative PriceShocks → Residual fare increase → Rounding → Surcharge → Pickup → Surge → PD
- Every table: rows `%inc` | `DoD` | `WoW` | `MoM`
- SA cols `RUH|JED|MAD|DMM|MEC|Others|Total`; JO cols **`AMM|IRB|ZRQ|Others|Total` only** (never reuse SA headers)
- Fixed-width monospace; each table in its own code fence; Total = country rate/delta
- **JO must match SA formatting quality** — see JO worked example in `automations/SLACK_MESSAGE_TEMPLATE.md`
- Footer: canvas link
- Optional `:warning:` on a **table title** only if that KPI’s country Total `%inc` > prior 7d avg (`major_shift_*` / `avg7_*`)

## Step 3 — Canvas `F0BN0E7RJ31`
Follow `automations/CANVAS_WATCH_TEMPLATE.md`.

**Must:**
1. Read existing canvas body
2. Prepend today’s compact section
3. Keep only **newest 3** dated sections; delete older
4. **Exceptions only** where `exception_28d_2sd_* = TRUE` (rate > 28d avg + 2× sample σ)
5. **Trend strip** — country Total Cumulative + Residual for last 3 runs (`t2 → t1 → **t0**`)
6. **Investigate today** — 1–2 concrete leads (city + KPI + why), or quiet-day line
7. **No** definitions, essays, or full matrices on canvas

## Step 4 — Failures
- Snowflake fail → one webhook error line
- Canvas fail → still post channel tables; one-line canvas error note

## Definitions (do not invent)

**Cumulative PriceShocks %** — `Fare_Diff > 0.01` (any reason: waiting, cancel fine, additional time, residual pricing, tech bugs). **Excludes** rounding.

**Residual fare increase %** — `increase_pricing`: `Fare_Diff > 0.01` AND residual after waiting/cancel `> 0.01`.

**Rounding error %** — `0 < |Fare_Diff| ≤ 0.01` (tech bug). Not in Cumulative.

**Surcharge mismatch** — withinA + dropoff at dest AND `ROUND(rd.SURCHARGE+rd.INTERCITYSURCHARGE,2) != ROUND(pc.SURCHARGE,2)`.

**Pickup mismatch** — PC pickup vs first `ride_offered` distance > 100m.

**Surge / PD mismatch** — both multipliers non-null AND rounded values differ (4 dp). Do not coalesce NULL→0.

**Canvas exception** — `yesterday > avg28 + 2*sd28` (28 days ending day before report date).

## Hard constraints
- Existing automation only; do not create a new automation
- Never log webhook URL / PAT / bot token
- Channel = tables; canvas = 3-run exception digest only
