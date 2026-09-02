# Price Shock — Discount Handling: Implementation Spec

**For:** the engineer/agent updating the Jeeny daily price-shock Slack alert
**Version:** 1.0 · 2026-09-02
**Supersedes:** nothing — this is additive to `daily_price_shock_alert.sql` v2.1
**Database:** Snowflake, `JEENY_PROD`
**Scope:** SA + JO, boarded rides where upfront pricing applies

This document is self-contained. Everything needed to implement the change is here: the data model, the validated formulas, complete runnable SQL, the alert output spec, regression gates, and the baselines to check against. No prior context required.

---

## 1. What this change does, in one paragraph

The current alert measures **fare integrity**: it adds the discount back to the receipt (`TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT`) so a promo cannot masquerade as a fare decrease, then compares that to the price-check screen. That metric is correct and **must not change**. What it cannot see is that ~19.8% of Jordan rides and ~3.5% of Saudi rides carry a discount that was **already at its cap before the ride started** — for those passengers the discount cannot grow when the fare does, so they absorb 100% of any overrun. This change adds two dimensions (`discount_segment`, `cap_bound_at_quote`) and one metric (`net_fare_diff`) that make that population visible, without touching a single existing number.

**Headline impact on the existing metric: none.** Netting discounts out moves the shock rate by −0.02pp in SA and +0.08pp in JO. Do not expect the top-line to move, and treat it as a red flag if it does.

---

## 2. Required changes to the alert

| # | Change | Why |
|---|---|---|
| 1 | **Keep `fare_diff` and every existing bucket, threshold and baseline exactly as they are.** | This is the fare-integrity metric. It isolates the pricing engine. Nothing here supersedes it. |
| 2 | Add `discount_segment` (6 values) as a **new grouping dimension** on the daily output | Identifies which discount program applied and whether its cap was already binding |
| 3 | Add `cap_bound_at_quote` (0/1) as a **new flag** | The actionable population: passengers with no cushion against a fare overrun |
| 4 | Add `net_fare_diff` and `d_discount` as **new metrics reported beside** `fare_diff` | `net_fare_diff` is what the passenger experienced; `d_discount` says how much the discount absorbed |
| 5 | Add **Output 5** to the Slack post: a discount-segment block (see §8) | This is the deliverable of the change |
| 6 | Wire the **three regression gates** in §9 into the job and fail loudly | The formulas are fitted to observed behaviour; if the platform changes, every number here is stale |
| 7 | Do **not** replace `fare_diff` with `net_fare_diff` anywhere | At market level they are the same number; at segment level they are the finding. Reporting only one loses the point |

---

## 3. Data model

### 3.1 The two discount programs

Jeeny has exactly two passenger discount programs that touch the fare. Both are **percentage-with-cap**, both are shown before the ride is requested, and both **scale with the final fare until their cap binds**.

| Program | Quote-time source | Ride-level source | Grain | Join |
|---|---|---|---|---|
| **Promo voucher** — passenger types a code at the price-check screen | `PASSENGERS.PRICECHECKKAFKAWITHPROMO` | `RIDE.DETAILS.DISCOUNTRR` | one row per (`TRACEID`, `SERVICES`) | `TRACEID` → `RIDE.DETAILS.TRACEID` |
| **Promotion engine** — automatic, targeted (`PROMOTIONTYPE = 'DYNAMIC'`, `FIRSTNRIDES = 3`) | `PASSENGERS.PROMOTIONENGINE` (rate/cap must be **reconstructed**) | `RIDE.DETAILS.DISCOUNTRR` | one row per `RIDEID` | `RIDEID` |

They co-occur on **62 of 1.27M rides**, so treat them as mutually exclusive with voucher taking precedence. Do not sum them.

### 3.2 Column reference

**`PASSENGERS.PRICECHECKKAFKAWITHPROMO`** — the voucher as evaluated at the price-check screen.

| Column | Type | Notes |
|---|---|---|
| `TRACEID` | TEXT | Join key. 46 NULLs per month — filter them out. 96% of promo traces match a `PRICECHECKS` row |
| `PASSENGERID` | TEXT | |
| `AREACODE` | TEXT | Join to `GENERAL.AREAS.AREA_CODE` for country |
| `SERVICES` | TEXT | Part of the grain — this is why there are multiple rows per trace |
| `VOUCHERCODE` | TEXT | **Casing differs from `DETAILS.PAYMENTVOUCHERCODE` — `UPPER()` both** |
| `DISCOUNTTYPE` | TEXT | `PERCENTAGE` (99.9%), `FIXED_AMOUNT` (266 traces/week — negligible), or `''` when invalid |
| `DISCOUNTVALUE` | NUMBER | The percentage (10–100) for `PERCENTAGE`; an absolute amount for `FIXED_AMOUNT` |
| `MAXIMUMDISCOUNT` | FLOAT | **The cap, in local currency, VAT-INCLUSIVE.** JO 0.20–1.00 JOD, SA 2–12 SAR. A 0.20 cap is a real Jordan voucher, not a data error |
| `ISVALID` | BOOLEAN | `false` ⇒ the voucher was rejected; `DISCOUNTTYPE`/`DISCOUNTVALUE`/`MAXIMUMDISCOUNT` are then empty |
| `FAILUREREASON` | TEXT | Populated only when `ISVALID = false`. 8 distinct values |
| `ISREFERRAL` | BOOLEAN | |
| `EVENTTIMESTAMP` | TIMESTAMP_TZ | **Precedes the ride.** Widen the window a day either side of the ride `CREATEDDATE` range |

**`PASSENGERS.PROMOTIONENGINE`** — the automatic discount.

| Column | Type | Notes |
|---|---|---|
| `RIDEID` | TEXT | Join key, unique |
| `PROMOTIONID` | TEXT | 3 active configs across both markets — see §4.3 |
| `DISCOUNTAMOUNT` | NUMBER | **The FINAL applied ex-VAT discount, not the quoted one.** Written post-ride. Exact match to `DETAILS.DISCOUNTRR` on 30,173/30,173 rides — which is a tautology, not evidence of anything. **Never use it as the expected discount** (see §10, trap 1) |
| `RIDEAMOUNT` | FLOAT | **Unusable.** Zero on most SA rows; matches neither the price-check (25 of 21,357) nor the receipt (0) |
| `PROMOTIONTYPE` | TEXT | `DYNAMIC` on all rows |
| `FIRSTNRIDES` | NUMBER | `3` on all rows — this program targets new passengers |
| `AREACODE`, `SERVICE`, `RIDECREATEDAT`, `APPLIEDDATETIME`, `PROMOTIONSTARTDATE`, `PROMOTIONENDDATE`, `SEGMENTROLLINGDAYS` | | |

