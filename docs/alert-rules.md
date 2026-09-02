# Alert rules — surfaces & SQL map

Status: updated 2026-09-02 (post-discount exposure added; pending BI cutover).

## Surfaces

| Surface | Content |
|---------|---------|
| **Channel** | **Two** Pulsar posts: SA then JO. 7 unchanged KPI tables + market-specific post-discount exposure. `automations/SLACK_MESSAGE_TEMPLATE.md` |
| **Canvas `F0BN0E7RJ31`** | Last 3 runs; scenario×dropoff NET + exclusive cause mix + discount-segment gross/net table. `automations/CANVAS_WATCH_TEMPLATE.md` |

## Channel KPIs
Cumulative (NET) · Residual (NET) · Rounding · Surcharge · Pickup · Surge · PD  
Cities: SA RUH/JED/MAD/DMM/MEC/Others/Total · JO AMM/IRB/ZRQ/Others/Total

## Canvas
1. NET shock contribution by: WithinA±dest, WithinB±dest, BeyondB (city + Total, DoD/WoW/MoM)
2. Cause mix last day (GROSS exclusive, ~100%): pickup, PD, surge, surcharge, previous_wallet_balance, waiting_time, scenario slices
3. Discount exposure: segment ride share, gross vs post-discount shock rate,
   gross→net excess, average `d_discount`, and absorption

## Discount alert signals

- Cap-bound share rises DoD: more passengers have no discount cushion.
- Capped segment post-discount shock rises faster than `no_discount`.
- Percentage-bound average `d_discount` moves toward zero: absorption is being
  lost or a cap may have fallen.
- Combined promised-not-applied count exceeds approximately 200/day.
- Any discount regression gate fails: fail loudly, withhold discount figures,
  but preserve the unchanged seven fare-integrity tables and non-discount
  canvas sections.

These signals use post-discount `net_fare_diff`. Existing seven channel tables
remain based on locked `fare_diff` for longitudinal comparability.

## SQL map

| File | Use |
|------|-----|
| `JEENY_PROD.RIDE.PRICESHOCKS` | BI daily facts (CHANNEL/SCENARIO/CAUSE_MIX + DISCOUNT/GATE) |
| `sql/priceshocks_daily_digest.sql` | Current v1 automation until DISCOUNT/GATE cutover |
| `sql/priceshocks_daily_digest_v2.sql` | **v2 automation after cutover** — one-query consumer |
| `sql/bi_priceshocks_discount_extension.sql` | BI MERGE for DISCOUNT + GATE into PriceShocks |
| `sql/fare_integrity_channel_summary.sql` | Legacy / debug only |
| `sql/fare_integrity_canvas_breakdown.sql` | Legacy / debug only |
| `sql/daily_price_shock_alert.sql` | Optional headline |

## Ownership
`C0BMWLMR03T` · **Pricing KPI Alerts Slack** · 11:00 AM PKT
