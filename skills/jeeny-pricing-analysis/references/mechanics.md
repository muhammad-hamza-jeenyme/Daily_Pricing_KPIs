# Mechanics: data model + how a fare is determined

## 1. Objects and joins

| Object | Grain | Role |
|---|---|---|
| `RIDE.DETAILS` | 1/`RIDEID` | Spine: lifecycle, area, service, surge/PD, end-of-ride surcharge |
| `RIDE.UPFRONT` | 1/`RIDEID` | Scenario, estimates, charging inputs, additional time, scaled distance |
| `RIDE.RECEIPTS` | 1/`RIDEID` | Charged total + every line item |
| `PASSENGERS.PRICECHECKS` | **many per quote session** (one per service) | The quote shown |
| `GENERAL.AREAS` | 1/`AREA_CODE` | `COUNTRY_CODE` → VAT factor + currency |
| `RIDE.EVENTHISTORY` | many/ride | Pickup proxy via `ride_offered`; key is `ID`, not `RIDEID` |

```
AREAS ─AREA_CODE─ DETAILS ─RIDEID─ UPFRONT
                     ├───RIDEID─── RECEIPTS
                     ├─ RIDEID + LOWER(SERVICEFILTER)=LOWER(REQUEST_SERVICE) ─ PRICECHECKS
                     └─ RIDEID = EVENTHISTORY.ID (event_name='ride_offered', first TRIGGERED_AT)
```

Inner-joining UPFRONT and RECEIPTS is what makes "upfront applied and ride charged" true — a left join silently changes the universe.

Anything outside these six objects: use the `jeeny-snowflake-bi-catalog` skill for the full 142-object dictionary.

## 2. Gotchas

1. **PriceChecks fans out.** Join on `RIDEID` *and* service, then `QUALIFY ROW_NUMBER() OVER (PARTITION BY rd.rideid ORDER BY pc.actualdatetime DESC NULLS LAST) = 1`. Symptom: ride count above the true universe.
2. **`pc.VAT` is not ride VAT** — it's hailing surcharge + its VAT. Treating it as ride VAT double-counts, since `VALUE` already includes SA ride VAT.
3. **`pc.SURCHARGE` is ex-VAT.** Gross up ×1.15 SA / ×1.0 JO for the shown-fare compare; but compare **ex-VAT to ex-VAT** for the bucket-2 mismatch (`rd.SURCHARGE + rd.INTERCITYSURCHARGE` vs `pc.SURCHARGE`). Omitting `INTERCITYSURCHARGE` makes every intercity ride look broken.
4. **`pc.MINIMUMFARE` is not the min fare.** Min fare lives in the area taximeter config; only visible as the leading `max(...)` literal inside `UPFRONT.TAXIMETERFORMULA` (an inference, not SME-confirmed). Use stored `VALUE` / `CHARGINGFARE`.
5. **`UPFRONT.CHARGINGFARE` ≠ what the passenger paid** — excludes hailing, waiting, cancel fine, discount. Always compare to `RECEIPTS.TOTALAMOUNTWITHTAX`.
6. **`RECEIPTS.SUBTOTAL` does not reconcile.** `SUBTOTAL − DISCOUNT − VATONDISCOUNT = TOTAL` held on only 16/100 sample rows. Build from line items instead (SKILL.md §3, verified 100/100).
7. **Mixed units.** `ACTUALTIME`/`APPLIEDESTIMATETIME`/`MAXWITHINMINUTESVARIANCE` minutes · `TIMETHRESHHOLDS*VALUE` seconds · threshold percentages are percentage points (22 = +22%) · `RECEIPTS.DISTANCE`/`DURATION` are metres/seconds while `PRICECHECKS.DISTANCE`/`DURATION` are km/minutes.
8. **Booleans arrive as text.** Compare `LOWER(TO_VARCHAR(DROPOFFATDESTINATION)) = 'true'`; same for `APPLIEDFIXEDTIMETHRESHOLDAPPLIED`.
9. **`COALESCE` money columns to 0** or one NULL voids the whole `Fare_Diff` and the ride vanishes from the classification. **Do NOT coalesce the multipliers** — a NULL forced to 0 reads as a false bucket-1 mismatch; left NULL, the comparison just doesn't fire.
10. **Scenario casing** is `withinA` / `withinB` / `beyondB` in prod; compare with `LOWER()`.

