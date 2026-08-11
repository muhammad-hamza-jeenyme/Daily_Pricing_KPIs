# Price shock analysis — SA & JO (last 30 complete days)

**Analyst role:** Pricing  
**Window:** `CREATEDDATE` **2026-07-11 → 2026-08-09** inclusive (`>= CURRENT_DATE()-30` and `< CURRENT_DATE()` on 2026-08-10)  
**Markets:** SA, JO separately; combined counts only (never mix SAR + JOD in money figures)  
**Taxonomy version:** re-run 2026-08-10 (tech mismatches before contractual line items; rounding as bucket 6)  
**Status of tech tickets:** all Excel rows still **UNDER INVESTIGATION** — hypotheses, not confirmed fixes  

---

## 1. Problem statement

Passengers see a PriceCheck quote, then pay a higher final receipt on completed rides.

**Price shock (strict):** boarded ride with destination where:

```
Fare_Diff = Normalized_Receipt − PriceCheck_Shown > 0.01
```

```
PC_Surcharge_Gross = ROUND(PriceChecks.SURCHARGE × IFF(SA, 1.15, 1.0), 2)
PriceCheck_Shown   = PriceChecks.VALUE + PriceChecks.VAT + PC_Surcharge_Gross
Normalized_Receipt = Receipts.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT
```

**Rounding (bucket 6):** `0 < Fare_Diff ≤ 0.01` — not a shock by definition; included in the cause taxonomy so all positive fare gaps are assigned exactly one bucket.

**Primary tables:** `JEENY_PROD.RIDE.DETAILS`, `RIDE.UPFRONT`, `RIDE.RECEIPTS`, `PASSENGERS.PRICECHECKS`, `GENERAL.AREAS`  
**Pickup proxy (bucket 3):** `RIDE.EVENTHISTORY` (`ride_offered`)  
**Date column:** `RIDE.DETAILS.CREATEDDATE`  
**Universe:** `BOARDED IS NOT NULL`, `UPFRONT.ORIGINALESTIMATEFARE IS NOT NULL`, `COUNTRY_CODE IN ('SA','JO')`, one PriceCheck per ride (`LOWER(SERVICEFILTER)=LOWER(REQUEST_SERVICE)`, latest `ACTUALDATETIME`)

---

## 2. Quantum

### 2.1 Headline (by market + combined counts)

| Market | Completed rides | Shock rides (`Fare_Diff > 0.01`) | % of completed | Total excess fare | Avg overcharge | P90 overcharge | Positive rounding (`0 < diff ≤ 0.01`) |
|--------|----------------:|---------------------------------:|---------------:|------------------:|---------------:|---------------:|--------------------------------------:|
| **SA** | 2,860,551 | 1,182,722 | **41.35%** | **4,768,318.86 SAR** | 4.03 SAR | 9.90 SAR | 31,889* |
| **JO** | 2,495,416 | 650,815 | **26.08%** | **435,924.07 JOD** | 0.67 JOD | 1.50 JOD | 25,728* |
| **SA+JO** | 5,355,967 | 1,833,537 | **34.23%** | *(not combined)* | *(not combined)* | *(not combined)* | 57,617* |

\*Positive rounding from taxonomy query `01c64a68-030a-834c-000b-86f71d082796` (bucket 6 after precedence). Rides with rounding **and** an earlier-bucket flag (e.g. surge) are counted in that earlier bucket, not here.

**SQL — headline quantum** (query `01c64a5b-030a-8560-000b-86f71d078482`):

