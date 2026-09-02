# `JEENY_PROD.RIDE.PRICESHOCKS` — BI daily facts table

Status: **live** (validated 2026-08-31). Refresh daily **before 11:00 AM PKT**.

## Purpose

Pre-aggregated fare-integrity metrics for SA + JO. Cloud Agent reads this table
instead of re-running ride-level joins. Current v1 uses
`sql/priceshocks_daily_digest.sql`; discount-aware v2 reads it alongside the
companion through `sql/priceshocks_daily_digest_v2.sql`.

Sample snapshot: `tables schema/Ride PriceShocks.csv`.

## Discount-aware companion (2026-09-02)

Do not change this table's existing `fare_diff`-based metrics. BI should add
`JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS` using
`sql/bi_price_shock_discounts_daily.sql`.

The companion stores passenger-experienced post-discount analysis:

- six `discount_segment` values and `cap_bound_at_quote`
- gross `fare_diff` vs post-discount `net_fare_diff`
- `d_discount`, gross/net excess, and absorption
- promised-at-quote but not applied discrepancies
- three mandatory daily regression gates plus exact reconciliation and segment
  direction safety checks

Handoff: `docs/price-shock-discounts-bi-handoff.md`.

After BI deploys the companion and its gates pass, the automation switches to
`sql/priceshocks_daily_digest_v2.sql`, which reads both tables in one Snowflake
statement. Until then, keep the active automation on
`sql/priceshocks_daily_digest.sql`.

## Grain

One row per:

`RIDE_DATE × METRIC_FAMILY × METRIC_NAME × COUNTRY × CITY_BUCKET`

| Column | Type | Notes |
|--------|------|-------|
| `RIDE_DATE` | DATE | Saudi calendar ride date |
| `METRIC_FAMILY` | TEXT | `CHANNEL` \| `SCENARIO` \| `CAUSE_MIX` |
| `METRIC_NAME` | TEXT | See catalogues below |
| `COUNTRY` | TEXT | `SA` \| `JO` |
| `CITY_BUCKET` | TEXT | City code, `Others`, or `Total` |
| `RIDES_DENOM` | NUMBER | Denominator |
| `RIDES_FLAGGED` | NUMBER | Numerator |
| `PCT` | NUMBER | `ROUND(100 * flagged / denom, 2)` |
| `COMPUTED_AT` | TIMESTAMP_LTZ | BI job runtime |

**DoD / WoW / MoM are not stored** — derived in `sql/priceshocks_daily_digest.sql`
(yesterday vs −1d / −7d / −28d).

History depth: currently ~60 ride dates in table (enough for MoM).

## Metric catalogues (exact names in Snowflake)

### CHANNEL (Slack — city + Total)

| METRIC_NAME | Slack table |
|-------------|-------------|
| `cumulative_price_shocks_net` | Cumulative PriceShocks % (NET) |
| `residual_fare_increase_net` | Residual fare increase % (NET) |
| `rounding_error` | Rounding error % |
| `surcharge_mismatch` | Surcharge mismatch % |
| `pickup_mismatch` | Pickup mismatch % |
| `surge_mismatch` | Surge mismatch % |
| `pd_mismatch` | PD mismatch % |
| `spillover_recovery` | Monitor only (not a Slack table) |

Cities: SA `RUH|JED|MAD|DMM|MEC|Others|Total` · JO `AMM|IRB|ZRQ|Others|Total`

### SCENARIO (Canvas — NET contribution, city + Total)

`withinA_at_dest` · `withinA_not_dest` · `withinB_at_dest` · `withinB_not_dest` · `beyondB`

### CAUSE_MIX (Canvas — GROSS exclusive, country `Total` only)

`pickup_mismatch` · `pd_mismatch` · `surge_mismatch` · `surcharge_mismatch` ·  
`previous_wallet_balance` · `waiting_time` ·  
`withinA_at_dest` · `withinA_not_dest` · `withinB_at_dest` · `withinB_not_dest` · `beyondB`

`RIDES_DENOM` = GROSS fare-increase rides; `PCT` sums ≈ 100% per country/day.

## Agent consumer

**Current v1 SQL:** `sql/priceshocks_daily_digest.sql`.

**After discount BI cutover:** `sql/priceshocks_daily_digest_v2.sql` (one
Snowflake call across both aggregate tables).

Freshness: `MAX(RIDE_DATE) >= CURRENT_DATE - 1`. If not ready → ETL-lag failure; skip canvas.

## Legacy heavy SQL (debug / rebuild only)

- `sql/fare_integrity_channel_summary.sql`
- `sql/fare_integrity_canvas_breakdown.sql`
- `sql/bi_fare_integrity_daily_facts.sql` (original BI handoff query)

Do **not** run these in the daily automation unless PriceShocks is broken.
