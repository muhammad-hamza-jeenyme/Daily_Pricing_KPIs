# BI handoff — full daily rebuild of `JEENY_PROD.RIDE.PRICESHOCKS`

**Date:** 2026-09-02  
**Owner (Pricing):** Muhammad Hamza  
**Canonical query (share this one only):** `sql/bi_priceshocks_daily.sql`  
**Target table:** `JEENY_PROD.RIDE.PRICESHOCKS` (existing — no new table)

This single query is enough for the next day’s Slack + canvas posts:
city-level CHANNEL / SCENARIO issue tables, country CAUSE_MIX, and the
discount / gate block.

## Ask of BI

1. Ensure nullable columns exist on `PRICESHOCKS`:

```sql
ALTER TABLE JEENY_PROD.RIDE.PRICESHOCKS
  ADD COLUMN IF NOT EXISTS AMOUNT_VALUE NUMBER(18,2),
  ADD COLUMN IF NOT EXISTS AVG_VALUE NUMBER(18,3);
```

2. Every day, **after** yesterday’s ride / receipt / price-check / promo /
   promotion-engine data is complete, and **before 11:00 AM PKT**:
   - Delete prior table contents (full replace), **or** delete all rows in the
     fact window and replace.
   - Run `sql/bi_priceshocks_daily.sql`.
   - Insert the full result into `JEENY_PROD.RIDE.PRICESHOCKS`.

Suggested pattern:

```sql
TRUNCATE TABLE JEENY_PROD.RIDE.PRICESHOCKS;

INSERT INTO JEENY_PROD.RIDE.PRICESHOCKS (
    RIDE_DATE, METRIC_FAMILY, METRIC_NAME, COUNTRY, CITY_BUCKET,
    RIDES_DENOM, RIDES_FLAGGED, PCT, AMOUNT_VALUE, AVG_VALUE, COMPUTED_AT
)
/* paste / schedule sql/bi_priceshocks_daily.sql here */;
```

3. Do **not** run a separate CHANNEL job and a separate discount job.
4. Do **not** use:
   - `sql/bi_fare_integrity_daily_facts.sql` (superseded)
   - `sql/bi_priceshocks_discount_extension.sql` (superseded)
   - `sql/bi_price_shock_discounts_daily.sql` (superseded companion draft)

## Output grain

One row per:

`RIDE_DATE × METRIC_FAMILY × METRIC_NAME × COUNTRY × CITY_BUCKET`

| Column | Type | Notes |
|---|---|---|
| `RIDE_DATE` | DATE | Saudi calendar `CREATEDDATE` |
| `METRIC_FAMILY` | TEXT | `CHANNEL` \| `SCENARIO` \| `CAUSE_MIX` \| `DISCOUNT` \| `GATE` |
| `METRIC_NAME` | TEXT | See catalogues below |
| `COUNTRY` | TEXT | `SA` \| `JO` |
| `CITY_BUCKET` | TEXT | City / `Others` / `Total` |
| `RIDES_DENOM` | NUMBER | Denominator |
| `RIDES_FLAGGED` | NUMBER | Numerator (GATE: `1`=PASS, `0`=FAIL) |
| `PCT` | NUMBER | Rate / match % |
| `AMOUNT_VALUE` | NUMBER(18,2) NULL | Used by DISCOUNT/GATE; NULL elsewhere |
| `AVG_VALUE` | NUMBER(18,3) NULL | Used by DISCOUNT/GATE; NULL elsewhere |
| `COMPUTED_AT` | TIMESTAMP_LTZ | Job runtime |

**Primary key:** `(RIDE_DATE, METRIC_FAMILY, METRIC_NAME, COUNTRY, CITY_BUCKET)`

**DoD / WoW / MoM are not stored.** Cursor derives them from the 30-day history.

## Windows

| Window | Value |
|---|---|
| Fact window | last **30** complete `CREATEDDATE` days |
| Spillover lookback | **30 days before** `win_start` (do not shrink) |
| Promo-engine config lookback | 7 trailing days ending on each fact date |

## Metric catalogues

### CHANNEL (Slack city + Total)

Cities: SA `RUH|JED|MAD|DMM|MEC|Others|Total` · JO `AMM|IRB|ZRQ|Others|Total`

| `METRIC_NAME` | Meaning |
|---|---|
| `cumulative_price_shocks_net` | Fare_Diff > 0.01, exclude spillover recovery (**NET**) |
| `residual_fare_increase_net` | Fare_Diff > 0.01 and Residual > 0.01, exclude recovery (**NET**) |
| `rounding_error` | `0 < \|Fare_Diff\| ≤ 0.01` |
| `surcharge_mismatch` | withinA + dropoff at dest + surcharge mismatch |
| `pickup_mismatch` | PC pickup vs first `ride_offered` > 100m |
| `surge_mismatch` | PC vs Details surge |
| `pd_mismatch` | PC vs Details PD |
| `spillover_recovery` | monitor only |