```sql
WITH params AS (
  SELECT DATEADD('day', -30, CURRENT_DATE()) AS win_start,
         CURRENT_DATE() AS win_end
),
BaseRides AS (
  SELECT
    rd.rideid,
    ga.country_code AS country,
    COALESCE(pc.value, 0) AS pc_value,
    COALESCE(pc.vat, 0) AS pc_vat_hailing,
    ROUND(COALESCE(pc.surcharge, 0) * IFF(ga.country_code = 'SA', 1.15, 1.0), 2) AS pc_surcharge_gross,
    COALESCE(rr.totalamountwithtax, 0) AS rr_total,
    COALESCE(rr.discount, 0) AS rr_discount,
    COALESCE(rr.vatondiscount, 0) AS rr_vatdiscount
  FROM jeeny_prod.ride.details rd
  JOIN jeeny_prod.ride.upfront uf ON rd.rideid = uf.rideid
  JOIN jeeny_prod.ride.receipts rr ON rd.rideid = rr.rideid
  JOIN jeeny_prod.general.areas ga ON rd.area_code = ga.area_code
  JOIN jeeny_prod.passengers.pricechecks pc
    ON pc.rideid = rd.rideid
   AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
  CROSS JOIN params p
  WHERE rd.boarded IS NOT NULL
    AND uf.originalestimatefare IS NOT NULL
    AND ga.country_code IN ('SA', 'JO')
    AND rd.createddate >= p.win_start
    AND rd.createddate < p.win_end
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY rd.rideid
    ORDER BY pc.actualdatetime DESC NULLS LAST
  ) = 1
),
Scored AS (
  SELECT
    country,
    ROUND(
      (rr_total + rr_discount + rr_vatdiscount)
      - (pc_value + pc_vat_hailing + pc_surcharge_gross), 2
    ) AS fare_diff
  FROM BaseRides
)
SELECT
  country,
  COUNT(*) AS completed_rides,
  SUM(IFF(fare_diff > 0.01, 1, 0)) AS shock_rides,
  ROUND(100.0 * SUM(IFF(fare_diff > 0.01, 1, 0)) / NULLIF(COUNT(*), 0), 4) AS pct_shock,
  SUM(IFF(fare_diff > 0.01, fare_diff, 0)) AS total_excess_fare,
  ROUND(AVG(IFF(fare_diff > 0.01, fare_diff, NULL)), 4) AS avg_overcharge,
  ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY IFF(fare_diff > 0.01, fare_diff, NULL)), 4) AS p90_overcharge
FROM Scored
GROUP BY ROLLUP(country)
ORDER BY country NULLS LAST;
```

### 2.2 Trend by day

Shock **rate** stable across the window (query `01c64a5c-030a-85ff-000b-86f71d07a48a`):

| Market | Daily `% shock` range | Pattern |
|--------|----------------------|---------|
| SA | ~39.95% → ~44.16% | Higher on Fridays; excess SAR tracks volume |
| JO | ~24.92% → ~27.61% | Mild mid-week peaks |

Selected days:

| Date | SA shocks | SA % | SA excess (SAR) | JO shocks | JO % | JO excess (JOD) |
|------|----------:|-----:|----------------:|----------:|-----:|----------------:|
| 2026-07-11 | 37,989 | 42.66 | 156,590.33 | 18,491 | 25.52 | 11,887.40 |
| 2026-07-17 | 30,965 | 44.16 | 134,211.67 | 14,261 | 27.19 | 9,873.90 |
| 2026-07-30 | 48,566 | 41.39 | 212,272.97 | 24,951 | 26.32 | 17,496.22 |
| 2026-08-09 | 39,942 | 39.95 | 148,804.13 | 21,791 | 25.63 | 14,594.46 |

---

## 3. Root cause (exclusive buckets)

### Precedence (first match wins — buckets sum to 100%)

Applied to **every ride with `Fare_Diff > 0`** (positive gap vs PriceCheck). Strict shocks are the subset with `Fare_Diff > 0.01`.

1. Surge **or** PD multiplier mismatch — PC vs Details (`SURGEMULTIPLIER` / `DISCRIMINATIONMULTIPLIER`)  
2. Surcharge mismatch @ PC vs request, **withinA + dropoff at destination**  
3. Incorrect pickup point in Google estimate — proxy: PC pickup vs first `ride_offered` **> 100m**  
4. Previous cancellation fine applied — `CANCELLATIONFINE + VATONCANCELLATIONFINE > 0.01`  
5. Waiting time charges — `WAITINGCHARGES + VATONWAITINGCHARGES > 0.01`  
6. Rounding — `0 < Fare_Diff ≤ 0.01`  
7. Additional time value — `ADDITIONALTIMEVALUE > 0.01` **and** dropoff at destination  
8. Unclassified  

**Effect of reordering vs prior run:** tech flags (1–3) now win over cancel/waiting. SA surcharge-mismatch shocks rise from ~3.6k → **20.3k** because many cancel/waiting rides also had surcharge mismatch and were previously attributed to contractual buckets.

### 3.1 Strict shocks only (`Fare_Diff > 0.01`) — by market

Bucket 6 is **impossible** here (by shock definition) → 0 rides / 0%.

