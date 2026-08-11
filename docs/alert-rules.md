# Alert rules — severity & thresholds

Status: updated 2026-08-11 (surge/PD city tables, Total col, canvas history).

## Slack channel vs Canvas

| Surface | Content |
|---------|---------|
| **Channel (Pulsar)** | Short: `% fare increase` + surcharge / pickup / **surge** / **PD** mismatch counts; city tables (majors + Others + **Total**), fixed-width. `automations/SLACK_MESSAGE_TEMPLATE.md` |
| **Canvas `F0BN0E7RJ31`** | Detailed watches/alerts; **prepend** today, keep prior days. `automations/CANVAS_WATCH_TEMPLATE.md` |

## Channel KPIs

| KPI | Definition |
|-----|------------|
| `% rides with fare increase` | `increase_pricing` share only (`Fare_Diff > 0.01` and residual after waiting/cancel `> 0.01`). **Not** all positive gaps — excludes `increase_non_issue`. |
| Surcharge mismatch rides | withinA + dropoff at dest AND `(Details.SURCHARGE + INTERCITYSURCHARGE) != PriceChecks.SURCHARGE` |
| Pickup mismatch rides | PC pickup vs first `ride_offered` location distance **> 100m** |
| Surge mismatch rides | both non-null AND `ROUND(PC.SURGEMULTIPLIER,4) <> ROUND(Details.SURGEMULTIPLIER,4)` |
| PD mismatch rides | both non-null AND `ROUND(PC.DISCRIMINATIONMULTIPLIER,4) <> ROUND(Details.DISCRIMINATIONMULTIPLIER,4)` |

## Cities

| Country | Columns |
|---------|---------|
| SA | RUH, JED, MAD, DMM, MEC, Others, **Total** (country) |
| JO | AMM, IRB, ZRQ, Others, **Total** (country) |

## Comparisons
DoD / WoW / MoM / vs prior **7d** average. Major shift on Canvas when yesterday > 7d avg.

## SQL
| File | Use |
|------|-----|
| `sql/fare_integrity_channel_summary.sql` | **Main** channel + mismatch metrics |
| `sql/fare_integrity_slack_rollup.sql` | Optional majors detail |

## Ownership
`C0BMWLMR03T` · existing **Pricing KPI Alerts Slack** automation · Pulsar webhook + bot token for canvas.
