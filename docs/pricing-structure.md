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
- **withinA**: actual time inside ±A of applied estimate. Lower A is usually **0**, so finishing early → withinA.
- **withinB**: outside A but inside B.
- **beyondB**: outside B — rare; B upper bound very high (`TIMETHRESHHOLDSBHIGHPERCENTAGE`). Often round-trip / dropoff ≠ dest where new Google duration ≈ 0.
- Path labels (not scenario): `ad_less_ed` = taximeter/actual distance < estimated distance; speed out of limit → **scaled distance** (GPS-spoofing assumption).

### Charging inputs (withinB / BeyondB)

| Condition | Distance used | Time used (conceptually) |
|-----------|---------------|--------------------------|
| AD < ED | Estimated distance | Est time + add’l time (withinB) or actual (BeyondB) |
| Speed in limit | Taximeter distance | same |
| Speed beyond limit | **Scaled distance** | same |

`ScaledDistance = ActualTime × FixSpeedCap`  
`FixSpeedCap` not in Snowflake yet; monitor rides with `SCALEDDISTANCE > 0` by city (rare).

### Time thresholds (units)

- `ACTUALTIME`, `APPLIEDESTIMATETIME` → **minutes**
- `TIMETHRESHHOLDSA/B*VALUE` → **seconds**
- Percent columns are **percent points** (e.g. `22` = +22%)

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
| `DISCOUNT` | Ignore for now (not populated) |

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

| Condition | `issue_type` |
|-----------|----------------|
| `Fare_Diff = 0` | `matched` |
| `0 < \|Fare_Diff\| ≤ 0.01` | `rounding` |
| `Fare_Diff > 0.01` and `Residual ≤ 0.01` | `increase_non_issue` |
| `Fare_Diff > 0.01` and `Residual > 0.01` | `increase_pricing` |
| `Fare_Diff < -0.01` | `decrease_pricing` |

Ignore `OUTSTANDINGBALANCE`. Surge/PD: compare PriceChecks vs Details.

Threshold seconds: `APPLIEDESTIMATETIME_min * 60 * (1 + pct/100)`.

Daily SQL: `sql/fare_integrity_daily_digest.sql` (aggregate). Ride-level check: `tables schema/draft SQL.sql`.

## Non-issue vs pricing path

- Waiting / prior cancellation fine → non-issue.
- withinA can still increase if **dropoff ≠ destination** and re-Google raises fare.
- withinB / BeyondB share increases still tracked (e.g. rising % withinB by area is concerning).

## Side notes

- Round to 2 decimals almost everywhere.
- True VAT on ride value: SA only.
- Token-efficient daily job: **aggregates only**, 29-day window.
- Broader Pricing KPI pack later; v1 = fare-integrity + scenario splits.

## Still open

None blocking v1 SQL. Optional later: MinFare column in BI; FixSpeedCap column; PriceCheck discounts; alert % thresholds for Slack.
