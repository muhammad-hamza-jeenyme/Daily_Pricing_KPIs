# Pulsar daily fare-integrity report (Cloud Automation)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

Paste this entire file into the automation **Instructions**. Repo: `muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Goal
Daily **11:00 AM PKT** (`0 6 * * *` UTC):
1. Read pre-aggregated `RIDE.PRICESHOCKS` (BI refreshes before 11:00 AM PKT)
2. Post **two** Pulsar webhooks (SA, then JO)
3. Update Canvas `F0BN0E7RJ31` (scenario + cause-mix only; keep last 3 runs)

## Tools / secrets
- Snowflake MCP
- `PULSAR_SLACK_WEBHOOK_URL`
- `PULSAR_SLACK_BOT_TOKEN` (`canvases:read` + `canvases:write`)
- Canvas `F0BN0E7RJ31` — https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31 (**not** a secret)

## Step 1 — One thin Snowflake query (only this)
Run **`sql/priceshocks_daily_digest.sql`** once.
It reads `RIDE.PRICESHOCKS` and returns:
- `output_kind = status` → `is_ready`, `max_ride_date`, `max_computed_at`
- `output_kind = digest` + `metric_family = CHANNEL` → 7 Slack KPIs (+ optional spillover monitor)
- `output_kind = digest` + `metric_family = SCENARIO` → canvas NET contribution
- `output_kind = digest` + `metric_family = CAUSE_MIX` → canvas exclusive GROSS mix

**Do not** run `fare_integrity_channel_summary.sql` or `fare_integrity_canvas_breakdown.sql` in the daily job.

### Freshness gate
If `is_ready = 0` or `max_ride_date < CURRENT_DATE - 1`:
- Post one webhook line: ETL lag / PriceShocks not ready for yesterday
- Skip canvas
- Stop

## Step 2 — Channel posts (fix JO break)
Follow `automations/SLACK_MESSAGE_TEMPLATE.md`.

Filter `metric_family = CHANNEL`, report metrics only (ignore `spillover_recovery` for Slack tables):

| metric_name (exact) | Table title |
|---------------------|-------------|
| `cumulative_price_shocks_net` | Cumulative PriceShocks % |
| `residual_fare_increase_net` | Residual fare increase % |
| `rounding_error` | Rounding error % |
| `surcharge_mismatch` | Surcharge mismatch % |
| `pickup_mismatch` | Pickup mismatch % |
| `surge_mismatch` | Surge mismatch % |
| `pd_mismatch` | PD mismatch % |

**Must post TWO webhook messages:**
1. **SA only** — header + 7 tables (cols `RUH|JED|MAD|DMM|MEC|Others|Total`)
2. **JO only** — header + 7 tables (cols `AMM|IRB|ZRQ|Others|Total`) + canvas link footer

Never combine SA+JO in one payload.
Each table = own code fence; even number of ``` per message.
Rows: `%inc` (= `pct`) | `DoD` | `WoW` | `MoM` (pp deltas).

## Step 3 — Canvas update
Follow `automations/CANVAS_WATCH_TEMPLATE.md`.
From the **same** digest result (no second SQL):

| metric_family | Use |
|---------------|-----|
| `SCENARIO` | NET shock contribution by withinA/B×dropoff + beyondB; city + Total; DoD/WoW/MoM |
| `CAUSE_MIX` | Last-day GROSS exclusive % by country (`city_bucket=Total`); must sum ≈100% |

**Must:**
1. Prepend today’s dated section; keep newest **3** runs only
2. Content **only**: SA/JO scenario tables + SA/JO cause-mix tables
3. **No** exceptions, investigate list, trends, definitions, or alerts

## Step 4 — Failures
Snowflake fail → one webhook error line.
Canvas fail → still post channel; one-line canvas note.
PriceShocks stale → ETL-lag webhook; skip canvas.

## Definitions (do not invent)
Formulas are already applied inside `PRICESHOCKS` by BI. Specs:
`docs/priceshocks-table.md` · `docs/payment-spillover-price-shocks.md` · `docs/pricing-structure.md`

**CHANNEL Cumulative / Residual** = NET (spillover recovery excluded).
**SCENARIO** = NET contribution to Cumulative.
**CAUSE_MIX** = GROSS exclusive among fare increases (includes previous_wallet_balance).

## Hard constraints
- Existing automation only
- Never log secrets
- **One** Snowflake query per run (`priceshocks_daily_digest.sql`)
- Two channel webhooks; canvas = breakdown only
- Token discipline: format aggregates only — do not dump the full MCP grid into Slack/context
- Do not recompute ride-level fare logic in the agent
