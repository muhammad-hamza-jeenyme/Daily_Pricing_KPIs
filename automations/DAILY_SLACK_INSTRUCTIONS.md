# Pulsar daily fare-integrity report (Cloud Automation)

**Use existing automation only** (Pricing KPI Alerts Slack). Do not create a new one.

Paste this entire file into the automation **Instructions**. Repo: `muhammad-hamza-jeenyme/Daily_Pricing_KPIs` @ `main`.

## Goal
Daily **11:00 AM PKT** (`0 6 * * *` UTC):
1. Snowflake channel SQL → **two** Pulsar webhook posts (SA, then JO)
2. Snowflake canvas SQL → update Canvas `F0BN0E7RJ31` (breakdown tables only; keep last 3 runs)

## Tools / secrets
- Snowflake MCP
- `PULSAR_SLACK_WEBHOOK_URL`
- `PULSAR_SLACK_BOT_TOKEN` (`canvases:read` + `canvases:write`)
- Canvas `F0BN0E7RJ31` — https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31 (**not** a secret)

## Step 1 — Channel SQL
Run `sql/fare_integrity_channel_summary.sql`.

Use `grain=country` + `grain=city` for report date:
- `pct_cumulative_shock`, `pct_increase_pricing` (**NET** of spillover)
- `pct_rounding`, `pct_surcharge_mismatch`, `pct_pickup_mismatch`, `pct_surge_mismatch`, `pct_pd_mismatch`
- DoD/WoW/MoM pp deltas for each

Do **not** shrink spillover lookback (30d before window).

## Step 2 — Channel posts (fix JO break)
Follow `automations/SLACK_MESSAGE_TEMPLATE.md`.

**Must post TWO webhook messages:**
1. **SA only** — header + 7 tables (Cumulative → Residual → Rounding → Surcharge → Pickup → Surge → PD)
2. **JO only** — header + same 7 tables + canvas link footer

Never combine SA+JO in one payload (JO fences break after ~2 tables).  
Each table = own code fence; even number of \`\`\` per message; JO cols `AMM|IRB|ZRQ|Others|Total` only.

## Step 3 — Canvas SQL
Run `sql/fare_integrity_canvas_breakdown.sql`.

| grain | Use |
|-------|-----|
| `scenario_city` / `scenario_country` | NET shock contribution % by WithinA/B×dropoff + BeyondB; city tables + Total; DoD/WoW/MoM |
| `cause_mix` | Last-day GROSS fare-increase exclusive % by country (must sum ≈100%) |

## Step 4 — Canvas update
Follow `automations/CANVAS_WATCH_TEMPLATE.md`.

**Must:**
1. Prepend today’s dated section; keep newest **3** runs only
2. Content **only**: SA/JO scenario×dropoff tables + SA/JO cause-mix tables
3. **No** exceptions, investigate list, trends, definitions, or alerts

## Step 5 — Failures
Snowflake fail → one webhook error line.  
Canvas fail → still post channel; one-line canvas note.

## Definitions (do not invent)

**NET Cumulative / Residual** — exclude spillover recovery (`prev_outs` match cancel fine ±0.02). Spec: `docs/payment-spillover-price-shocks.md`.

**Scenario canvas tables** — contribution: (NET shock ∧ segment) / all completed rides.

**Cause mix** — among `Fare_Diff > 0.01` (GROSS), exclusive order:  
pickup → PD → surge → surcharge → previous_wallet_balance → waiting → withinA_at_dest → withinA_not_dest → withinB_at_dest → withinB_not_dest → beyondB → unclassified.

## Hard constraints
- Existing automation only
- Never log secrets
- Two channel webhooks; canvas = breakdown only
- Token discipline: do not dump full SQL result into Slack; format aggregates only; do not re-query the same SQL twice