**`PASSENGERS.SAVINGS`** — **not a fare component.** A cashback ledger: 19,837 rows / 3,523 passengers per month, with `DISCOUNTAMOUNT`, `AMOUNTCONSUMED`, `CASHBACKDATETIME`, `EXPIRYDATETIME`. Never put it in the fare comparison. Listed here only so nobody reaches for it.

**`RIDE.DETAILS` / `RIDE.RECEIPTS`** — the applied discount. These are equivalent, verified on 1,297,124 boarded rides over 7 days with **zero** mismatches at 0.011 tolerance:

```
DETAILS.DISCOUNTRR  =  DETAILS.DISCOUNTCONSUMED  =  RECEIPTS.DISCOUNT
DETAILS.VATONDISCOUNT  =  RECEIPTS.VATONDISCOUNT
```

Pick one and stay with it. `DETAILS` avoids a join. The SQL below uses `RECEIPTS` on the fare side (to match the existing alert) and `DETAILS` for the discountable base.

### 3.3 Fields that look right and are wrong

| Field | Why not |
|---|---|
| `PASSENGERS.PRICECHECKS.DISCOUNT` | **100% NULL** — 0 non-null of 47,807,843 rows in a 7-day window. This is why the quote-time discount has to be reconstructed at all |
| `RIDE.DETAILS.PAYMENTVOUCHERDISCOUNT` | Not the fare discount. Differs from the applied discount on 50,246 of 50,342 discounted SA rides and 86,491 of 198,676 JO rides. Different program |
| `PROMOTIONENGINE.DISCOUNTAMOUNT` as expected discount | Final amount, written post-ride. Using it forces `d_discount = 0` by construction |
| `PROMOTIONENGINE.RIDEAMOUNT` | Unusable, see above |
| `PASSENGERS.SAVINGS.*` | Cashback ledger, not a fare line |

---

## 4. The validated formulas

### 4.1 Constants

```
vat_factor (vatf)  = 1.15  (SA)   ·  1.00  (JO)
SA ride-hailing surcharge = 0.50 ex-VAT  ·  0.58 GROSS      <-- hardcode 0.58
```

**The 0.58 is load-bearing.** VAT on 0.50 is 0.075, which the platform rounds **up** to 0.08. So `0.50 × 1.15 = 0.575` is wrong and `0.58` is right. `PriceChecks.VAT` already carries 0.58, so the existing `fare_diff` needs no correction — but see §10, trap 2 for where this bites.

### 4.2 Applied (charged) discount — what the receipt shows

```
Base_exVAT = RIDEVALUE + RIDEHAILINGSURCHARGE + SURCHARGE
                       + INTERCITYSURCHARGE + WAITINGTIMEFEE

voucher:       DISCOUNTRR = LEAST( ROUND(cap/vatf, 2), ROUND(dv/100  * Base_exVAT, 2) )
promo engine:  DISCOUNTRR = LEAST( cap,                ROUND(pct/100 * Base_exVAT, 2) )
both:       VATONDISCOUNT = ROUND(DISCOUNTRR * (vatf - 1), 2)
```

Validation:

| Program | Rides tested | Formula match | VAT rule match |
|---|---|---|---|
| Voucher, SA | 28,466 | **100.00%** | 100% |
| Voucher, JO | 188,438 | **99.99%** | 100% |
| Promo engine `6a78cfe0…` (SA) | 20,298 | **100.000%** | 100% |
| Promo engine `6a78d04b…` (SA) | 1,170 | **100.000%** | 100% |
| Promo engine `6a78cf50…` (JO) | 9,063 | **100.000%** | 99.99% |

**`WAITINGTIMEFEE` is in the discountable base.** Omitting it drops the SA voucher match from 100.00% to 92.99% — every one of the 1,994 mismatches had a waiting fee. **`CANCELLATIONFINE` is NOT** in the base (adding it drops SA to 95.56%), which is correct: a prior unpaid balance shouldn't be discountable. Wallet balance is not in the base either.

### 4.3 The two cap conventions differ — do not unify them

| Program | Cap convention | Worked example | Evidence |
|---|---|---|---|
| **Voucher** (`MAXIMUMDISCOUNT`) | **VAT-INCLUSIVE.** `DISCOUNTRR` tops out at `ROUND(cap/vatf, 2)`, so the **gross** discount tops out at the cap | 2.5 SAR cap → **2.17 ex-VAT + 0.33 VAT = 2.50 gross** | 100% match; the raw cap gives 35% |
| **Promotion engine** (cap **inferred** — no config column exists) | **EX-VAT.** `DISCOUNTRR` tops out at `cap`, so the gross discount tops out at `cap × vatf` | 5 SAR cap → **5.00 ex-VAT + 0.75 VAT = 5.75 gross** | 100% match; VAT-inclusive gives 43.3% / 28.5% |

Consequence: **for any configured cap `C` in SA, a voucher costs `C` gross and the promotion engine costs `C × 1.15` gross.** One of the two is not doing what whoever configured it intended. Verification SQL and nine named rides are in `verify_discount_cap_convention.sql`; a summary is in §11.

In JO (`vatf = 1.00`) the two conventions are indistinguishable, so this only matters for SA.

### 4.4 Reconstructing the promotion-engine rate and cap

No cap or rate column exists in `PASSENGERS.PROMOTIONENGINE`. Derive both per `PROMOTIONID` from observed behaviour — **derive, do not hardcode**, so a new promotion is picked up automatically:

```
cap  = MAX(DISCOUNTRR) over that PROMOTIONID
pct  = the implied rate read off rides STRICTLY BELOW that cap,
       where DISCOUNTRR / Base_exVAT is exactly the configured rate
```

Observed 2026-08-24..30, and the reason to trust the inference — capped rides pile up on exactly one value while the fare base ranges over 2.7×:

| Country | `PROMOTIONID` | Config | Rides | % at cap |
|---|---|---|---|---|
| SA | `6a78cfe05319cb4e3d82f5b0` | 30% up to 5 SAR | 20,298 | 46.6% |
| SA | `6a78d04b5319cb4e3d82f5b1` | 50% up to 5 SAR | 1,170 | 56.7% |
| JO | `6a78cf508146664ee427436a` | 30% up to 1 JOD | 9,063 | 31.6% |

