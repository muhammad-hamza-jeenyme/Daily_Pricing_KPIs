# Baselines, bucket detail, tickets

## 1. Sanity checks — run before interpreting anything

1. **Ride count**: ~5.18M over 29 days, ~5.36M over 30 days (SA+JO); ~2.86M SA / ~2.50M JO over 30 days. Higher ⇒ PriceChecks fanned out (missing service match or `QUALIFY`).
2. **Shock rate**: ~41% SA, ~26% JO. Far off ⇒ a formula term is missing, usually the discount add-back or the surcharge gross-up.
3. **Buckets total 100%** of the chosen denominator and match the shock count within ride-level rounding noise.
4. **Bucket 6 = 0** in a strict-shock table. If not, the filter is `> 0` not `> 0.01`.
5. **Currencies separated** — no SAR+JOD money total anywhere.
6. **Money columns coalesced**; a zero-shock city is usually a NULL, not a clean city.
7. **Decomposition identity**: `d_ridevalue + d_hailing + d_surcharge + Non_Issue = Fare_Diff` should hold to the penny. It failing means a line item was dropped.

## 2. Quantum — window 2026-07-11 → 2026-08-09 (30 days), taxonomy v2026-08-10

| Market | Completed | Shocks (`>0.01`) | % | Total excess | Avg | P90 |
|---|---:|---:|---:|---:|---:|---:|
| SA | 2,860,551 | 1,182,722 | **41.35%** | 4,768,318.86 SAR | 4.03 | 9.90 |
| JO | 2,495,416 | 650,815 | **26.08%** | 435,924.07 JOD | 0.67 | 1.50 |
| SA+JO | 5,355,967 | 1,833,537 | **34.23%** | *never combine* | — | — |

Daily rate is stable: SA ~39.95–44.16% (higher Fridays), JO ~24.92–27.61%. Excess tracks volume, so read rates and per-ride averages, not totals.

## 3. Bucket mix

Strict shocks (`Fare_Diff > 0.01`):

| Bucket | SA rides | SA % | JO rides | JO % | Combined % | Avg SAR / JOD |
|---|---:|---:|---:|---:|---:|---|
| 1 Surge/PD mismatch | 724 | 0.06% | 319 | 0.05% | 0.06% | 4.74 / 0.54 |
| 2 Surcharge mismatch | 20,315 | 1.72% | 408 | 0.06% | 1.13% | 1.81 / 1.16 |
| 3 Wrong pickup (proxy) | 104 | 0.01% | 26 | 0.00% | 0.01% | 7.19 / 0.51 |
| 4 Cancellation fine | 315,491 | 26.68% | 84,262 | 12.95% | 21.80% | 4.37 / 0.93 |
| 5 Waiting charges | 536,925 | 45.40% | 260,101 | 39.97% | 43.47% | 2.39 / 0.33 |
| 6 Rounding | 0 | 0% | 0 | 0% | 0% | — |
| 7 Additional time | 186,508 | 15.77% | 166,464 | 25.58% | 19.25% | 6.37 / 0.75 |
| 8 Unclassified | 122,654 | 10.37% | 139,235 | 21.39% | 14.28% | 7.15 / 1.05 |

All positive gaps (`> 0`, rounding visible) — combined totals 1,901,837, i.e. ~4% more than strict:

| Bucket | SA | JO | Combined | Combined % |
|---|---:|---:|---:|---:|
| 1 | 728 | 321 | 1,049 | 0.06% |
| 2 | 30,491 | 409 | 30,900 | 1.62% |
| 3 | 106 | 28 | 134 | 0.01% |
| 4 | 315,587 | 84,275 | 399,862 | 21.03% |
| 5 | 537,123 | 260,291 | 797,414 | 41.93% |
| 6 | 31,889 | 25,728 | 57,617 | 3.03% |
| 7 | 186,508 | 166,464 | 352,972 | 18.56% |
| 8 | 122,654 | 139,235 | 261,889 | 13.77% |

Bucket 8 carries the **highest average overcharge of any large bucket** (7.15 SAR / 1.05 JOD) — higher than every legitimate bucket in both markets. Combined with no ticket covering it, that makes it the highest-value target.

Three different "surcharge mismatch" numbers exist and are not interchangeable: 20,315 SA strict shocks · 30,491 SA positive gaps (so ~10k carry only a ≤0.01 gap) · and any count that doesn't condition on `Fare_Diff` at all, which is larger still and unmeasured.

## 4. Digest shape — 29-day window 2026-07-06 → 2026-08-03 (~5.18M rides)

`issue_type` × scenario, ride counts:

| Country | Scenario | matched | rounding | incr_non_issue | incr_pricing | decr_pricing |
|---|---|---:|---:|---:|---:|---:|
| JO | withinA | 1,631,732 | 25,969 | 262,056 | 86,346 | 83,719 |
| JO | withinB | 300 | 607 | 704 | 276,234 | 17,715 |
| JO | beyondB | 1,447 | 20 | 152 | 1,569 | 1,269 |
| SA | withinA | 1,415,057 | 64,831 | 662,794 | 99,862 | 121,127 |
| SA | withinB | 520 | 88 | 1,605 | 391,411 | 26,316 |
| SA | beyondB | 420 | 8 | 222 | 735 | 2,321 |

Expected shape: withinB dominated by `increase_pricing`; `increase_non_issue` large on withinA; beyondB rare; scaled-distance ≈0–16/29d. Note this query did **not** de-duplicate PriceChecks, so a de-duplicated re-run may read slightly lower — that's the fix, not a data problem.

Top areas by `increase_pricing` on 2026-08-03: AMM 8,105 · JED 5,910 · RUH 5,504 · IRB 2,771 · ZRQ 2,094 · MAD 1,762 · DMM 1,152 · MEC 1,004.

## 5. Open tech tickets

From `Pricing Bugs Investigations by Tech.xlsx`. All **UNDER INVESTIGATION** — hypotheses, not confirmed causes or fixes.

| Ticket | Status | Bucket | Shocks |
|---|---|---|---:|
| Surge/PD multiplier mismatch at PC vs request | In Progress | 1 | 1,043 |
| Surcharge mismatch despite dropoff at dest + withinA | Backlog | 2 | 20,723 |
| Wrong pickup points in Google estimate | In Progress | 3 (proxy) | 130 |
| Wrong pickup **and dropoff** points | In Progress | 3 partial, else 8 | TBD — no dropoff-pin flag |
| Google estimate path missing on map | In Progress | none — no BI field | TBD |
| Destination not filled / estimate provenance | In Progress | out of universe | n/a |
| Taximeter path missing on map | In Progress | none — no BI field | TBD |
| *(no ticket)* rounding 0.01 | — | 6 | 0 strict / 57,617 gaps |

**Headline for stakeholders:** open tickets explain ~1.2% of shock rides. The rest is contractual (4+5, ~65%), documented additional-time charging (7, ~19%) and unexplained (8, ~14%). Fixing every known bug barely moves the shock rate — the real conversations are disclosure and bucket 8.

## 6. Open questions

Bucket 3 is a proxy, not a measurement · dropoff≠destination volume has no product label (legitimate vs design gap) · withinA+dest residual not yet decomposed by component · `ACTUALDISCRIMINATIONMULTIPLIER` unvalidated · no BI columns for path-on-map, `MinFare` · `FIXEDSPEEDCAP` / `MAXWITHINMINUTESVARIANCE` now on `UPFRONT` (withinA = A-band **or** minute-variance ≤ max) · whether surge randomisation can legitimately cause a bucket-1 mismatch is unconfirmed with SMEs.
