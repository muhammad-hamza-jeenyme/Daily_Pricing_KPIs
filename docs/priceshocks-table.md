# `JEENY_PROD.RIDE.PRICESHOCKS` — BI daily facts table

Status: **live** (validated 2026-08-31). Discount extension pending BI deploy.
Refresh daily **before 11:00 AM PKT**.

## Purpose

Pre-aggregated fare-integrity metrics for SA + JO. Cloud Agent reads this table
instead of re-running ride-level joins. Current v1 uses
`sql/priceshocks_daily_digest.sql`. After discount rows are deployed, v2 uses
`sql/priceshocks_daily_digest_v2.sql` against the **same table**.

Sample snapshot: `tables schema/Ride PriceShocks.csv`.

## Discount extension (2026-09-02)

Do **not** create a companion table. Extend this table:

1. Keep CHANNEL / SCENARIO / CAUSE_MIX formulas and metric names unchanged.
2. Add nullable columns `AMOUNT_VALUE`, `AVG_VALUE`.
3. MERGE rows from `sql/bi_priceshocks_discount_extension.sql` with
   `METRIC_FAMILY IN ('DISCOUNT','GATE')`.

Handoff: `docs/price-shock-discounts-bi-handoff.md`.

## Grain

One row per:

`RIDE_DATE × METRIC_FAMILY × METRIC_NAME × COUNTRY × CITY_BUCKET`

| Column | Type | Notes |
|--------|------|-------|
| `RIDE_DATE` | DATE | Saudi calendar ride date |
| `METRIC_FAMILY` | TEXT | `CHANNEL` \| `SCENARIO` \| `CAUSE_MIX` \| `DISCOUNT` \| `GATE` |
| `METRIC_NAME` | TEXT | See catalogues below |
| `COUNTRY` | TEXT | `SA` \| `JO` |
| `CITY_BUCKET` | TEXT | City code, `Others`, or `Total` |
| `RIDES_DENOM` | NUMBER | Denominator |
| `RIDES_FLAGGED` | NUMBER | Numerator (for GATE: 1=PASS, 0=FAIL) |
| `PCT` | NUMBER | Rate / match % |
| `AMOUNT_VALUE` | NUMBER(18,2) NULL | Excess money or secondary gate value |
| `AVG_VALUE` | NUMBER(18,3) NULL | Avg d_discount / avg excess / n_uncapped |
| `COMPUTED_AT` | TIMESTAMP_LTZ | BI job runtime |

**DoD / WoW / MoM are not stored** — derived in the thin digest SQL.

History depth: keep ~60 ride dates (enough for MoM).

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

### DISCOUNT (Slack Output 5 + canvas — country `Total` only)

Prefixes: six segments + `cap_bound_total` + `pct_bound_total`.

Suffixes:

- `__ride_share`
- `__gross_shock` (`AMOUNT_VALUE` = gross excess, `AVG_VALUE` = avg gross)
- `__net_shock` (`AMOUNT_VALUE` = net excess, `AVG_VALUE` = avg `d_discount`)
- `__absorption`

Plus `promised_not_applied` (no suffix).

### GATE (regression — country `Total` only)

`RIDES_FLAGGED = 1` PASS / `0` FAIL.

- `gate1_voucher_formula`
- `gate1_promo_formula:<PROMOTIONID>`
- `gate2_net_fare_identity`
- `gate3_promo_config:<PROMOTIONID>`
- `gate4_priceshocks_reconciliation`
- `gate5_segment_direction:<segment>`

## Agent consumer

**Current v1 SQL:** `sql/priceshocks_daily_digest.sql` (CHANNEL/SCENARIO/CAUSE_MIX).

**After discount rows are live:** `sql/priceshocks_daily_digest_v2.sql` (same table,
adds DISCOUNT + GATE).

Freshness: `MAX(RIDE_DATE) >= CURRENT_DATE - 1`. If CHANNEL is ready but GATE
fails or DISCOUNT is missing, fare-integrity posts continue; discount block is
withheld.

## Legacy heavy SQL (debug / rebuild only)

- `sql/fare_integrity_channel_summary.sql`
- `sql/fare_integrity_canvas_breakdown.sql`
- `sql/bi_fare_integrity_daily_facts.sql` (original CHANNEL/SCENARIO/CAUSE_MIX handoff)
- `sql/bi_price_shock_discounts_daily.sql` (superseded companion-table draft)

Do **not** run these in the daily automation unless PriceShocks is broken.
