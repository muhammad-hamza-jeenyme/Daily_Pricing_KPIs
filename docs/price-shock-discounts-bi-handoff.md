# BI handoff — post-discount price-shock facts

**Date:** 2026-09-02  
**Owner (Pricing):** Muhammad Hamza  
**Canonical build query:** `sql/bi_price_shock_discounts_daily.sql`  
**Proposed table:** `JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS`

## What BI should build

Create a daily-refreshed aggregate table from the canonical query. This table is
an additive companion to the live `JEENY_PROD.RIDE.PRICESHOCKS` table:

- `PRICESHOCKS` remains the source for the existing fare-integrity headline,
  city KPIs, scenario contribution, and cause mix.
- `PRICESHOCKDISCOUNTS` adds the passenger-experienced post-discount view,
  discount segments, cap exposure, discount absorption, and regression gates.

Do not replace the existing `fare_diff` metrics with `net_fare_diff`. The two
views answer different questions:

- `fare_diff` isolates pricing-engine integrity by adding the applied discount
  back to the receipt.
- `net_fare_diff` measures what the passenger experienced after the expected
  quote discount and final charged discount.

## Refresh and deployment

1. Backfill the last **60 complete `CREATEDDATE` days**.
2. Retain the query's **30-day spillover lookback before the fact window**.
3. Refresh after yesterday's `RIDE.DETAILS`, `RIDE.RECEIPTS`,
   `PASSENGERS.PRICECHECKS`, `PASSENGERS.PRICECHECKKAFKAWITHPROMO`, and
   `PASSENGERS.PROMOTIONENGINE` data are complete.
4. Complete the table before **11:00 AM PKT**.
5. Publish with an atomic table/view swap. Do not cut the automation over until
   the smoke checks and all three gates pass.
6. After BI deployment, switch the automation to
   `sql/priceshocks_daily_digest_v2.sql`.

Recommended key:

`(RIDE_DATE, ROW_TYPE, DISCOUNT_SEGMENT, COUNTRY, CITY_BUCKET, PROMOTION_ID)`

`PROMOTION_ID` is null except for promotion-engine gate rows.

## Universe

The query preserves the existing price-shock universe:

- `RIDE.DETAILS.BOARDED IS NOT NULL`
- `RIDE.UPFRONT.ORIGINALESTIMATEFARE IS NOT NULL`
- `GENERAL.AREAS.COUNTRY_CODE IN ('SA','JO')`
- `RIDE.DETAILS.CREATEDDATE` is the reporting date; do not re-timezone
- one latest matching PriceCheck per ride:
  `LOWER(PRICECHECKS.SERVICEFILTER) = LOWER(DETAILS.REQUEST_SERVICE)`
- currencies stay separate: SA = SAR, JO = JOD

## Source tables and grain controls

| Source | Purpose | Join / grain rule |
|---|---|---|
| `RIDE.DETAILS` | Ride universe, final fare components, applied discount | One row per `RIDEID` |
| `RIDE.UPFRONT` | Upfront-pricing eligibility | `RIDEID` |
| `RIDE.RECEIPTS` | Charged net amount and applied discount | `RIDEID` |
| `GENERAL.AREAS` | Country | `AREA_CODE` |
| `PASSENGERS.PRICECHECKS` | Quote fare components | Latest matching service row per `RIDEID` |
| `PASSENGERS.PRICECHECKKAFKAWITHPROMO` | Voucher rate/cap at quote | Aggregate to one row per `TRACEID` before joining |
| `PASSENGERS.PROMOTIONENGINE` | Automatic promotion applied to ride | `RIDEID`; derive config, never use final `DISCOUNTAMOUNT` as expected |

`PRICECHECKKAFKAWITHPROMO` is natively multi-row by
`(TRACEID, SERVICES)`. Joining it raw fans out rides. Null `TRACEID` rows are
discarded, the event window is widened around the ride window, and only
single-code valid traces are trusted.

Voucher takes precedence over promotion engine when both sources occur. Never
sum the two programs.

## Locked formulas

### Existing fare-integrity metric — unchanged

```sql
vatf                  = IFF(country = 'SA', 1.15, 1.00)
PC_Surcharge_Gross    = ROUND(PriceChecks.SURCHARGE * vatf, 2)
PriceCheck_Shown      = PriceChecks.VALUE + PriceChecks.VAT
                        + PC_Surcharge_Gross
Normalized_Receipt    = Receipts.TOTALAMOUNTWITHTAX
                        + Receipts.DISCOUNT
                        + Receipts.VATONDISCOUNT
Fare_Diff             = Normalized_Receipt - PriceCheck_Shown
```

`PriceChecks.VAT` carries the SA 0.58 gross ride-hailing surcharge. The
platform computes 0.50 ex-VAT + 0.08 VAT; do not replace 0.58 with 0.575.

### Discountable final-ride base

