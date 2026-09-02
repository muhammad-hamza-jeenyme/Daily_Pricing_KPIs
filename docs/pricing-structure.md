# Jeeny pricing structure

Status: **v1 locked** (2026-08-03). SQL ready for Snowflake validation.

## Journey & goal

`PriceCheck → Request → Accept → Boarded → Finished`

Track **fare integrity / price shocks** on boarded rides with destination: charged fare vs PriceCheck shown fare. Segregate **non-issue** vs **pricing-experience** drivers; include **fare decreases**. Split by `withinA` / `withinB` / `BeyondB`.

Universe: `BOARDED IS NOT NULL`, `ORIGINALESTIMATEFARE IS NOT NULL`, `country_code IN ('SA','JO')`.  
Time: `Ride.Details.CREATEDDATE` in **Saudi time**; agent **11:00 AM PKT**.  
Grain for digests: **day × AREA_CODE × UPFRONTSCENARIO × issue-type**, last **29 days** (DoD / WoW / MoM vs 28d prior).

## Upfront flowchart (confirmed)

- Destination selected → else re-Google; dropoff at destination → else re-Google.
- `UPFRONTSCENARIO` casing in Snowflake: `withinA` | `withinB` | `beyondB` (only these three when destination was selected).
- **withinA** when **either**:
  1. Actual time is inside the A band: `ACTUALTIME * 60 ∈ [TIMETHRESHHOLDSALOWVALUE, TIMETHRESHHOLDSAHIGHVALUE]` (VALUE cols are seconds), **or**
  2. `ACTUALTIME − APPLIEDESTIMATETIME ≤ MAXWITHINMINUTESVARIANCE` (all **minutes** — max WithinA allowance).
  A-low is often **0**, so finishing early usually stays withinA via (1).
- **withinB**: outside A but inside B.
- **beyondB**: outside B — rare; B upper bound very high (`TIMETHRESHHOLDSBHIGHPERCENTAGE`). Often round-trip / dropoff ≠ dest where new Google duration ≈ 0.
- Path labels (not scenario): `ad_less_ed` = taximeter/actual distance < estimated distance; speed out of limit → **scaled distance** (GPS-spoofing assumption).

### Charging inputs (withinB / BeyondB)

| Condition | Distance used | Time used (conceptually) |
|-----------|---------------|--------------------------|
| AD < ED | Estimated distance | Est time + add’l time (withinB) or actual (BeyondB) |
| Speed in limit | Taximeter distance | same |
| Speed beyond limit | **Scaled distance** | same |

`ScaledDistance = ActualTime × FIXEDSPEEDCAP`  
`FIXEDSPEEDCAP` = speed used to calculate `SCALEDDISTANCE` from `ACTUALTIME` when scaled distance applies (now in `RIDE.UPFRONT`). Monitor rides with `SCALEDDISTANCE > 0` by city (rare).

### Time thresholds (units)

- `ACTUALTIME`, `APPLIEDESTIMATETIME`, `MAXWITHINMINUTESVARIANCE` → **minutes**
- `TIMETHRESHHOLDSA/B*VALUE` → **seconds**
- Percent columns are **percent points** (e.g. `22` = +22%)
- `FIXEDSPEEDCAP` → speed used with `ACTUALTIME` for scaled distance

Validated form (sample):

`TIMETHRESHHOLDSAHIGHVALUE ≈ APPLIEDESTIMATETIME * 60 * (1 + TIMETHRESHHOLDSAHIGHPERCENTAGE/100)`  
(same pattern for A low / B low / B high; A low often effectively 0)

### Additional time (withinB)

When `ACTUALTIME * 60 > TIMETHRESHHOLDSAHIGHVALUE` **and** `APPLIEDFIXEDTIMETHRESHOLDAPPLIED = FALSE`:

`ADDITIONALTIMECOMP = ACTUALTIME − APPLIEDESTIMATETIME` (both minutes)  
— validated 21/21 non-zero cases in sample (SME text had the subtraction order flipped).

Then: `ADDITIONALTIMEVALUE = ADDITIONALTIMECOMP * FACTORFORADDITIONALTIME` (100/100).