| Bucket | SA rides | SA % | SA avg (SAR) | SA excess (SAR) | JO rides | JO % | JO avg (JOD) | JO excess (JOD) | Classification | Confidence |
|--------|---------:|-----:|-------------:|----------------:|---------:|-----:|-------------:|----------------:|----------------|------------|
| 1. Surge or PD mismatch | 724 | 0.06% | 4.74 | 3,429.93 | 319 | 0.05% | 0.54 | 171.48 | **TECH BUG** (hypothesis) | Medium |
| 2. Surcharge mismatch (withinA + dest) | 20,315 | 1.72% | 1.81 | 36,815.36 | 408 | 0.06% | 1.16 | 474.31 | **TECH BUG** (hypothesis) | Medium |
| 3. Incorrect pickup (proxy) | 104 | 0.01% | 7.19 | 747.49 | 26 | 0.00% | 0.51 | 13.21 | **TECH BUG** (hypothesis) | **Low** |
| 4. Prev. cancellation fine | 315,491 | 26.68% | 4.37 | 1,377,228.80 | 84,262 | 12.95% | 0.93 | 78,367.85 | **LEGITIMATE** | High |
| 5. Waiting time charges | 536,925 | 45.40% | 2.39 | 1,284,388.64 | 260,101 | 39.97% | 0.33 | 85,042.52 | **LEGITIMATE** | High |
| 6. Rounding | 0 | 0% | — | — | 0 | 0% | — | — | **TECH BUG** | High (definitionally empty among shocks) |
| 7. Additional time value | 186,508 | 15.77% | 6.37 | 1,188,975.46 | 166,464 | 25.58% | 0.75 | 125,209.48 | **LEGITIMATE** / UX may feel **PRODUCT DESIGN GAP** | Medium on label |
| 8. Unclassified | 122,654 | 10.37% | 7.15 | 876,733.16 | 139,235 | 21.39% | 1.05 | 146,645.22 | **UNKNOWN** | High |

Evidence: query `01c64a68-030a-834c-000b-86f71d08282e`.  
SA sum = 1,182,721; JO sum = 650,815 (matches quantum within 1-ride noise).

### 3.2 Strict shocks — combined counts only

| Bucket | Shock rides | % of shocks |
|--------|------------:|------------:|
| 1. Surge or PD mismatch | 1,043 | 0.06% |
| 2. Surcharge mismatch (withinA + dest) | 20,723 | 1.13% |
| 3. Incorrect pickup | 130 | 0.01% |
| 4. Prev. cancellation fine | 399,753 | 21.80% |
| 5. Waiting time charges | 797,026 | 43.47% |
| 6. Rounding | 0 | 0.00% |
| 7. Additional time value | 352,972 | 19.25% |
| 8. Unclassified | 261,889 | 14.28% |
| **Total** | **1,833,536** | **100%** |

Query: `01c64a68-030a-85ff-000b-86f71d08407e` (`pct_of_shocks` column).

### 3.3 Positive fare gaps (`Fare_Diff > 0`) — includes rounding

Use this table when bucket 6 must appear in the 100% mix.

| Bucket | SA rides | SA % of +gaps | JO rides | JO % of +gaps | Combined rides | Combined % |
|--------|---------:|--------------:|---------:|--------------:|---------------:|-----------:|
| 1. Surge or PD | 728 | 0.06% | 321 | 0.05% | 1,049 | 0.06% |
| 2. Surcharge mismatch | 30,491 | 2.49% | 409 | 0.06% | 30,900 | 1.62% |
| 3. Incorrect pickup | 106 | 0.01% | 28 | 0.00% | 134 | 0.01% |
| 4. Cancel fine | 315,587 | 25.76% | 84,275 | 12.45% | 399,862 | 21.03% |
| 5. Waiting | 537,123 | 43.84% | 260,291 | 38.46% | 797,414 | 41.93% |
| 6. Rounding | 31,889 | 2.60% | 25,728 | 3.80% | 57,617 | 3.03% |
| 7. Additional time | 186,508 | 15.22% | 166,464 | 24.60% | 352,972 | 18.56% |
| 8. Unclassified | 122,654 | 10.01% | 139,235 | 20.57% | 261,889 | 13.77% |

Evidence: `01c64a68-030a-834c-000b-86f71d082796`, `01c64a68-030a-85ff-000b-86f71d08407e`.

**SA note:** 30,491 surcharge-mismatch positive gaps vs 20,315 shocks → **~10k** withinA+dest surcharge mismatches have only a ≤0.01 fare gap (or were classified into bucket 2 before cancel/waiting with tiny residual). Treat volume carefully when comparing to Slack “surcharge mismatch rides” KPI.

### 3.4 Bucket SQL (new precedence)

