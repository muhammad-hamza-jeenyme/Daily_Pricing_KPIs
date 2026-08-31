# RIDE.PRICESHOCKS

BI pre-aggregated fare-integrity metrics. Refreshed before **11:00 AM PKT**.  
Daily Pulsar job reads this table only via `sql/priceshocks_daily_digest.sql` — do **not** recompute ride-level fare logic in the agent.

## Columns

| Column | Meaning |
|--------|---------|
| `RIDE_DATE` | Saudi calendar ride day |
| `METRIC_FAMILY` | `CHANNEL` \| `SCENARIO` \| `CAUSE_MIX` |
| `METRIC_NAME` | KPI / segment key (see below) |
| `COUNTRY` | `SA` \| `JO` |
| `CITY_BUCKET` | SA: `RUH\|JED\|MAD\|DMM\|MEC\|Others\|Total`; JO: `AMM\|IRB\|ZRQ\|Others\|Total` |
| `RIDES_DENOM` / `RIDES_FLAGGED` | Denominator / numerator ride counts |
| `PCT` | Percent (already computed by BI) |
| `COMPUTED_AT` | BI refresh timestamp |

## Metric families

| Family | Grain | Meaning |
|--------|-------|---------|
| **CHANNEL** | city + country Total | Slack KPIs. `cumulative_price_shocks_net` / `residual_fare_increase_net` are **NET** (spillover recovery excluded). Also: `rounding_error`, `surcharge_mismatch`, `pickup_mismatch`, `surge_mismatch`, `pd_mismatch`, optional monitor `spillover_recovery` (not posted in Slack tables). |
| **SCENARIO** | city + country Total | **NET** contribution to Cumulative by `withinA_at_dest`, `withinA_not_dest`, `withinB_at_dest`, `withinB_not_dest`, `beyondB`. Canvas only. |
| **CAUSE_MIX** | country `Total` only | Last-day **GROSS** exclusive % among fare increases (includes `previous_wallet_balance`). Must sum ≈100%. Canvas only. |

## Comparisons (digest SQL)

On report date = `CURRENT_DATE - 1`:

- **DoD** = pct(report) − pct(report − 1)
- **WoW** = pct(report) − pct(report − 7)
- **MoM** = pct(report) − pct(report − 28)

## Freshness

Ready when `MAX(RIDE_DATE) >= CURRENT_DATE - 1`. If stale → one ETL-lag webhook; skip canvas.

## Related specs

- `docs/payment-spillover-price-shocks.md` — NET vs spillover recovery  
- `docs/pricing-structure.md` — fare compare identity  
- `automations/SLACK_MESSAGE_TEMPLATE.md` / `automations/CANVAS_WATCH_TEMPLATE.md`
