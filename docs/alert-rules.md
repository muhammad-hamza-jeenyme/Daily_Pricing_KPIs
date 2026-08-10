# Alert rules — severity & thresholds

Status: updated 2026-08-10 (surcharge + pickup mismatch).

## Slack channel vs Canvas

| Surface | Content |
|---------|---------|
| **Channel (Pulsar)** | Short: `% fare increase` + **surcharge mismatch** counts + **pickup mismatch** counts; city tables (majors + Others). `automations/SLACK_MESSAGE_TEMPLATE.md` |
| **Canvas `F0BN0E7RJ31`** | Detailed watches/alerts. `automations/CANVAS_WATCH_TEMPLATE.md` |

## Channel KPIs

| KPI | Definition |
|-----|------------|
| `% rides with fare increase` | `increase_pricing` share |
| Surcharge mismatch rides | withinA + dropoff at dest AND `(Details.SURCHARGE + INTERCITYSURCHARGE) != PriceChecks.SURCHARGE` |
| Pickup mismatch rides | PC pickup vs first `ride_offered` location distance **> 100m** |

## Cities

| Country | Columns |
|---------|---------|
| SA | RUH, JED, MAD, DMM, MEC, Others |
| JO | AMM, IRB, ZRQ, Others |

## Comparisons
DoD / WoW / MoM / vs prior **7d** average. Major shift on Canvas when yesterday > 7d avg.

## SQL
| File | Use |
|------|-----|
| `sql/fare_integrity_channel_summary.sql` | **Main** channel + mismatch metrics |
| `sql/fare_integrity_slack_rollup.sql` | Optional majors detail |

## Ownership
`C0BMWLMR03T` · existing **Pricing KPI Alerts Slack** automation · Pulsar webhook + bot token for canvas.
