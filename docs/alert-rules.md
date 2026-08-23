# Alert rules — severity & thresholds

Status: updated 2026-08-23 (JO split posts; canvas scenario + cause mix).

## Surfaces

| Surface | Content |
|---------|---------|
| **Channel** | **Two** Pulsar posts: SA then JO. 7 KPI tables each. `automations/SLACK_MESSAGE_TEMPLATE.md` |
| **Canvas `F0BN0E7RJ31`** | Last 3 runs; scenario×dropoff NET contribution tables + last-day exclusive cause mix only. `automations/CANVAS_WATCH_TEMPLATE.md` |

## Channel KPIs
Cumulative (NET) · Residual (NET) · Rounding · Surcharge · Pickup · Surge · PD  
Cities: SA RUH/JED/MAD/DMM/MEC/Others/Total · JO AMM/IRB/ZRQ/Others/Total

## Canvas
1. NET shock contribution by: WithinA±dest, WithinB±dest, BeyondB (city + Total, DoD/WoW/MoM)
2. Cause mix last day (GROSS Fare_Diff>0.01, exclusive, ~100%): pickup, PD, surge, surcharge, previous_wallet_balance, waiting, scenario slices, unclassified

## SQL
| File | Use |
|------|-----|
| `sql/fare_integrity_channel_summary.sql` | Channel |
| `sql/fare_integrity_canvas_breakdown.sql` | Canvas |
| `sql/daily_price_shock_alert.sql` | Optional headline |

## Ownership
`C0BMWLMR03T` · **Pricing KPI Alerts Slack** · 11:00 AM PKT