**This is an inference, not a config read.** Engineering should confirm the configured values before anyone changes a config on the strength of it.

### 4.5 Expected (quoted) discount and the new metrics

```
-- LOCKED, UNCHANGED. pc.VAT already carries the 0.58 gross surcharge in SA.
PC_Surcharge_Gross = ROUND(PriceChecks.SURCHARGE * IFF(SA, 1.15, 1.0), 2)
PriceCheck_Shown   = PriceChecks.VALUE + PriceChecks.VAT + PC_Surcharge_Gross
Normalized_Receipt = Receipts.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT
Fare_Diff          = Normalized_Receipt - PriceCheck_Shown

-- NEW. Build the quote base COMPONENT-WISE. Never PriceCheck_Shown / 1.15.
Quote_Base_exVAT = ROUND(PriceChecks.VALUE / vatf, 2)
                 + ROUND(PriceChecks.VAT   / vatf, 2)      -- 0.58 -> 0.50 exactly
                 + PriceChecks.SURCHARGE                   -- already ex-VAT, do NOT divide

-- Both programs scale with the base, so both are evaluated on the QUOTED base.
Expected_Disc_exVAT = voucher   ? LEAST(ROUND(cap/vatf,2), ROUND(dv%  * Quote_Base_exVAT, 2))
                    : promo_eng ? LEAST(cap,               ROUND(pct% * Quote_Base_exVAT, 2))
                    : 0

Expected_Disc_gross = Expected_Disc_exVAT + ROUND(Expected_Disc_exVAT * (vatf-1), 2)

Cap_Bound_At_Quote  = the percentage leg already met the cap on the QUOTED base

PriceCheck_Net = PriceCheck_Shown - Expected_Disc_gross
Charged_Net    = Receipts.TOTALAMOUNTWITHTAX          -- already net of discount
Net_Fare_Diff  = Charged_Net - PriceCheck_Net
d_discount     = Expected_Disc_gross - Actual_Disc_gross
```

**Identity — assert this in the job:**

```
Net_Fare_Diff = Fare_Diff + d_discount
```

Holds on **1,268,177 of 1,268,184 rides (99.9995%)** at 0.011 tolerance.

`d_discount` is self-documenting:

| Value | Meaning |
|---|---|
| `< 0` | The discount **grew** with the fare — the passenger was partly shielded |
| `= 0` | The discount was **capped** — zero protection, the passenger absorbed the whole overrun |
| `> 0` | The discount came out **smaller** than quoted — investigate |

It also drops into the existing residual decomposition as a fourth term, changing nothing that is already there:

```
Fare_Diff     = d_ridevalue + d_hailing + d_surcharge + Non_Issue                (existing)
Net_Fare_Diff = d_ridevalue + d_hailing + d_surcharge + Non_Issue + d_discount
```

---

## 5. `discount_segment` — the new dimension

Six mutually exclusive values, evaluated in this order:

| Value | Test | Meaning |
|---|---|---|
| `voucher_capped` | valid voucher AND `cap_bound_at_quote` | Voucher discount already at its ceiling at quote. **Zero shock buffer** |
| `voucher_pct_bound` | valid voucher | Voucher discount below its cap — scales with the fare, absorbs `dv%` of any overrun |
| `promoeng_capped` | promotion engine AND `cap_bound_at_quote` | Engine discount already at its ceiling. **Zero shock buffer** |
| `promoeng_pct_bound` | promotion engine | Engine discount below its cap — absorbs `pct%` of any overrun |
| `discount_no_source` | discount on the receipt, neither source found | 92 SA / 251 JO rides per week. Immaterial; keep it so it can't hide |
| `no_discount` | else | 93.0% of SA rides, 64.6% of JO rides |

---

## 6. Complete production SQL

Reference implementation: `discount_aware_price_shock.sql` v3.0 (in the Price Shock project). It is written as one statement per output because the Snowflake MCP connector submits a single statement per call; adapt to your runner. Structure:

```
params        -- window + spillover lookback (30 days — do NOT shrink)
lookback      -- every ride in the lookback window, for the LAG
prev          -- LAG(OUTSTANDINGBALANCE) per passenger, for spillover detection
pe_raw        -- promotion-engine rides with their applied discount and ride base
pe_max        -- cap per PROMOTIONID = MAX(applied discount)
pe_cfg        -- rate per PROMOTIONID, read off below-cap rides  (§4.4)
promo         -- quote-time voucher, aggregated to ONE ROW PER TRACEID
base          -- the ride universe with all inputs
calc          -- fare_diff, exp_disc_exvat, cap_bound_at_quote
grossed       -- exp_disc_gross (round the VAT, never multiply the total)
final         -- net_fare_diff, d_discount, discount_segment, promised_not_applied
```

### 6.1 Universe (unchanged from the existing alert)

```sql
FROM JEENY_PROD.RIDE.DETAILS   rd
JOIN JEENY_PROD.RIDE.UPFRONT   uf ON rd.RIDEID = uf.RIDEID
JOIN JEENY_PROD.RIDE.RECEIPTS  rr ON rd.RIDEID = rr.RIDEID
JOIN JEENY_PROD.GENERAL.AREAS  ga ON rd.AREA_CODE = ga.AREA_CODE
JOIN JEENY_PROD.PASSENGERS.PRICECHECKS pc
  ON pc.RIDEID = rd.RIDEID
 AND LOWER(pc.SERVICEFILTER) = LOWER(rd.REQUEST_SERVICE)
WHERE rd.BOARDED IS NOT NULL
  AND uf.ORIGINALESTIMATEFARE IS NOT NULL
  AND ga.COUNTRY_CODE IN ('SA','JO')
  AND rd.CREATEDDATE BETWEEN :d_from AND :d_to
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY rd.RIDEID
    ORDER BY pc.ACTUALDATETIME DESC NULLS LAST) = 1
```

`CREATEDDATE` is already a Saudi calendar date — do not re-timezone.

### 6.2 The two new CTEs