## 3. Columns that matter

**`PRICECHECKS`** — `VALUE` (quote incl. SA ride VAT; = `ORIGINALESTIMATEFARE`) · `VAT` (hailing+VAT) · `SURCHARGE` (ex-VAT) · `BASEFARE` (taximeter output) · `SURGEMULTIPLIER`, `DISCRIMINATIONMULTIPLIER` · `SERVICEFILTER` · `ACTUALDATETIME` (pick latest) · `PICKUPLAT/LONG`, `DESTLAT/LONG` · `DISTANCE`, `DURATION` (km, minutes) · `MINIMUMFARE`/`MAXIMUMFARE` (don't use) · `DISCOUNT` (not populated) · `RANDOMISATION_*` (surge experiment; link to mismatches unconfirmed) · `CUSTOMERSEGMENT`, `PD_GROUP`, `TRACEID`.

**`DETAILS`** — `CREATEDDATE` (Saudi date) · `AREA_CODE` · `BOARDED` · `REQUEST_SERVICE` · `SURGEMULTIPLIER`, `DISCRIMINATIONMULTIPLIER` (bucket 1) · `ACTUALDISCRIMINATIONMULTIPLIER` (unvalidated) · `SURCHARGE`, `VATONSURCHARGE`, `INTERCITYSURCHARGE`, `VATONINTERCITYSURCHARGE` (bucket 2) · `RIDEHAILINGSURCHARGE`(+VAT) · `TAXIMETERPRICE`, `TAXIMETERBOARDTOFINISHDISTANCE/DURATION` · `ESTIMATEDDISTANCE`, `ESTIMATEDTRAVELTIME`, `ESTIMATEDAMOUNT` · `REQUESTLAT/LONG`, `ACTUALPICKUPLAT/LNG`, `ACTUALDROPOFFLAT/LON`, `REQUESTEDDROPOFFLAT/LONG` · `ADDRESSSOURCESPICKUP`/`DESTINATION` (sample values `manual_pin`, `search`, `recent`, `saved_address`, `landmark` — not an authoritative enum) · waiting mechanics `TOTALWAITINGTIME`, `CHARGEDWAITINGTIME`, `COURTESYTIME`, `MAXCHARGEABLEMINUTES`, `WAITTIMEFACTOR`, `WAITINGTIMEFEE` · `DESTINATIONAREACODE`, `REQUESTEDDESTINATIONAREACODE` (intercity) · `TRACEID`. Ignore `OUTSTANDINGBALANCE`. Receipt-mirroring columns exist here — prefer `RECEIPTS`.

**`UPFRONT`** — `UPFRONTSCENARIO` · `DROPOFFATDESTINATION` · `ORIGINALESTIMATEFARE/TIME/DISTANCE` · `APPLIEDESTIMATEFARE/TIME/DISTANCE` · `RECALCULATEDFARE/TIME/DISTANCE` · `TAXIMETERFARE/TIME/DISTANCE`, `TAXIMETERFORMULA`, `TAXIMETERCASE`, `TAXIMETERSTATE` · `CHARGINGDISTANCE`, `CHARGINGDISTANCESOURCE`, `CHARGINGTIME`, `CHARGINGTIMESOURCE`, `CHARGINGFARE`, `FINALRIDEFARE` · `ADDITIONALTIMECOMP`, `ADDITIONALTIMEVALUE`, `FACTORFORADDITIONALTIME` · `ACTUALTIME`, `ACTUALSPEED`, `ESTIMATEDSPEED`, `MAXSPEED`, `SPEEDPARAMETERX` · `SCALEDDISTANCE`, `FIXEDSPEEDCAP`, `KALMANDISTANCE` · `TIMETHRESHHOLDSA/B{LOW,HIGH}{PERCENTAGE,VALUE}` · `MAXWITHINMINUTESVARIANCE` · `APPLIEDFIXEDTIMETHRESHOLDAPPLIED/VALUE`.

**`RECEIPTS`** — `TOTALAMOUNTWITHTAX` · `DISCOUNT`, `VATONDISCOUNT` (add back) · `WAITINGCHARGES`(+VAT), `CANCELLATIONFINE`(+VAT) (= `Non_Issue`) · `RIDEHAILINGSURCHARGE`(+VAT) (= `pc.VAT`) · `RIDEVALUE`, `VATONRIDEVALUE` · `SURCHARGE`(+VAT), `INTERCITYSURCHARGE`(+VAT) · `UNROUNDEDRIDEFINALVALUE` (for rounding cases) · `SUBTOTAL` (don't use).

## 4. How the quote is built

```
BaseFare       = taximeter formula, e.g. max(8.63, 0.994*(0.21*durMin + 0.84*distKm + 3.97))
Effective fare = MAX(BaseFare × Surge, MinFare) × PD × (VAT if SA)   → PRICECHECKS.VALUE
```

Movable determinants between quote and ride: **surge**, **PD**, and the **Google distance/duration** feeding the taximeter. Min fare can't be recomputed (not in BI), which is why stored `VALUE` is authoritative.

## 5. How the charge is built

```
RIDEVALUE    = (taximeter(charging inputs) + ADDITIONALTIMEVALUE) × SURGE × PD     -- ex-VAT
CHARGINGFARE = RIDEVALUE + VATONRIDEVALUE                                         -- VAT SA only
```

`RIDEVALUE` is **ex-VAT** (verified: 43.94 + 6.59 = `CHARGINGFARE` 50.53). The SME text reads "× (VAT if SA)" then sums — that phrasing looks like double VAT; it isn't. The receipt then adds hailing, area/intercity surcharge, waiting, cancel fine, and subtracts discount.

## 6. Scenarios

| Scenario | Condition | Behaviour |
|---|---|---|
| `withinA` | **Either** (1) `ACTUALTIME * 60` ∈ `[TIMETHRESHHOLDSALOWVALUE, TIMETHRESHHOLDSAHIGHVALUE]`, **or** (2) `ACTUALTIME − APPLIEDESTIMATETIME ≤ MAXWITHINMINUTESVARIANCE` (minutes) | charge the quote. A-low ≈ 0, so finishing early usually still withinA via (1) |
| `withinB` | outside A, inside B | additional-time path; dominated by `increase_pricing` by construction |
| `beyondB` | outside B | rare (`TIMETHRESHHOLDSBHIGHPERCENTAGE` often ~999999); round trips, or dropoff≠dest with re-Googled duration ≈ 0 |

`withinA` can still increase legitimately when `DROPOFFATDESTINATION = false` (re-Google). A rising `pct_withinB` by city is an **estimate-quality** signal, not a charging bug.

## 7. Thresholds and additional time

```
TIMETHRESHHOLDSAHIGHVALUE ≈ APPLIEDESTIMATETIME × 60 × (1 + TIMETHRESHHOLDSAHIGHPERCENTAGE/100)
```
(verified: 22.6 min at 22% → 1654 s; same pattern A-low / B-low / B-high; A-low often ≈ 0)

```
IF ACTUALTIME × 60 > TIMETHRESHHOLDSAHIGHVALUE AND APPLIEDFIXEDTIMETHRESHOLDAPPLIED = FALSE:
   ADDITIONALTIMECOMP  = ACTUALTIME − APPLIEDESTIMATETIME          -- minutes, this order
   ADDITIONALTIMEVALUE = ADDITIONALTIMECOMP × FACTORFORADDITIONALTIME
```

Subtraction order verified 21/21 on sample; the original SME write-up had it inverted, so treat any `APPLIEDESTIMATETIME − ACTUALTIME` you find as a stale copy.

## 8. Distance path

| Condition | Distance charged |
|---|---|
| actual < estimated distance | estimated distance |
| speed within limit | taximeter distance |
| speed beyond limit | **scaled distance** = `ActualTime × FIXEDSPEEDCAP` |

`FIXEDSPEEDCAP` is on `RIDE.UPFRONT` — the speed used to calculate `SCALEDDISTANCE` from `ACTUALTIME` when scaled distance applies. Anti-GPS-spoofing guard; ≈0–16 rides per 29 days.

## 9. VAT and currency

| | SA | JO |
|---|---|---|
| Ride VAT | 15%, already inside `VALUE` | none |
| PC surcharge gross-up | ×1.15 | ×1.0 |
| Currency | SAR | JOD |

Three distinct surcharges: **ride-hailing** (platform fee, mirrors `pc.VAT`), **area** (`SURCHARGE`), **intercity** (`INTERCITYSURCHARGE`). Surcharge is *allowed* to differ quote-vs-ride when dropoff ≠ destination — which is exactly why bucket 2 restricts to dropoff-at-destination.
