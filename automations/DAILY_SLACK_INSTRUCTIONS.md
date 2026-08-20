# Pulsar daily fare-integrity report (Cloud Automation)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

Paste this entire file into the automation **Instructions**. Repo source of truth: `muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Goal
Daily **11:00 AM PKT** (`0 6 * * *` UTC): run Snowflake → post **tables-only** Pulsar channel message → update Canvas `F0BN0E7RJ31` (3 runs max, exceptions-only).

**Shock KPIs are NET of digital-payment spillover recovery** (see Definitions). Do not report gross shocks as the headline.

## Tools / secrets
- Snowflake MCP
- `PULSAR_SLACK_WEBHOOK_URL` — channel post as Pulsar
- `PULSAR_SLACK_BOT_TOKEN` — canvas (`canvases:read` + `canvases:write`)
- Canvas ID `F0BN0E7RJ31` (https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31) — **not** a secret

## Step 1 — SQL
Run `sql/fare_integrity_channel_summary.sql` from repo `main`.

Optional sanity headline: `sql/daily_price_shock_alert.sql` (country `shocks_gross` / `spillover_excluded` / `shocks_net`).

Use rows `grain=country` and `grain=city` for report date. Key fields:

| Field | Use |
|-------|-----|
| `pct_cumulative_shock` + DoD/WoW/MoM | Cumulative PriceShocks % (**NET**) |
| `pct_increase_pricing` + deltas | Residual fare increase % (**NET**) |
| `pct_spillover_recovery` | Canvas / sanity only — recovery legs excluded from shocks |
| `pct_rounding` + deltas | Rounding error % |
| `pct_*_mismatch` + deltas | Surcharge / Pickup / Surge / PD tables |
| `exception_28d_2sd_*` | Canvas exceptions (country + city) |
| `cum_trend_t1/t2`, `res_trend_t1/t2` | Country trend strip (with today’s pct as t0) |

**Do not shrink** the SQL spillover lookback (30 days before digest window).

## Step 2 — Channel message (Pulsar webhook)
Follow `automations/SLACK_MESSAGE_TEMPLATE.md` exactly.

**Must:**
- SA then JO
- Header only then **tables** — **no** prose KPI blocks before tables
- Table order: Cumulative PriceShocks → Residual fare increase → Rounding → Surcharge → Pickup → Surge → PD
- Every table: rows `%inc` | `DoD` | `WoW` | `MoM`
- SA cols `RUH|JED|MAD|DMM|MEC|Others|Total`; JO cols **`AMM|IRB|ZRQ|Others|Total` only**
- Fixed-width monospace; each table in its own code fence; Total = country rate/delta
- **JO must match SA formatting quality**
- Footer: canvas link
- Optional `:warning:` on a **table title** only if that KPI’s country Total `%inc` > prior 7d avg

## Step 3 — Canvas `F0BN0E7RJ31`
Follow `automations/CANVAS_WATCH_TEMPLATE.md`.

**Must:**
1. Read existing canvas body
2. Prepend today’s compact section
3. Keep only **newest 3** dated sections; delete older
4. **Exceptions only** where `exception_28d_2sd_* = TRUE` (rate > 28d avg + 2× sample σ)
5. **Trend strip** — country Total Cumulative + Residual (**net**) for last 3 runs
6. **Investigate today** — 1–2 concrete leads, or quiet-day line
7. If `pct_spillover_recovery` spikes vs 7d, one line under monitor (not a shock)
8. **No** definitions, essays, or full matrices on canvas

## Step 4 — Failures
- Snowflake fail → one webhook error line
- Canvas fail → still post channel tables; one-line canvas error note

## Definitions (do not invent)

**Cumulative PriceShocks % (NET)** — `Fare_Diff > 0.01` for any reason (waiting, cancel fine on originating ride, additional time, residual pricing, tech bugs), **excluding** rounding and **excluding spillover recovery** rides.

**Residual fare increase % (NET)** — `increase_pricing` (`Fare_Diff > 0.01` AND residual after waiting/cancel `> 0.01`) **and not** spillover recovery.

**Spillover recovery** — digital underpay parked as `OUTSTANDINGBALANCE` (~1 SAR SA / ~0.1 JOD JO threshold), recovered next ride as `CANCELLATIONFINE` matching prior outs (±0.02, ex-VAT). Cash exempt. Spec: `docs/payment-spillover-price-shocks.md`.

**Rounding error %** — `0 < |Fare_Diff| ≤ 0.01`. Not in Cumulative.

**Surcharge / Pickup / Surge / PD mismatch** — unchanged; see template.

**Canvas exception** — `yesterday > avg28 + 2*sd28`.

## Hard constraints
- Existing automation only; do not create a new automation
- Never log webhook URL / PAT / bot token
- Channel = tables; canvas = 3-run exception digest only
- Always use **NET** Cumulative / Residual (post spillover fix)
