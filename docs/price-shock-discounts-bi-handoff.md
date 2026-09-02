# BI handoff — extend `JEENY_PROD.RIDE.PRICESHOCKS` with discounts

**Date:** 2026-09-02 (revised — single-table path)  
**Owner (Pricing):** Muhammad Hamza  
**Canonical build query:** `sql/bi_priceshocks_discount_extension.sql`  
**Target table:** `JEENY_PROD.RIDE.PRICESHOCKS` (existing — **no new table**)

## Ask of BI

1. Keep the current CHANNEL / SCENARIO / CAUSE_MIX refresh **unchanged**.
2. Add two nullable columns to `PRICESHOCKS` (NULL for existing families).
3. Run `sql/bi_priceshocks_discount_extension.sql` and **MERGE/INSERT** only
   `METRIC_FAMILY IN ('DISCOUNT','GATE')` into `PRICESHOCKS`.
4. Refresh before **11:00 AM PKT**, after yesterday’s ride / receipt / price-check
   / promo / promotion-engine data is complete.
5. Backfill the last **60** complete `CREATEDDATE` days for DISCOUNT + GATE.

Do **not** replace `fare_diff`-based CHANNEL metrics with post-discount
`net_fare_diff`. Discount rows are additive.

## DDL additions

```sql
ALTER TABLE JEENY_PROD.RIDE.PRICESHOCKS
  ADD COLUMN IF NOT EXISTS AMOUNT_VALUE NUMBER(18,2),
  ADD COLUMN IF NOT EXISTS AVG_VALUE NUMBER(18,3);
```

| Column | Type | Meaning |
|---|---|---|
| `AMOUNT_VALUE` | NUMBER(18,2) NULL | Excess money (local currency) or secondary gate value |
| `AVG_VALUE` | NUMBER(18,3) NULL | Avg `d_discount`, avg excess, or `n_uncapped` |

Primary key remains:

`(RIDE_DATE, METRIC_FAMILY, METRIC_NAME, COUNTRY, CITY_BUCKET)`

Promotion-engine gate rows encode the id in `METRIC_NAME`
(`gate1_promo_formula:<id>`, `gate3_promo_config:<id>`).

## Output grain

Same as live table:

`RIDE_DATE × METRIC_FAMILY × METRIC_NAME × COUNTRY × CITY_BUCKET`

| Column | Notes |
|---|---|
| `METRIC_FAMILY` | New values: `DISCOUNT`, `GATE` |
| `CITY_BUCKET` | Always `Total` for these new families |
| `RIDES_DENOM` / `RIDES_FLAGGED` / `PCT` | Same semantics as today |
| `AMOUNT_VALUE` / `AVG_VALUE` | Used by DISCOUNT / GATE only |
| `COMPUTED_AT` | Job timestamp |

## DISCOUNT metric catalogue (`CITY_BUCKET = Total`)

Segments / rollups used as the `segment` prefix:

- Six segments: `voucher_capped`, `voucher_pct_bound`, `promoeng_capped`,
  `promoeng_pct_bound`, `discount_no_source`, `no_discount`
- Rollups: `cap_bound_total`, `pct_bound_total`
- Monitor: `promised_not_applied` (no suffix)

| `METRIC_NAME` pattern | `RIDES_DENOM` | `RIDES_FLAGGED` | `PCT` | `AMOUNT_VALUE` | `AVG_VALUE` |
|---|---|---|---|---|---|
| `{segment}__ride_share` | country rides | segment rides | ride share % | NULL | NULL |
| `{segment}__gross_shock` | segment rides | `fare_diff > 0.01` shocks (excl. spillover) | gross shock % | gross excess | avg gross excess |
| `{segment}__net_shock` | segment rides | `net_fare_diff > 0.01` shocks (excl. spillover) | net shock % | net excess | avg `d_discount` |
| `{segment}__absorption` | 1 | 1 | absorption % | NULL | NULL |
| `promised_not_applied` | country rides | promised count | rate % | NULL | NULL |

Absorption:

`(gross_excess − net_excess) / gross_excess × 100`

Never sum SAR with JOD.

## GATE metric catalogue (`CITY_BUCKET = Total`)

`RIDES_FLAGGED = 1` means PASS, `0` means FAIL.

| `METRIC_NAME` | Pass rule | `PCT` | `AMOUNT_VALUE` | `AVG_VALUE` |
|---|---|---|---|---|
| `gate1_voucher_formula` | formula ≥ 99.9 and VAT ≥ 99.9 | formula match % | VAT match % | NULL |
| `gate1_promo_formula:<PROMOTIONID>` | same | formula match % | VAT match % | `n_uncapped` |
| `gate2_net_fare_identity` | identity ratio ≥ 99.99% | identity % | NULL | NULL |
| `gate3_promo_config:<PROMOTIONID>` | derived pct/cap present and `n_uncapped ≥ 50` | derived pct | derived cap | `n_uncapped` |
| `gate4_priceshocks_reconciliation` | exact match to CHANNEL `cumulative_price_shocks_net` Total counts | recomputed gross % | NULL | NULL |
| `gate5_segment_direction:<segment>` | capped: net% ≥ gross%; pct-bound: avg `d_discount` < 0 | net shock % | gross shock % | avg `d_discount` |