```sql
/* promotion-engine config, DERIVED per PROMOTIONID */
pe_raw AS (
    SELECT pe.PROMOTIONID,
           COALESCE(rd.DISCOUNTRR,0) AS disc,
           COALESCE(rd.RIDEVALUE,0) + COALESCE(rd.RIDEHAILINGSURCHARGE,0)
             + COALESCE(rd.SURCHARGE,0) + COALESCE(rd.INTERCITYSURCHARGE,0)
             + COALESCE(rd.WAITINGTIMEFEE,0) AS ride_base
    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.GENERAL.AREAS ga ON ga.AREA_CODE = rd.AREA_CODE
    JOIN JEENY_PROD.PASSENGERS.PROMOTIONENGINE pe ON pe.RIDEID = rd.RIDEID
    CROSS JOIN params p
    WHERE rd.BOARDED IS NOT NULL
      AND ga.COUNTRY_CODE IN ('SA','JO')
      AND rd.CREATEDDATE BETWEEN p.d_from AND p.d_to
      AND COALESCE(rd.DISCOUNTRR,0) > 0.001
),
pe_max AS (SELECT PROMOTIONID, MAX(disc) AS cap_exvat FROM pe_raw GROUP BY 1),
pe_cfg AS (
    SELECT m.PROMOTIONID,
           m.cap_exvat,
           ROUND(MEDIAN(r.disc / NULLIF(r.ride_base,0)) * 100, 0) AS pct,
           COUNT(*)                                              AS n_uncapped
    FROM pe_max m
    JOIN pe_raw r ON r.PROMOTIONID = m.PROMOTIONID
    WHERE r.disc < m.cap_exvat - 0.011 AND r.ride_base > 0
    GROUP BY 1, 2
),

/* quote-time voucher, ONE ROW PER TRACEID — aggregate or the join fans out */
promo AS (
    SELECT
        pk.TRACEID,
        MAX(IFF(pk.ISVALID, 1, 0))                            AS voucher_valid,
        MAX(IFF(pk.ISVALID, pk.DISCOUNTVALUE,   NULL))        AS dv,
        MAX(IFF(pk.ISVALID, pk.MAXIMUMDISCOUNT, NULL))        AS cap,
        MAX(IFF(pk.ISVALID, pk.DISCOUNTTYPE,    NULL))        AS dtype,
        MAX(IFF(pk.ISVALID, UPPER(pk.VOUCHERCODE), NULL))     AS voucher_code,
        COUNT(DISTINCT IFF(pk.ISVALID, pk.VOUCHERCODE, NULL)) AS n_codes,
        MAX(IFF(NOT pk.ISVALID, NULLIF(pk.FAILUREREASON,''), NULL)) AS failure_reason
    FROM JEENY_PROD.PASSENGERS.PRICECHECKKAFKAWITHPROMO pk
    CROSS JOIN params p
    WHERE pk.TRACEID IS NOT NULL
      AND pk.EVENTTIMESTAMP >= DATEADD('day', -1, p.d_from)
      AND pk.EVENTTIMESTAMP <  DATEADD('day',  2, p.d_to)
    GROUP BY pk.TRACEID
)
```

### 6.3 Quote base, expected discount, cap flag

```sql
/* in base: quote-side DISCOUNTABLE base, ex-VAT.
   COMPONENT-WISE on purpose — see §10 trap 2 */
ROUND(COALESCE(pc.VALUE,0) / IFF(ga.COUNTRY_CODE='SA',1.15,1.0), 2)
  + ROUND(COALESCE(pc.VAT,0) / IFF(ga.COUNTRY_CODE='SA',1.15,1.0), 2)
  + COALESCE(pc.SURCHARGE,0)                             AS quote_base_exvat,

/* in calc: expected discount at quote, ex-VAT.
   Cap conventions differ and must not be unified — see §4.3 */
CASE
    WHEN voucher_valid = 1 AND n_codes = 1 AND dtype = 'PERCENTAGE'
        THEN ROUND(LEAST(ROUND(cap/vatf, 2),
                         ROUND(dv/100.0 * quote_base_exvat, 2)), 2)
    WHEN voucher_valid = 1 AND n_codes = 1 AND dtype = 'FIXED_AMOUNT'
        THEN ROUND(LEAST(ROUND(dv/vatf, 2), quote_base_exvat), 2)
    WHEN has_promo_engine = 1 AND pe_pct IS NOT NULL
        THEN ROUND(LEAST(pe_cap_exvat,
                         ROUND(pe_pct/100.0 * quote_base_exvat, 2)), 2)
    ELSE 0
END                                                      AS exp_disc_exvat,

CASE
    WHEN voucher_valid = 1 AND n_codes = 1 AND dtype = 'PERCENTAGE'
        THEN IFF(ROUND(dv/100.0 * quote_base_exvat, 2)
                 >= ROUND(cap/vatf, 2) - 0.005, 1, 0)
    WHEN has_promo_engine = 1 AND pe_pct IS NOT NULL
        THEN IFF(ROUND(pe_pct/100.0 * quote_base_exvat, 2)
                 >= pe_cap_exvat - 0.005, 1, 0)
    ELSE 0
END                                                      AS cap_bound_at_quote

/* in grossed: gross up by rounding the VAT, NEVER by multiplying the total */
ROUND(exp_disc_exvat + ROUND(exp_disc_exvat * (vatf - 1), 2), 2) AS exp_disc_gross
```

### 6.4 Final metrics and segment

```sql
ROUND(pc_shown - exp_disc_gross, 2)                      AS pc_net,
ROUND(charged_net - (pc_shown - exp_disc_gross), 2)      AS net_fare_diff,
ROUND(exp_disc_gross - act_disc_gross, 2)                AS d_discount,
CASE
    WHEN voucher_valid = 1 AND cap_bound_at_quote = 1     THEN 'voucher_capped'
    WHEN voucher_valid = 1                                THEN 'voucher_pct_bound'
    WHEN has_promo_engine = 1 AND cap_bound_at_quote = 1  THEN 'promoeng_capped'
    WHEN has_promo_engine = 1                             THEN 'promoeng_pct_bound'
    WHEN act_disc_gross > 0.01                            THEN 'discount_no_source'
    ELSE                                                       'no_discount'
END                                                      AS discount_segment,
IFF(voucher_valid = 1 AND act_disc_gross <= 0.01, 1, 0)  AS promised_not_applied
```

---

## 7. Baselines to validate against

All figures: rides created **2026-08-24 → 2026-08-30** (7 complete days), spillover-recovery excluded.

### 7.1 Headline