Order for withinB charging core:

`(taximeter(inputs) + ADDITIONALTIMEVALUE) × SURGE × DISC × (VAT if SA)`  
→ `CHARGINGFARE = RIDEVALUE + VATONRIDEVALUE`

Min fare is inside taximeter config (area-level). Effective fare uses:

`MAX(BaseFare × Surge, MinFare) × PD × VAT`  
`MinFare` **not** in BI yet — do **not** use `PriceChecks.MINIMUMFARE`. Use stored `VALUE` / `CHARGINGFARE`.

## Passengers.PriceChecks

| Field | Meaning (confirmed) |
|-------|---------------------|
| `BASEFARE` | Taximeter output (min fare inside formula) |
| `VALUE` | Includes SA 15% VAT when applicable; JO has **no** VAT. Conceptually `MAX(BaseFare×Surge, MinFare)×PD×VAT`; MinFare not in BI — use stored `VALUE` |
| `VAT` | **Not** SA VAT — equals `Receipts.RIDEHAILINGSURCHARGE + Receipts.VATONRIDEHAILINGSURCHARGE` (100/100 on sample) |
| `SURCHARGE` | Pre-VAT at PriceCheck. Gross for compare: `ROUND(SURCHARGE × 1.15, 2)` in SA, `× 1.0` in JO. May differ from end-of-ride surcharge when dropoff ≠ destination |
| `DISCOUNT` | Do not use for quote discount; empirically unpopulated. Reconstruct quote discount from voucher/promotion sources below |

Shown at PriceCheck: `VALUE + VAT + SURCHARGE`  
`ORIGINALESTIMATEFARE = VALUE` (both include SA VAT when applicable) — 100/100.

Join: one PriceCheck row per ride with `LOWER(SERVICEFILTER) = LOWER(REQUEST_SERVICE)`.

## Comparison (primary — Receipts only)

`Upfront.CHARGINGFARE` is **not** sufficient (excludes hailing, waiting, cancel fine, discount, etc.).

```
PC_Surcharge_Gross   = ROUND(SURCHARGE × IFF(SA, 1.15, 1.0), 2)   -- JO = ×1; hardcode (not VALUE ratio)
PriceCheck_Shown     = VALUE + VAT + PC_Surcharge_Gross
Normalized_Receipt   = Receipts.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT
Fare_Diff            = Normalized_Receipt - PriceCheck_Shown
Non_Issue            = waiting(+VAT) + cancellation_fine(+VAT)
Residual             = Fare_Diff − Non_Issue
```

Surcharge can legitimately differ PriceCheck vs Details/Receipts when **dropoff ≠ destination** (re-Google); that gap feeds `increase_pricing` / `decrease_pricing` via Fare_Diff.

## Post-discount passenger experience (added 2026-09-02)

The existing `Fare_Diff` and all current buckets remain unchanged. Add a second
view for what the passenger experienced:

```
vatf = IFF(SA, 1.15, 1.00)

Quote_Base_exVAT =
    ROUND(PriceChecks.VALUE / vatf, 2)
  + ROUND(PriceChecks.VAT / vatf, 2)
  + PriceChecks.SURCHARGE

Expected_Disc_Gross =
    Expected_Disc_exVAT
  + ROUND(Expected_Disc_exVAT * (vatf - 1), 2)

PriceCheck_Net = PriceCheck_Shown - Expected_Disc_Gross
Charged_Net    = Receipts.TOTALAMOUNTWITHTAX
Net_Fare_Diff  = Charged_Net - PriceCheck_Net
d_discount     = Expected_Disc_Gross
               - (Receipts.DISCOUNT + Receipts.VATONDISCOUNT)
```

Identity: `Net_Fare_Diff = Fare_Diff + d_discount` (tolerance 0.011).

Discount sources:

- Voucher: `PASSENGERS.PRICECHECKKAFKAWITHPROMO`, aggregated to one row per
  `TRACEID`; `MAXIMUMDISCOUNT` is VAT-inclusive.