Any `GATE` row with `RIDES_FLAGGED = 0` is a loud failure for the discount block.
Existing CHANNEL posts should still run.

## Locked formulas (do not change CHANNEL)

```sql
vatf               = IFF(SA, 1.15, 1.00)
PC_Surcharge_Gross = ROUND(PriceChecks.SURCHARGE * vatf, 2)
PriceCheck_Shown   = VALUE + VAT + PC_Surcharge_Gross
Normalized_Receipt = TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT
Fare_Diff          = Normalized_Receipt - PriceCheck_Shown
```

### New passenger-experience layer

```sql
Quote_Base_exVAT =
    ROUND(VALUE / vatf, 2) + ROUND(VAT / vatf, 2) + SURCHARGE

Expected_Disc_Gross =
    Expected_Disc_exVAT + ROUND(Expected_Disc_exVAT * (vatf - 1), 2)

Net_Fare_Diff = TOTALAMOUNTWITHTAX - (PriceCheck_Shown - Expected_Disc_Gross)
d_discount    = Expected_Disc_Gross - (DISCOUNT + VATONDISCOUNT)
```

Identity: `Net_Fare_Diff = Fare_Diff + d_discount` (±0.011).

Voucher cap is **VAT-inclusive**; promotion-engine inferred cap is **ex-VAT**.
Build quote base component-wise (never `PriceCheck_Shown / 1.15`).
Discountable base includes `WAITINGTIMEFEE`; excludes cancellation fine.
Aggregate `PRICECHECKKAFKAWITHPROMO` to one row per `TRACEID` before joining.
Voucher takes precedence over promotion engine; never sum both.
Do not use `PROMOTIONENGINE.DISCOUNTAMOUNT` as expected quote discount.

## Refresh recommendation

1. Existing job continues to refresh CHANNEL / SCENARIO / CAUSE_MIX.
2. After that (or in the same warehouse job), run the extension query.
3. Delete/replace rows for the target dates where
   `METRIC_FAMILY IN ('DISCOUNT','GATE')`, then insert the query output.
4. Keep spillover lookback **30 days before** the 60-day fact window.
5. Gate 4 compares against already-written CHANNEL Total rows for the same day —
   refresh CHANNEL first if both run in one pipeline.

## Smoke checks after backfill

```sql
-- New families present for yesterday
SELECT metric_family, COUNT(*)
FROM JEENY_PROD.RIDE.PRICESHOCKS
WHERE ride_date = CURRENT_DATE() - 1
  AND metric_family IN ('DISCOUNT', 'GATE')
GROUP BY 1;

-- Failed gates (should be empty)
SELECT metric_name, country, rides_flagged, pct, amount_value, avg_value
FROM JEENY_PROD.RIDE.PRICESHOCKS
WHERE ride_date = CURRENT_DATE() - 1
  AND metric_family = 'GATE'
  AND rides_flagged = 0;

-- CHANNEL totals still present and untouched
SELECT country, rides_denom, rides_flagged, pct
FROM JEENY_PROD.RIDE.PRICESHOCKS
WHERE ride_date = CURRENT_DATE() - 1
  AND metric_family = 'CHANNEL'
  AND metric_name = 'cumulative_price_shocks_net'
  AND city_bucket = 'Total';
```

Red flags:

- Existing CHANNEL Total rates move materially after this change.
- Join fan-out (ride counts inflate).
- Capped segments show meaningful negative avg `d_discount`.
- Percentage-bound segments show positive avg `d_discount`.
- SAR and JOD are summed.

## Consumer after BI cutover

Cursor automation switches to `sql/priceshocks_daily_digest_v2.sql`, which reads
**only** `JEENY_PROD.RIDE.PRICESHOCKS` (CHANNEL + SCENARIO + CAUSE_MIX +
DISCOUNT + GATE).

Until DISCOUNT/GATE rows exist for yesterday, keep the active automation on
`sql/priceshocks_daily_digest.sql`.

## Files to share with BI

1. **This document** — `docs/price-shock-discounts-bi-handoff.md`
2. **Query** — `sql/bi_priceshocks_discount_extension.sql`
3. Optional detail — `docs/price-shock-discounts-implementation-spec.md`

Do **not** use `sql/bi_price_shock_discounts_daily.sql` for this path; that file
targeted a separate companion table and is superseded for BI handoff.