| Market | Rides | Shock gross | Shock net | Excess gross | Excess net |
|---|---|---|---|---|---|
| SA | 721,201 | 248,939 (**34.52%**) | 248,805 (**34.50%**) | 1,086,412 SAR | 1,081,739 SAR |
| JO | 546,983 | 122,741 (**22.44%**) | 123,159 (**22.52%**) | 74,038 JOD | 73,628 JOD |

SA gross 34.52% reconciles with the `daily_price_shock_alert.sql` v2.1 baseline of 34.46%. **If your gross number moves materially from the existing alert, you have broken something — stop and check the join fan-out before looking at anything else.**

### 7.2 By segment

| Market | Segment | Rides | % of rides | Shock gross | Shock net | Avg gross | Avg net | Excess gross | Excess net | Avg `d_discount` |
|---|---|---|---|---|---|---|---|---|---|---|
| SA | `no_discount` | 670,893 | 93.0% | 34.45% | 34.45% | 4.33 | 4.33 | 1,001,791 | 1,001,791 | 0 |
| SA | `voucher_capped` | 16,081 | 2.2% | 36.33% | 36.57% | 4.71 | 4.73 | 27,544 | 27,790 | +0.019 |
| SA | `voucher_pct_bound` | 12,803 | 1.8% | 30.84% | 29.99% | 3.77 | 3.32 | 14,877 | 12,757 | −0.732 |
| SA | `promoeng_pct_bound` | 12,001 | 1.7% | 36.40% | 36.03% | 4.61 | 4.03 | 20,154 | 17,444 | −0.620 |
| SA | `promoeng_capped` | 9,331 | 1.3% | **39.00%** | **39.04%** | 6.02 | 6.02 | 21,916 | 21,923 | +0.001 |
| JO | `no_discount` | 353,209 | 64.6% | 23.98% | 23.98% | 0.63 | 0.63 | 53,568 | 53,568 | 0 |
| JO | `voucher_capped` | 105,394 | **19.3%** | 20.64% | 20.98% | 0.56 | 0.55 | 12,077 | 12,189 | +0.001 |
| JO | `voucher_pct_bound` | 79,352 | 14.5% | 17.42% | 17.59% | 0.48 | 0.45 | 6,666 | 6,341 | −0.033 |
| JO | `promoeng_pct_bound` | 6,122 | 1.1% | 26.46% | 25.68% | 0.71 | 0.61 | 1,143 | 954 | −0.116 |
| JO | `promoeng_capped` | 2,655 | 0.5% | **29.57%** | **29.57%** | 0.71 | 0.71 | 561 | 561 | 0 |

Two invariants worth asserting in the job:

1. **All four `*_capped` segments must have `avg d_discount` ≈ 0 and `shock_net >= shock_gross`.** If a capped segment shows meaningful absorption, `cap_bound_at_quote` is misfiring.
2. **All four `*_pct_bound` segments must have negative `avg d_discount`.** That is the discount growing with the fare. A positive value means the expected discount is being computed on the wrong base.

### 7.3 Discount penetration

| Market | Rides | Discounted | Share | Avg discount |
|---|---|---|---|---|
| SA | 724,168 | 50,342 | 7.0% | 4.05 SAR |
| JO | 572,857 | 198,676 | **34.7%** | 0.249 JOD |

SA discounted rides split ~43% promotion-engine / ~57% voucher; JO is ~95% voucher. **Discounts are a Jordan story first.**

### 7.4 Cap-bound population — the actionable number

| Market | `voucher_capped` | `promoeng_capped` | Total | % of all rides |
|---|---|---|---|---|
| SA | 16,081 | 9,331 | **25,412** | **3.5%** |
| JO | 105,394 | 2,655 | **108,049** | **19.8%** |

---

## 8. Slack output spec

Keep Outputs 1–3 of the existing alert exactly as they are. Add one block.

### Output 5 — discount exposure (new)

Post per market, in the market's own currency. **Never sum SAR with JOD.**

```
DISCOUNT EXPOSURE — {country} — {report_date}

No shock buffer (discount capped before the ride started)
  {cap_bound_shock_rides} shock rides of {cap_bound_rides} capped rides ({pct}%)
  {cap_bound_excess} {ccy} absorbed entirely by passengers
  vs {no_discount_pct}% shock rate on undiscounted rides

Partially shielded (discount grew with the fare)
  {pct_bound_shock_rides} shock rides
  {pct_bound_excess_gross} -> {pct_bound_excess_net} {ccy}  ({pct}% absorbed)

Worst segment: {segment}  {pct}% shock  ·  avg {avg} {ccy}
```

Alert-worthy movements, day over day:

| Signal | Why it matters |
|---|---|
| `cap_bound_rides` share rising | More passengers with no cushion — a campaign-config change, not a pricing change |
| A `*_capped` segment's shock rate rising faster than `no_discount` | The exposed population is getting more exposed |
| `avg d_discount` on a `*_pct_bound` segment moving toward 0 | Absorption is being lost — check whether a cap was lowered |
| `promised_not_applied` rising above ~200/day combined | The voucher→request funnel is leaking |
| A new `PROMOTIONID` appearing in `pe_cfg` with low `n_uncapped` | A new promotion whose rate cannot yet be read — see §9 gate 3 |

Do **not** put `net_fare_diff` in the headline Slack line. It is the same number as `fare_diff` at market level and will only confuse the reader. It belongs in Output 5, per segment.

---

## 9. Regression gates — wire these in and fail loudly

The formulas in §4 are fitted to observed platform behaviour, not read from config. If the platform changes, every number in §7 becomes stale silently. Run all three daily.

### Gate 1 — applied-discount formula

Expect `pct_match >= 99.9` on every row, `pct_vat_rule_match >= 99.9`.

