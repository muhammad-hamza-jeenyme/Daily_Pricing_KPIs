# Pricing KPI definitions

Status: **v1 fare-integrity** locked 2026-08-03.

## Comparison windows

| Window | Definition |
|--------|------------|
| **DoD** | Yesterday vs day before |
| **WoW** | Yesterday vs 7 days earlier |
| **MoM** | Yesterday vs **28 days before** |

`createddate` is Saudi calendar date. Agent runs 11:30 AM PKT. Digest window = last 29 complete days (`createddate < CURRENT_DATE`).

## v1 catalogue — fare integrity

| KPI / dimension | Definition | Grain |
|-----------------|------------|-------|
| `ride_count` | Boarded rides with destination (ORIG estimate not null), SA+JO | day × area × scenario × issue_type |
| `issue_type` mix | matched / rounding / increase_non_issue / increase_pricing / decrease_pricing | same |
| `upfrontscenario` mix | withinA / withinB / beyondB share (prod casing) | day × area (+ rollup) |
| `sum_fare_diff` / `avg_fare_diff` | Normalized receipt − PriceCheck shown | same |
| `sum_residual` | Fare_Diff − non_issue (waiting+cancel) | same |
| `dropoff_not_at_dest_rides` | Dropoff ≠ destination | same |
| `scaled_distance_rides` | `SCALEDDISTANCE > 0` | day × area |
| `surge_mismatch_rides` | PC surge ≠ Details surge | day × area |
| `pd_mismatch_rides` | PC PD ≠ Details PD | day × area |

## Formulas

See `docs/pricing-structure.md` and `sql/fare_integrity_daily_digest.sql`.