```sql
-- Taxonomy: Fare_Diff > 0 ; strict shocks = Fare_Diff > 0.01
CASE
  WHEN ROUND(pc_surge, 4) <> ROUND(rd_surge, 4)
    OR ROUND(pc_pd, 4) <> ROUND(rd_pd, 4)
    THEN '1_surge_or_pd_mismatch'
  WHEN LOWER(upfrontscenario) = 'withina'
   AND LOWER(TO_VARCHAR(dropoffatdestination)) = 'true'
   AND ROUND(rd_surcharge + rd_intercitysurcharge, 2) <> ROUND(pc_surcharge_ex_vat, 2)
    THEN '2_surcharge_mismatch_withina_dest'
  WHEN is_pickup_mismatch = 1 THEN '3_incorrect_pickup_google_estimate'
  WHEN (rr_cancelfine + rr_vatcancelfine) > 0.01 THEN '4_prev_cancellation_fine'
  WHEN (rr_waitingcharges + rr_vatwaitingcharges) > 0.01 THEN '5_waiting_time_charges'
  WHEN fare_diff > 0 AND fare_diff <= 0.01 THEN '6_rounding_0_01'
  WHEN additionaltimevalue > 0.01
   AND LOWER(TO_VARCHAR(dropoffatdestination)) = 'true'
    THEN '7_additional_time_value'
  ELSE '8_unclassified'
END AS cause_bucket
```

Full query body matches prior analysis (BaseRides + OfferEvent + fare_diff); filter `fare_diff > 0` for §3.3 or `fare_diff > 0.01` for §3.1.

---

## 4. Cross-reference to open tech tickets

Source: `C:\Users\Muhammad Hamza\Desktop\Pricing Bugs Investigations by Tech.xlsx`. All **UNDER INVESTIGATION**.

| Excel issue | Status | Maps to bucket | Shock volume (SA+JO) | Notes |
|-------------|--------|----------------|---------------------:|-------|
| Surge or PD Multiplier Mismatch at PC vs Ride Request | In Progress | **1** | 1,043 | Still tiny share of shocks |
| Surcharge Mismatch despite dropoff at dest and withinA | Backlog | **2** | 20,723 | Much larger under new precedence (was ~3.9k when cancel/waiting ranked first) |
| Wrong Pickup points in Google estimate | In Progress | **3** (proxy) | 130 | Low-confidence proxy |
| Wrong Pickup and Dropoff points in Google Estimates | In Progress | **3** partial; else **8** | TBD — no dropoff-pin flag | Mostly unclassified when dropoff≠dest |
| Google Estimate path missing on map | In Progress | **None** | TBD — missing BI field | |
| Destination not filled / Original Estimate provenance | In Progress | **Out of universe** | N/A | Requires `ORIGINALESTIMATEFARE IS NOT NULL` |
| Taximeter path missing on map | In Progress | **None** | TBD | |
| *(no Excel row)* Rounding 0.01 | — | **6** | 0 among shocks; 57,617 positive gaps | Separate tech issue |

### Shocks **not** explained by known Excel tickets

| Segment | % of shocks | Why |
|---------|------------:|-----|
| 4 Cancel fine | 21.8% | Contractual |
| 5 Waiting | 43.5% | Contractual |
| 7 Additional time @ dest | 19.3% | Documented withinB/beyondB charging |
| 8 Unclassified | 14.3% | Mostly dropoff≠dest / residual — **no ticket covers volume** |

Open Excel tickets (buckets 1–3) explain **~1.2%** of exclusive shock rides under this taxonomy (up from &lt;0.3% when cancel/waiting ranked first, almost entirely via bucket 2 reassignment).

---

## 5. Open questions / data gaps

1. **Bucket 6 vs shock definition** — Rounding cannot appear among strict shocks. Stakeholders must choose: report §3.1 (shocks only) or §3.3 (all positive gaps).  
2. **Bucket 3 proxy** — PC lat/long vs first offer ≠ wrong Google pin. Confidence **low**.  
3. **withinA + dest residual** still inside unclassified — TBD component drill-down.  
4. **Dropoff≠destination** volume not in buckets 1–7 — product label TBD (LEGITIMATE vs DESIGN GAP).  
5. **Excel issues without BI columns** — missing Google/taximeter path on map.  
6. **PD field** — `DISCRIMINATIONMULTIPLIER` used; `ACTUALDISCRIMINATIONMULTIPLIER` unvalidated.  
7. **Do not mix currencies** in excess-fare totals.