```sql
-- vouchers (cap VAT-INCLUSIVE)
WITH v AS (
    SELECT ga.COUNTRY_CODE AS cc,
           IFF(ga.COUNTRY_CODE='SA',1.15,1.00) AS vatf,
           COALESCE(rd.DISCOUNTRR,0)    AS disc,
           COALESCE(rd.VATONDISCOUNT,0) AS vdisc,
           COALESCE(rd.RIDEVALUE,0) + COALESCE(rd.RIDEHAILINGSURCHARGE,0)
             + COALESCE(rd.SURCHARGE,0) + COALESCE(rd.INTERCITYSURCHARGE,0)
             + COALESCE(rd.WAITINGTIMEFEE,0) AS base_exvat,
           pk.dv, pk.cap
    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.GENERAL.AREAS ga ON ga.AREA_CODE = rd.AREA_CODE
    LEFT JOIN JEENY_PROD.PASSENGERS.PROMOTIONENGINE pe ON pe.RIDEID = rd.RIDEID
    JOIN (
        SELECT TRACEID, MAX(DISCOUNTVALUE) dv, MAX(MAXIMUMDISCOUNT) cap
        FROM JEENY_PROD.PASSENGERS.PRICECHECKKAFKAWITHPROMO
        WHERE EVENTTIMESTAMP >= DATEADD('day',-2,:report_date)
          AND EVENTTIMESTAMP <  DATEADD('day', 2,:report_date)
          AND TRACEID IS NOT NULL AND ISVALID AND DISCOUNTTYPE = 'PERCENTAGE'
        GROUP BY TRACEID
        HAVING COUNT(DISTINCT VOUCHERCODE) = 1 AND COUNT(DISTINCT DISCOUNTVALUE) = 1
    ) pk ON pk.TRACEID = rd.TRACEID
    WHERE rd.CREATEDDATE = :report_date
      AND rd.BOARDED IS NOT NULL AND ga.COUNTRY_CODE IN ('SA','JO')
      AND COALESCE(rd.DISCOUNTRR,0) > 0.001
      AND pe.RIDEID IS NULL
)
SELECT 'voucher' AS program, cc, COUNT(*) AS n,
       ROUND(100.0*SUM(IFF(ABS(disc - ROUND(LEAST(ROUND(cap/vatf,2),
                               ROUND(dv/100.0*base_exvat,2)),2))<=0.011,1,0))/COUNT(*),3) AS pct_match,
       ROUND(100.0*SUM(IFF(ABS(vdisc - ROUND(disc*(vatf-1),2))<=0.011,1,0))/COUNT(*),2)   AS pct_vat_rule_match,
       NULL AS n_uncapped
FROM v GROUP BY cc;
```

```sql
-- promotion engine (cap EX-VAT), with the derived config
WITH r AS (
    SELECT pe.PROMOTIONID, ga.COUNTRY_CODE AS cc,
           IFF(ga.COUNTRY_CODE='SA',1.15,1.00) AS vatf,
           COALESCE(rd.DISCOUNTRR,0)    AS disc,
           COALESCE(rd.VATONDISCOUNT,0) AS vdisc,
           COALESCE(rd.RIDEVALUE,0) + COALESCE(rd.RIDEHAILINGSURCHARGE,0)
             + COALESCE(rd.SURCHARGE,0) + COALESCE(rd.INTERCITYSURCHARGE,0)
             + COALESCE(rd.WAITINGTIMEFEE,0) AS ride_base
    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.GENERAL.AREAS ga ON ga.AREA_CODE = rd.AREA_CODE
    JOIN JEENY_PROD.PASSENGERS.PROMOTIONENGINE pe ON pe.RIDEID = rd.RIDEID
    WHERE rd.CREATEDDATE BETWEEN DATEADD('day',-6,:report_date) AND :report_date
      AND rd.BOARDED IS NOT NULL AND ga.COUNTRY_CODE IN ('SA','JO')
      AND COALESCE(rd.DISCOUNTRR,0) > 0.001
),
m AS (SELECT PROMOTIONID, MAX(disc) AS cap_exvat FROM r GROUP BY 1),
cfg AS (
    SELECT m.PROMOTIONID, m.cap_exvat,
           ROUND(MEDIAN(r.disc/NULLIF(r.ride_base,0))*100, 0) AS pct,
           COUNT(*) AS n_uncapped
    FROM m JOIN r ON r.PROMOTIONID = m.PROMOTIONID
    WHERE r.disc < m.cap_exvat - 0.011 AND r.ride_base > 0
    GROUP BY 1, 2
)
SELECT 'promo_engine:' || r.PROMOTIONID AS program, r.cc, COUNT(*) AS n,
       ROUND(100.0*SUM(IFF(ABS(r.disc - ROUND(LEAST(cfg.cap_exvat,
                               ROUND(cfg.pct/100.0*r.ride_base,2)),2))<=0.011,1,0))/COUNT(*),3) AS pct_match,
       ROUND(100.0*SUM(IFF(ABS(r.vdisc - ROUND(r.disc*(r.vatf-1),2))<=0.011,1,0))/COUNT(*),2)   AS pct_vat_rule_match,
       MAX(cfg.n_uncapped) AS n_uncapped
FROM r JOIN cfg ON cfg.PROMOTIONID = r.PROMOTIONID
GROUP BY 1, 2 ORDER BY n DESC;
```

**Note the window difference:** the promotion-engine gate uses a 7-day window because `pe_cfg` needs enough below-cap rides to read the rate; a single day of a small promotion may not have any.

### Gate 2 — the identity

Expect `identity_holds / n >= 0.9999`.

```sql
SELECT country,
       COUNT(*) AS n,
       SUM(IFF(ABS(net_fare_diff - (fare_diff + d_discount)) <= 0.011, 1, 0)) AS identity_holds
FROM final
GROUP BY country;
```

### Gate 3 — promotion-engine config coverage

Expect every `PROMOTIONID` seen in the day's rides to appear in `pe_cfg` with `n_uncapped >= 50`. A new promotion whose rides are all capped yields a **NULL `pct`**, which silently falls through to `exp_disc = 0` and makes those rides look like `no_discount`.

```sql
SELECT pe.PROMOTIONID,
       COUNT(*)                                  AS rides_today,
       MAX(IFF(cfg.PROMOTIONID IS NULL, 1, 0))   AS missing_from_cfg,
       MAX(cfg.pct)                              AS derived_pct,
       MAX(cfg.cap_exvat)                        AS derived_cap,
       MAX(cfg.n_uncapped)                       AS n_uncapped
FROM JEENY_PROD.PASSENGERS.PROMOTIONENGINE pe
JOIN JEENY_PROD.RIDE.DETAILS rd ON rd.RIDEID = pe.RIDEID
LEFT JOIN pe_cfg cfg ON cfg.PROMOTIONID = pe.PROMOTIONID
WHERE rd.CREATEDDATE = :report_date AND rd.BOARDED IS NOT NULL
GROUP BY 1
HAVING missing_from_cfg = 1 OR COALESCE(MAX(cfg.n_uncapped),0) < 50;
```

Any row returned is an alert: a promotion is running whose rate we cannot read.