### SCENARIO (Canvas — NET contribution, city + Total)

`withinA_at_dest` · `withinA_not_dest` · `withinB_at_dest` ·
`withinB_not_dest` · `beyondB`

`PCT` = contribution vs all completed rides in universe.

### CAUSE_MIX (Canvas — exclusive GROSS, country `Total` only)

Among `Fare_Diff > 0.01` (GROSS). Exclusive first-match; % sums ≈ 100%.

`pickup_mismatch` · `pd_mismatch` · `surge_mismatch` · `surcharge_mismatch` ·
`previous_wallet_balance` · `waiting_time` · scenario buckets · `unclassified`

### DISCOUNT (Slack Output 5 + canvas — country `Total` only)

Prefixes: six segments + `cap_bound_total` + `pct_bound_total`  
Suffixes: `__ride_share` · `__gross_shock` · `__net_shock` · `__absorption`  
Plus: `promised_not_applied`

Promotion campaigns are **pooled** into segment totals (no promo-id rows).

### GATE (regression — country `Total` only)

`RIDES_FLAGGED = 1` PASS / `0` FAIL.

| `METRIC_NAME` | Pass rule |
|---|---|
| `gate1_voucher_formula` | formula ≥ 99.9 and VAT ≥ 99.9 |
| `gate1_promo_formula` | same, all campaigns pooled |
| `gate2_net_fare_identity` | identity ≥ 99.99% |
| `gate3_promo_config` | every active campaign OK (`n_uncapped ≥ 50`) |
| `gate4_priceshocks_reconciliation` | discount-universe gross shocks match **this run’s** CHANNEL Total `cumulative_price_shocks_net` |
| `gate5_segment_direction:<segment>` | capped: net% ≥ gross%; pct-bound: avg `d_discount` < 0 |

## Locked formulas (do not change without Pricing)

```sql
vatf               = IFF(SA, 1.15, 1.00)
PC_Surcharge_Gross = ROUND(PriceChecks.SURCHARGE * vatf, 2)
PriceCheck_Shown   = VALUE + VAT + PC_Surcharge_Gross
Normalized_Receipt = TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT
Fare_Diff          = Normalized_Receipt - PriceCheck_Shown

Net_Fare_Diff = TOTALAMOUNTWITHTAX - (PriceCheck_Shown - Expected_Disc_Gross)
d_discount    = Expected_Disc_Gross - (DISCOUNT + VATONDISCOUNT)
-- assert Net_Fare_Diff = Fare_Diff + d_discount (±0.011)
```

- Spillover recovery excluded from NET shocks; 30d lookback required.
- Voucher cap VAT-inclusive; promotion-engine inferred cap ex-VAT.
- Quote base component-wise; never `Shown / 1.15`.
- Waiting fee in discountable base; never use `PROMOTIONENGINE.DISCOUNTAMOUNT`
  as expected quote discount.
- Voucher precedence over promotion engine; never sum both.
- Never invent fare formulas; never sum SAR with JOD.

## Smoke checks after first load

```sql
-- Families present for yesterday
SELECT metric_family, COUNT(*), COUNT(DISTINCT city_bucket) AS n_cities
FROM JEENY_PROD.RIDE.PRICESHOCKS
WHERE ride_date = CURRENT_DATE() - 1
GROUP BY 1
ORDER BY 1;
-- Expect CHANNEL + SCENARIO with multiple cities; CAUSE_MIX/DISCOUNT/GATE = Total only

-- City CHANNEL row exists (Slack issue tables)
SELECT country, city_bucket, pct
FROM JEENY_PROD.RIDE.PRICESHOCKS
WHERE ride_date = CURRENT_DATE() - 1
  AND metric_family = 'CHANNEL'
  AND metric_name = 'cumulative_price_shocks_net'
ORDER BY 1, 2;

-- Failed gates (investigate any RIDES_FLAGGED = 0)
SELECT metric_name, country, rides_flagged, pct, amount_value, avg_value
FROM JEENY_PROD.RIDE.PRICESHOCKS
WHERE ride_date = CURRENT_DATE() - 1
  AND metric_family = 'GATE'
  AND rides_flagged = 0;
```

## Consumer (Pricing / Cursor)

**Active:**

- Agent SQL: `sql/priceshocks_daily_digest_v2.sql`
- Instructions: `automations/DAILY_SLACK_INSTRUCTIONS_V2.md`

Validated live 2026-09-07 (`is_ready=1`, `discount_is_ready=1`).

## Specs

- `docs/priceshocks-table.md`
- `docs/price-shock-discounts-implementation-spec.md`
- `docs/payment-spillover-price-shocks.md`
- `docs/kpi-definitions.md`