```sql
Base_exVAT = DETAILS.RIDEVALUE
           + DETAILS.RIDEHAILINGSURCHARGE
           + DETAILS.SURCHARGE
           + DETAILS.INTERCITYSURCHARGE
           + DETAILS.WAITINGTIMEFEE
```

Waiting time is discountable. Cancellation fine and wallet balance are not.

### Quote discountable base

Build this component-wise:

```sql
Quote_Base_exVAT = ROUND(PriceChecks.VALUE / vatf, 2)
                 + ROUND(PriceChecks.VAT / vatf, 2)
                 + PriceChecks.SURCHARGE
```

Do not calculate `PriceCheck_Shown / 1.15`; that mishandles the 0.58 SA
ride-hailing surcharge rounding.

### Voucher

`MAXIMUMDISCOUNT` is VAT-inclusive and local currency.

```sql
Expected_Disc_exVAT =
  LEAST(ROUND(MAXIMUMDISCOUNT / vatf, 2),
        ROUND(DISCOUNTVALUE / 100 * Quote_Base_exVAT, 2))
```

For `FIXED_AMOUNT`, the query uses
`LEAST(ROUND(DISCOUNTVALUE / vatf, 2), Quote_Base_exVAT)`.

### Promotion engine

There is no reliable rate/cap config column. Derive both per
`PROMOTIONID` for each ride date from its trailing seven days:

```sql
cap_exvat = MAX(DETAILS.DISCOUNTRR)
pct       = ROUND(MEDIAN(DISCOUNTRR / Base_exVAT) * 100, 0)
            -- only rides strictly below cap
```

Promotion-engine cap is ex-VAT:

```sql
Expected_Disc_exVAT =
  LEAST(cap_exvat, ROUND(pct / 100 * Quote_Base_exVAT, 2))
```

Do not use `PROMOTIONENGINE.DISCOUNTAMOUNT` as expected discount. It is the
final post-ride amount and would force `d_discount = 0`.

### Gross discount and post-discount difference

```sql
Expected_Disc_Gross =
  Expected_Disc_exVAT
  + ROUND(Expected_Disc_exVAT * (vatf - 1), 2)

Actual_Disc_Gross = Receipts.DISCOUNT + Receipts.VATONDISCOUNT
PriceCheck_Net     = PriceCheck_Shown - Expected_Disc_Gross
Charged_Net        = Receipts.TOTALAMOUNTWITHTAX
Net_Fare_Diff      = Charged_Net - PriceCheck_Net
d_discount         = Expected_Disc_Gross - Actual_Disc_Gross
```

Required identity:

```sql
Net_Fare_Diff = Fare_Diff + d_discount
```

Interpretation:

- `d_discount < 0`: discount grew; passenger was partly shielded.
- `d_discount = 0`: discount was capped; passenger absorbed the overrun.
- `d_discount > 0`: final discount was smaller than expected; investigate.

All gross/net shock rates and excess amounts in the new table exclude
spillover-recovery rides using the existing 30-day rule.

## Discount segments

Evaluate in this order:

| `DISCOUNT_SEGMENT` | Definition |
|---|---|
| `voucher_capped` | Valid single-code voucher, percentage leg already at cap at quote |
| `voucher_pct_bound` | Other valid single-code voucher |
| `promoeng_capped` | Promotion engine, percentage leg already at cap at quote |
| `promoeng_pct_bound` | Other promotion-engine ride |
| `discount_no_source` | Applied receipt discount but neither quote source found |
| `no_discount` | No applied/qualified discount source |

The query also emits:

- `cap_bound_total` — voucher + promotion-engine capped segments
- `pct_bound_total` — voucher + promotion-engine percentage-bound segments
- `promised_not_applied` — valid quote voucher but no applied gross discount

## Output schema