---

## 10. Traps — every one of these was hit during the analysis

**Trap 1 — `PROMOTIONENGINE.DISCOUNTAMOUNT` is the final amount, not the quoted one.**
The table is written post-ride. `DISCOUNTAMOUNT` matches `DETAILS.DISCOUNTRR` on 30,173/30,173 rides — which proves only that both record the same final number. Using it as the expected discount forces `d_discount = 0` by construction and makes the promotion-engine segments look like they have no gross-vs-net gap at all. Reconstruct rate and cap and evaluate on the **quoted** base.

**Trap 2 — never derive the quote-side ex-VAT base as `PriceCheck_Shown / 1.15`.**
The SA ride-hailing surcharge is 0.58 gross / 0.50 ex-VAT, because VAT on 0.50 is 0.075 and the platform rounds **up** to 0.08. Dividing 0.58 by 1.15 gives 0.5043, leaking 0.005 per ride into the expected discount. Build the base component-wise; `ROUND(0.58/1.15, 2)` recovers 0.50 exactly.

**Trap 3 — gross up by rounding the VAT, not by multiplying the total.**
`disc + ROUND(disc × 0.15, 2)` matches the platform on 100% of rides. `disc × 1.15` drifts.

**Trap 4 — the two cap conventions are not interchangeable.**
Voucher VAT-inclusive, promotion engine ex-VAT. Swapping them drops the match to 35% and 43.3% / 28.5%.

**Trap 5 — `PRICECHECKKAFKAWITHPROMO` grain is `(TRACEID, SERVICES)`.**
Several rows per price-check — 5.03M rows against 2.47M traces in a month. Aggregate to `TRACEID` before joining or the join fans out and every count inflates.

**Trap 6 — `EVENTTIMESTAMP` precedes the ride and is `TIMESTAMP_TZ`.**
Widen the promo window by a day either side of the ride `CREATEDDATE` range or you will drop legitimate vouchers at the window edge.

**Trap 7 — multi-code traces.**
316 SA / 783 JO traces per 7-day window carry more than one distinct voucher code. Require `n_codes = 1` before trusting `dv` / `cap`.

**Trap 8 — voucher code casing.**
`VOUCHERCODE` casing differs from `DETAILS.PAYMENTVOUCHERCODE`. `UPPER()` both. When they do match they match well — 28,291 of 28,491 SA and 186,173 of 188,441 JO — so the voucher shown at quote *is* the voucher applied.

**Trap 9 — `MAXIMUMDISCOUNT` is local currency.**
JO caps 0.20–1.00 JOD, SA 2–12 SAR. A 0.20 cap is a real Jordan voucher, not a data error. Do not "fix" it.

**Trap 10 — report value, not counts, for the `*_pct_bound` segments.**
Ride counts tick *up* slightly on the net metric while value falls, because some rides cross the 0.01 threshold. The absorption is real and shows in the money.

**Trap 11 — `CREATEDDATE` is already a Saudi calendar date.** Do not re-timezone. And never SUM SAR with JOD.

**Trap 12 — the 30-day spillover lookback is load-bearing.** Only ~60% of spillover recovery lands within 24h, ~90% within 7d, 99% within 30d. Shrinking the lookback silently reintroduces a 12.7% double count. This is inherited from v2.1 and unchanged.

---

## 11. Supporting finding: the two cap conventions

Full verification SQL: `verify_discount_cap_convention.sql`. Summary of the evidence:

**Nine named rides** (2026-08-27/28, SA), showing what each convention predicts against what was actually charged:

| `RIDEID` | Program | Config | Cap | `DISCOUNTRR` | `VATONDISCOUNT` | Gross | Predicted if cap VAT-incl | Predicted if cap ex-VAT |
|---|---|---|---|---|---|---|---|---|
| `6a8f543092ec7fcfd9c6e85f` | voucher `be9` | 20% up to 2.5 | 2.5 | **2.17** | 0.33 | 2.50 | **2.17 ✓** | 2.50 ✗ |
| `6a8f547841ab4856a55a5702` | voucher `be6` | 20% up to 2.5 | 2.5 | **2.17** | 0.33 | 2.50 | **2.17 ✓** | 2.50 ✗ |
| `6a8f54ef92ec7fcfd9c761b5` | voucher `bfb` | 50% up to 6 | 6 | **5.22** | 0.78 | 6.00 | **5.22 ✓** | 6.00 ✗ |
| `6a8f559192ec7fcfd9c7c2c0` | voucher `bfb` | 50% up to 6 | 6 | **5.22** | 0.78 | 6.00 | **5.22 ✓** | 6.00 ✗ |
| `6a8f540c41ab4856a55a1e16` | voucher `bbw` | 35% up to 7 | 7 | **6.09** | 0.91 | 7.00 | **6.09 ✓** | 7.00 ✗ |
| `6a8f549992ec7fcfd9c73111` | voucher `bbw` | 35% up to 7 | 7 | **6.09** | 0.91 | 7.00 | **6.09 ✓** | 7.00 ✗ |
| `6a8f53ed41ab4856a55a0e3c` | promo engine | 30% up to 5 | 5 | **5.00** | 0.75 | 5.75 | 4.35 ✗ | **5.00 ✓** |
| `6a8f541092ec7fcfd9c6d7b8` | promo engine | 30% up to 5 | 5 | **5.00** | 0.75 | 5.75 | 4.35 ✗ | **5.00 ✓** |
| `6a8f543192ec7fcfd9c6e93a` | promo engine | 30% up to 5 | 5 | **5.00** | 0.75 | 5.75 | 4.35 ✗ | **5.00 ✓** |

The three promotion-engine rides have `base_exvat` of 18.01 / 19.98 / **48.66** — a 2.7× range of fare, with the discount flat at 5.00. That is what "capped" means, and the cap is 5.00, not 4.35.

**At population scale, vouchers** (2026-08-24..30, SA, cap-bound rides only): for every cap value, the ex-VAT discount lands on `ROUND(cap/1.15, 2)` and the **gross** discount lands on the cap. The count at the raw cap is **zero for every cap**:

| Cap | `dv` | Rides | Median `DISCOUNTRR` | Median VAT | Median gross | At `cap/1.15` | At raw `cap` |
|---|---|---|---|---|---|---|---|
| 2.5 | 20% | 9,066 | 2.17 | 0.33 | **2.50** | 9,066 | **0** |
| 6 | 50% | 2,899 | 5.22 | 0.78 | **6.00** | 2,899 | **0** |
| 8 | 40% | 1,848 | 6.96 | 1.04 | **8.00** | 1,848 | **0** |
| 7 | 35% | 1,340 | 6.09 | 0.91 | **7.00** | 1,340 | **0** |
| 2 | 15% | 861 | 1.74 | 0.26 | **2.00** | 861 | **0** |
| 9 | 45% | 180 | 7.83 | 1.17 | **9.00** | 180 | **0** |

**At population scale, promotion engine** (same window, cap-bound rides only):

| Country | `PROMOTIONID` | Inferred cap | Rides | Median `DISCOUNTRR` | Median VAT | Median gross | Gross at cap |
|---|---|---|---|---|---|---|---|
| SA | `6a78cfe05319cb4e3d82f5b0` | 5 | 9,456 | **5.00** | 0.75 | **5.75** | **0** |
| SA | `6a78d04b5319cb4e3d82f5b1` | 5 | 663 | **5.00** | 0.75 | **5.75** | **0** |
| JO | `6a78cf508146664ee427436a` | 1 | 2,867 | 1.00 | 0.00 | 1.00 | 2,867 |

(The JO row shows gross at cap only because JO has no VAT — the two conventions are indistinguishable there.)

**Two caveats to state when raising this:**

1. No live SA voucher currently uses a cap of exactly 5 SAR, so this is not two live configs at the same number. It is a difference in how each program **interprets** whatever number is configured. For any configured cap `C` in SA: voucher pays `C` gross, engine pays `C × 1.15` gross.
2. The promotion-engine cap is **inferred** from `MAX(DISCOUNTRR)`, because no cap column exists. The inference is sound — 10,119 rides pile up on exactly 5.00 across a wide fare range — but it is an inference. Engineering should confirm the configured value before anyone changes a config on the strength of it.

---

## 12. Findings worth their own tickets (out of scope for this change)

**A. Jordan voucher caps bind before the ride starts — 19.3% of all JO rides.**
Caps of 0.20–1.00 JOD are exceeded almost immediately, so the voucher provides no protection against a fare overrun. Product option: surface the capped amount at quote ("you'll save 0.20 JOD") rather than the percentage ("10% off"), so the expectation is set on the number the passenger will actually see.

**B. `promoeng_capped` in SA is the worst segment on the platform.**
39.00% shock rate on a 6.02 SAR average overrun, against 34.45% / 4.33 SAR for undiscounted rides. The promotion engine targets `FIRSTNRIDES = 3`, so the platform's newest passengers carry the highest overruns with a discount that cannot move. This pattern holds in every pairing — the capped half always shocks more than the uncapped half:

| Pairing | Capped | Percentage-bound |
|---|---|---|
| SA voucher | 36.33% | 30.84% |
| SA promotion engine | 39.00% | 36.40% |
| JO voucher | 20.64% | 17.42% |
| JO promotion engine | 29.57% | 26.46% |

Larger fares both hit the cap and overrun more, so the passengers with no cushion are also the most exposed.

**C. 26% of voucher entries fail at the price-check screen, four fifths unexplained.**
131,546 traces in 7 days carried a voucher that failed, against ~373,000 that succeeded:

| Failure reason | Traces |
|---|---|
| `VOUCHER_INVALID` (no reason given) | 108,652 |
| Voucher does not exist | 19,046 |
| Promotion is not available for this user | 7,049 |
| `PAYMENT_METHOD_NOT_ALLOWED_FOR_PROMOTION` | 1,450 |
| Promotional code has expired | 357 |
| `CREDIT_CARD_BIN_NOT_MATCHED` | 121 |
| `CREDIT_CARD_TYPE_NOT_USED_BY_CUSTOMER` | 83 |
| Promotion is invalid for this service | 13 |

**D. Voucher validated at price-check but never attached to the ride.**
SA 126 rides / JO 1,058 rides per week; a valid voucher was returned at the screen and the receipt shows no discount. Almost all (125/126 and 1,057/1,058) have **no `PAYMENTVOUCHERCODE`** on the ride, so this is a funnel drop between price-check and request, not a pricing defect. ~470 SAR + ~220 JOD per week. A UX ticket, not a price-shock bucket.

**E. `PRICECHECKS.DISCOUNT` should be populated.**
The entire quote-side metric is a reconstruction. The applied side reconciles at 100%, but we have no record of what was actually *rendered on screen*. Populating this field would turn an inference into a measurement.

---

## 13. Reference files

| File | Contents |
|---|---|
| `discount_aware_price_shock.sql` v3.0 | Full runnable implementation, 5 outputs, inline provenance |
| `verify_discount_cap_convention.sql` | The 4 cap-convention tests, with expected results inline |
| `discounts-in-price-shock.md` v3.0 | The analysis narrative, version history, and how each conclusion was reached |
| `daily_price_shock_alert.sql` v2.1 | The existing alert this extends. Unchanged |

**Snowflake query IDs for every figure in this document:**

| Figure | Query ID |
|---|---|
| Penetration & field equivalence | `01c6cc1b-020b-2012-000b-86f721ade72` |
| Voucher formula validation | `01c6cc46-020b-246a-000b-86f721af7aa2` |
| Promotion-engine scaling evidence | `01c6cca9-020b-21f4-000b-86f721b59806` |
| Promotion-engine formula validation | `01c6ccab-020b-205a-000b-86f721b5e43e` |
| Headline + segments | `01c6ccaa-020b-24cd-000b-86f721b5abf6` |
| Identity check | `01c6cc21-020b-21f4-000b-86f721ade38e` |
| Cap convention — vouchers, population | `01c6cccc-020b-21f4-000b-86f721b78ff6` |
| Cap convention — engine, population | `01c6cccd-020b-246a-000b-86f721b7a67a` |
| Cap convention — nine named rides | `01c6ccce-020b-21f4-000b-86f721b7b30a` |
| SQL smoke test | `01c6ccb1-020b-2012-000b-86f721b6267a` |

---

**SME inputs (Hamza, 2026-09-02):** promotion-engine discounts are shown and applied before the ride request · the SA ride-hailing surcharge is 0.58 gross, because VAT of 0.075 rounds up to 0.08 · a discount can grow from its quoted value when the fare rises and the cap has not been reached.

**Nothing in this change alters an existing bucket definition, precedence order, threshold or baseline.** All prior figures remain comparable.