- Promotion engine: `PASSENGERS.PROMOTIONENGINE` by `RIDEID`; infer rate and
  ex-VAT cap per `PROMOTIONID` from trailing-seven-day behaviour. Its
  `DISCOUNTAMOUNT` is final, not quote-time expected discount.
- Voucher takes precedence if both sources occur; never sum them.
- `PASSENGERS.SAVINGS` and `DETAILS.PAYMENTVOUCHERDISCOUNT` are not fare
  discount sources for this comparison.

Final discountable base:

`RIDEVALUE + RIDEHAILINGSURCHARGE + SURCHARGE + INTERCITYSURCHARGE + WAITINGTIMEFEE`

Waiting time is discountable. Cancellation fine and wallet balance are not.
Gross discount VAT must be rounded separately; do not multiply the total by
1.15. The SA hailing surcharge remains 0.50 ex-VAT + 0.08 VAT = 0.58 gross.

Six segments: `voucher_capped`, `voucher_pct_bound`, `promoeng_capped`,
`promoeng_pct_bound`, `discount_no_source`, `no_discount`.

Full formula and BI implementation:
`docs/price-shock-discounts-implementation-spec.md` and
`docs/price-shock-discounts-bi-handoff.md`.

| Condition | `issue_type` |
|-----------|----------------|
| `Fare_Diff = 0` | `matched` |
| `0 < \|Fare_Diff\| ≤ 0.01` | `rounding` |
| `Fare_Diff > 0.01` and `Residual ≤ 0.01` | `increase_non_issue` |
| `Fare_Diff > 0.01` and `Residual > 0.01` | `increase_pricing` |
| `Fare_Diff < -0.01` | `decrease_pricing` |

Surge/PD: compare PriceChecks vs Details (both non-null; do not coalesce to 0).

### Digital payment spillover (locked 2026-08-19) — do **not** ignore `OUTSTANDINGBALANCE`

On Apple Pay / Credit Card (and similar digital methods; cash exempt), if underpay remainder ≤ ~**1 SAR** (SA) / ~**0.1 JOD** (JO), no 2nd debit: amount sits in `DETAILS.OUTSTANDINGBALANCE` and is recovered on the **next** ride as `RECEIPTS.CANCELLATIONFINE`. Counting both rides as shocks double-counts the same money.

**Net shock rule:** exclude recovery legs where  
`prev_outs = LAG(OUTSTANDINGBALANCE) OVER (PARTITION BY PASSENGERID ORDER BY CREATED)`  
and `prev_outs > 0` and `ABS(prev_outs − CANCELLATIONFINE) ≤ 0.02` (ex-VAT).  
**LOOKBACK = 30 days** (load-bearing). Full write-up: `docs/payment-spillover-price-shocks.md`.

Threshold seconds: `APPLIEDESTIMATETIME_min * 60 * (1 + pct/100)`.

Daily active v1 SQL: `sql/priceshocks_daily_digest.sql`.
Post-discount v2 after BI cutover: `sql/priceshocks_daily_digest_v2.sql`.
Legacy/debug: `sql/fare_integrity_channel_summary.sql` and
`sql/daily_price_shock_alert.sql`.
Ride-level check: `tables schema/draft SQL.sql`.

## Non-issue vs pricing path

- Waiting / prior cancel fine → non-issue **on the originating ride**.
- Spillover **recovery** cancel fine on the next ride → **exclude** from Cumulative / Residual shock counts (not a new increase).
- withinA can still increase if **dropoff ≠ destination** and re-Google raises fare.
- withinB / BeyondB share increases still tracked (e.g. rising % withinB by area is concerning).

## Side notes

- Round to 2 decimals almost everywhere.
- True VAT on ride value: SA only.
- Token-efficient daily job: **aggregates only**, 29-day window.
- Broader Pricing KPI pack later; v1 = fare-integrity + scenario splits.

## Still open

None blocking digests. Optional later: MinFare column in BI; PriceCheck discounts.  
Resolved: `FIXEDSPEEDCAP` / `MAXWITHINMINUTESVARIANCE` (2026-08); spillover double-count exclusion (2026-08-19).