| Column | Suggested type | Meaning |
|---|---|---|
| `RIDE_DATE` | DATE | Saudi calendar ride date |
| `ROW_TYPE` | VARCHAR | `SEGMENT`, `SUMMARY`, or `GATE` |
| `DISCOUNT_SEGMENT` | VARCHAR | Segment, summary name, or gate identifier |
| `COUNTRY`, `CITY_BUCKET` | VARCHAR | SA/JO; discount table currently uses `Total` |
| `COUNTRY_RIDES_TOTAL` | NUMBER | All rides in the country/day universe |
| `RIDE_SHARE_PCT` | NUMBER(12,2) | Segment or summary rides / country rides |
| `RIDES_TOTAL` | NUMBER | Rides in this segment/summary |
| `GROSS_SHOCK_RIDES` | NUMBER | Existing `fare_diff > 0.01` shock rides |
| `GROSS_SHOCK_PCT` | NUMBER(12,2) | Existing gross shock rate |
| `NET_SHOCK_RIDES` | NUMBER | Post-discount `net_fare_diff > 0.01` shock rides |
| `NET_SHOCK_PCT` | NUMBER(12,2) | Post-discount shock rate |
| `GROSS_EXCESS_AMOUNT` | NUMBER(18,2) | Positive `fare_diff` excess, local currency |
| `NET_EXCESS_AMOUNT` | NUMBER(18,2) | Positive `net_fare_diff` excess, local currency |
| `AVG_GROSS_EXCESS`, `AVG_NET_EXCESS` | NUMBER(18,2) | Average over corresponding shock rides |
| `AVG_D_DISCOUNT` | NUMBER(18,3) | Average expected minus actual gross discount |
| `ABSORPTION_PCT` | NUMBER(12,2) | `(gross excess - net excess) / gross excess` |
| `CAP_BOUND_AT_QUOTE` | NUMBER(1,0) | 1 for capped segment/summary rows |
| `PROMISED_NOT_APPLIED_RIDES` | NUMBER | Valid voucher at quote, no final discount |
| `CURRENCY` | VARCHAR | `SAR` or `JOD` |
| `PROMOTION_ID` | VARCHAR | Promotion config diagnostic key |
| `DERIVED_PCT` | NUMBER | Inferred promotion percentage |
| `DERIVED_CAP_EXVAT` | NUMBER(18,2) | Inferred promotion ex-VAT cap |
| `N_UNCAPPED` | NUMBER | Below-cap observations in trailing seven days |
| `GATE_NAME`, `GATE_STATUS` | VARCHAR | Regression name and `PASS`/`FAIL` |
| `GATE_VALUE`, `GATE_THRESHOLD` | NUMBER | Regression value and required boundary |
| `COMPUTED_AT` | TIMESTAMP_LTZ | BI job timestamp |

## Mandatory regression gates

The table refresh is not healthy if any gate row has `GATE_STATUS = 'FAIL'`.
The automation will fail loudly and withhold discount output while preserving
the unchanged fare-integrity post.

1. Applied-discount formula:
   - voucher formula match >= 99.9%
   - promotion-engine formula match >= 99.9%
   - VAT rule match >= 99.9%
2. Identity:
   - `net_fare_diff = fare_diff + d_discount` on >= 99.99% of rides
3. Promotion config coverage:
   - every `PROMOTIONID` seen that day has a derived rate and cap
   - `N_UNCAPPED >= 50` in its trailing-seven-day inference window

Two additional safety assertions are emitted:

4. Exact reconciliation to the existing `PRICESHOCKS`
   `cumulative_price_shocks_net` country Total numerator and denominator.
5. Segment direction: capped net shock rate must not be below gross; each
   percentage-bound segment must have negative average `d_discount`.

The spec does not define a numeric tolerance for capped average `d_discount ≈
0`, so the query exposes that value but does not invent a fail threshold.

## Baseline acceptance checks

For rides created 2026-08-24 through 2026-08-30, with spillover recovery
excluded, compare against the implementation-spec baseline:

| Market | Gross shock | Net shock | Gross excess | Net excess |
|---|---:|---:|---:|---:|
| SA | 34.52% | 34.50% | 1,086,412 SAR | 1,081,739 SAR |
| JO | 22.44% | 22.52% | 74,038 JOD | 73,628 JOD |

Red flags:

- Existing gross headline moves materially after the discount join.
- A `*_capped` segment has meaningful negative average `d_discount`.
- A `*_pct_bound` segment has positive average `d_discount`.
- Gross/net amounts are combined across SAR and JOD.
- Voucher rows multiply after joining promo events.

Multi-code voucher traces are deliberately not trusted for discount
reconstruction, following spec trap 7. They fall to `discount_no_source` when
an actual receipt discount exists rather than being assigned a potentially
wrong voucher rate/cap. This is a conservative handling of the spec's internal
tension between its six-segment pseudocode and its instruction to require
`n_codes = 1`.

Expected cap-bound share of all rides for the same seven-day validation window:
approximately 3.5% SA and 19.8% JO.

## Cutover smoke query

```sql
SELECT
    ride_date,
    country,
    COUNT_IF(row_type = 'GATE' AND gate_status = 'FAIL') AS failed_gates,
    COUNT_IF(row_type = 'SEGMENT') AS segment_rows,
    MAX(computed_at) AS computed_at
FROM JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS
WHERE ride_date = CURRENT_DATE() - 1
GROUP BY 1, 2;
```

Expected: both countries present, zero failed gates, and all active discount
segments represented. Only then re-paste the updated automation instructions.

## Implementation smoke test

On 2026-09-02, a one-day Snowflake smoke query for rides dated 2026-09-01
validated the source joins and identity. This smoke used a report-day-relative
30-day LAG input and is not the final 60-day backfill result; the production
query starts the LAG 30 days before the 60-day fact window and must pass the
exact `PRICESHOCKS` reconciliation gate.

| Market | Rides | Gross shock | Post-discount shock | Identity ratio |
|---|---:|---:|---:|---:|
| SA | 130,554 | 35.46% | 35.44% | 1.000000 |
| JO | 84,501 | 21.96% | 22.02% | 1.000000 |

Snowflake query ID: `01c6cd0b-020b-246a-000b-86f721ba7176`.
