# `JEENY_PROD.RIDE.PRICESHOCKS` — BI daily facts table

Status: **live** — full rebuild validated 2026-09-07 (v2 agent cutover).  
Refresh daily **before 11:00 AM PKT**.

## Purpose

Pre-aggregated fare-integrity **and** discount metrics for SA + JO. Cloud Agent
reads this table only (no ride-level joins in the daily job).

**Canonical BI query:** `sql/bi_priceshocks_daily.sql`  
**Handoff:** `docs/price-shock-discounts-bi-handoff.md`  
**Sample snapshot:** `tables schema/Ride PriceShocks.csv` (2026-09-07)

BI **deletes prior data** and inserts the full query output each day (30-day
fact window). One query covers Slack city/issue tables **and** discount block.

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
| `AVG_VALUE` | NUMBER(18,3) NULL | Avg d_discount / avg excess / helper |
| `COMPUTED_AT` | TIMESTAMP_LTZ | BI job runtime |

**DoD / WoW / MoM are not stored** — derived in the thin digest SQL.

History depth: **30** ride dates (enough for MoM = vs 28 days before).

Spillover lookback inside the build query: **30 days before** fact `win_start`.

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
- `gate1_promo_formula` (all campaigns pooled)
- `gate2_net_fare_identity`
- `gate3_promo_config` (all campaigns pooled)
- `gate4_priceshocks_reconciliation` (vs same-run CHANNEL Total)
- `gate5_segment_direction:<segment>`

## Agent consumer

**ACTIVE:** `sql/priceshocks_daily_digest_v2.sql` +
`automations/DAILY_SLACK_INSTRUCTIONS_V2.md`

**Superseded:** `sql/priceshocks_daily_digest.sql` +
`automations/DAILY_SLACK_INSTRUCTIONS.md`

Freshness: `MAX(RIDE_DATE) >= CURRENT_DATE - 1`. If CHANNEL is ready but GATE
fails or DISCOUNT is missing, fare-integrity posts continue; discount block is
withheld.

## Superseded handoff SQL (do not give to BI)

- `sql/bi_fare_integrity_daily_facts.sql` — CHANNEL/SCENARIO/CAUSE_MIX only
- `sql/bi_priceshocks_discount_extension.sql` — DISCOUNT/GATE only
- `sql/bi_price_shock_discounts_daily.sql` — companion-table draft

## Legacy heavy SQL (debug only)

- `sql/fare_integrity_channel_summary.sql`
- `sql/fare_integrity_canvas_breakdown.sql`

Do **not** run these in the daily automation unless PriceShocks is broken.
