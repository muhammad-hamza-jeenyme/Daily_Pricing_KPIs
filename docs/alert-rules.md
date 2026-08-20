# Alert rules — severity & thresholds

Status: updated 2026-08-20 (spillover NET Cumulative/Residual shocks).

## Slack channel vs Canvas

| Surface | Content |
|---------|---------|
| **Channel (Pulsar)** | **Tables only**. Rows `%inc`/`DoD`/`WoW`/`MoM`. Cumulative + Residual are **NET of spillover recovery**. `automations/SLACK_MESSAGE_TEMPLATE.md` |
| **Canvas `F0BN0E7RJ31`** | Last **3** runs; **exceptions only** if rate > **28d avg + 2σ**; trend strip Cumulative+Residual (net); 1–2 investigate leads; optional spillover monitor. No definitions. `automations/CANVAS_WATCH_TEMPLATE.md` |

## Channel KPIs (table order)

| KPI | Definition |
|-----|------------|
| Cumulative PriceShocks % | `Fare_Diff > 0.01` **and not** spillover recovery. **Excludes** rounding |
| Residual fare increase % | `increase_pricing` **and not** spillover recovery |
| Rounding error % | `0 < \|Fare_Diff\| ≤ 0.01` (tech bug) |
| Surcharge mismatch % | withinA + dropoff at dest AND `(Details.SURCHARGE + INTERCITYSURCHARGE) != PriceChecks.SURCHARGE` |
| Pickup mismatch % | PC pickup vs first `ride_offered` **> 100m** |
| Surge mismatch % | both non-null AND `ROUND(PC.SURGEMULTIPLIER,4) <> ROUND(Details.SURGEMULTIPLIER,4)` |
| PD mismatch % | both non-null AND `ROUND(PC.DISCRIMINATIONMULTIPLIER,4) <> ROUND(Details.DISCRIMINATIONMULTIPLIER,4)` |

**Spillover recovery** (excluded from Cumulative/Residual): prior ride `OUTSTANDINGBALANCE > 0` and `ABS(prev_outs − CANCELLATIONFINE) ≤ 0.02`. Threshold context: ~1 SAR SA / ~0.1 JOD JO for deferred 2nd debit on digital pay. Spec: `docs/payment-spillover-price-shocks.md`.

## Cities

| Country | Columns |
|---------|---------|
| SA | RUH, JED, MAD, DMM, MEC, Others, **Total** |
| JO | AMM, IRB, ZRQ, Others, **Total** |

## Comparisons
Channel tables: DoD / WoW / MoM as **pp**. Optional `:warning:` on table title when country rate > prior **7d** avg.  
Canvas exceptions: rate > prior **28d** mean + **2 × sample stddev** (`exception_28d_2sd_*` in SQL).

## SQL
| File | Use |
|------|-----|
| `sql/fare_integrity_channel_summary.sql` | **Main** channel + canvas (NET shocks, 30d spillover lookback) |
| `sql/daily_price_shock_alert.sql` | Headline country shocks_gross / spillover_excluded / shocks_net |
| `sql/fare_integrity_slack_rollup.sql` | Optional majors detail |

## Ownership
`C0BMWLMR03T` · existing **Pricing KPI Alerts Slack** automation · Pulsar webhook + bot token for canvas.
