---
name: jeeny-pricing-analysis
description: Investigation playbook for Jeeny fare increases and price shocks (SA + JO) — the SME-locked fare formulas, the exact residual decomposition that says which fare component moved, the exclusive root-cause taxonomy for tech bug vs legitimate charge, and the JEENY_PROD tables/joins/gotchas behind them. Use for any deep dive into why a passenger paid more than quoted: price shock, fare integrity, overcharge, surge or PD multiplier mismatch, surcharge or intercity surcharge mismatch, upfront scenarios (withinA/withinB/beyondB), additional time value, waiting charges, cancellation fines, scaled distance, dropoff-not-at-destination, unclassified residual, PriceChecks vs Receipts reconciliation, or a single complaining ride. Trigger even on a narrow ask ("surcharge mismatches in RUH last week", "are fares off in Amman", "why is increase_pricing up") — the formulas, join rules and bucket precedence here are locked and must not be re-derived.
---

# Jeeny price-shock investigation

Investigating why charged fare > quoted fare, on boarded rides in SA and JO.

**Never re-derive a fare formula.** Four SME-locked traps: `PriceChecks.VAT` is not ride VAT · `PriceChecks.MINIMUMFARE` is not the min fare · `Upfront.CHARGINGFARE` is not what the passenger paid · `Receipts.SUBTOTAL` does not reconcile (verified: holds on 16/100 sample rows). If a quantity you need isn't here, ask — don't invent it.

| Reference | Read when |
|---|---|
| `references/mechanics.md` | Writing SQL, or explaining *why* a fare came out as it did — tables, joins, gotchas, taximeter/surge/PD/VAT, scenarios, thresholds, additional time, distance |
| `references/baselines.md` | Sanity-checking a query result, sizing a finding, or cross-referencing open tech tickets |

SQL in `assets/sql/`: `base.sql` (scaffold — start here), `quantum.sql` (how big), `causes.sql` (bucket mix), `residual_decomp.sql` (which component moved), `ride_audit.sql` (one ride).

## 1. Universe

```sql
rd.boarded IS NOT NULL                     -- ride happened
AND uf.originalestimatefare IS NOT NULL    -- destination selected → upfront applies
AND ga.country_code IN ('SA','JO')
AND rd.createddate >= <start> AND rd.createddate < CURRENT_DATE()
-- + exactly one PriceCheck per ride (see mechanics.md gotcha 1)
```

`CREATEDDATE` is already a Saudi calendar date — don't re-timezone. **Never sum SAR with JOD**; report money per market, counts may combine.

## 2. Locked comparison

```
PC_Surcharge_Gross = ROUND(PriceChecks.SURCHARGE * IFF(SA, 1.15, 1.0), 2)
PriceCheck_Shown   = PriceChecks.VALUE + PriceChecks.VAT + PC_Surcharge_Gross
Normalized_Receipt = Receipts.TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT
Fare_Diff          = Normalized_Receipt - PriceCheck_Shown
Non_Issue          = WAITINGCHARGES(+VAT) + CANCELLATIONFINE(+VAT)
Residual           = Fare_Diff - Non_Issue
```

`VALUE` already carries SA 15% ride VAT (JO none) and equals `ORIGINALESTIMATEFARE` — don't add VAT on top. `VAT` is the ride-hailing surcharge + its VAT, reconciling to `RIDEHAILINGSURCHARGE + VATONRIDEHAILINGSURCHARGE`. `SURCHARGE` is ex-VAT at quote, so gross it up by country — hardcode the factor, never infer from `VALUE` ratios. Discount is added back so a promo can't masquerade as a fare decrease. Round to 2dp, and round the *difference*.

| Condition | `issue_type` |
|---|---|
| `Fare_Diff = 0` | `matched` |
| `ABS(Fare_Diff) <= 0.01` | `rounding` |
| `Fare_Diff > 0.01`, `Residual <= 0.01` | `increase_non_issue` |
| `Fare_Diff > 0.01`, `Residual > 0.01` | `increase_pricing` |
| `Fare_Diff < -0.01` | `decrease_pricing` |

**Price shock (strict / NET for digests)** = `Fare_Diff > 0.01` **and not** spillover recovery  
(`prev_outs > 0` AND `ABS(prev_outs − CANCELLATIONFINE) ≤ 0.02`; LOOKBACK 30d).  
`increase_pricing` is narrower — also demands `Residual > 0.01`, and digests exclude spillover recovery the same way.  
Gross vs net: ~12.7% of 30d gross shocks were recovery double-counts (SA ~41%→~34%; JO ~26%→~25%). Spec: `docs/payment-spillover-price-shocks.md`. Always say whether a number is **gross** or **net**.

## 3. Residual decomposition — the sharpest tool here

`Normalized_Receipt` is exactly its line items (verified 100/100 on sample; `SUBTOTAL` is not usable for this). Subtracting the quote term-by-term gives an **exact** split of `Fare_Diff`:

```
d_ridevalue = (RIDEVALUE + VATONRIDEVALUE)                                  - PriceChecks.VALUE
d_hailing   = (RIDEHAILINGSURCHARGE + VATONRIDEHAILINGSURCHARGE)            - PriceChecks.VAT
d_surcharge = (SURCHARGE + VATONSURCHARGE + INTERCITYSURCHARGE + VATONINTERCITYSURCHARGE)
                                                                            - PC_Surcharge_Gross
Fare_Diff = d_ridevalue + d_hailing + d_surcharge + Non_Issue     -- identity, 100/100
Residual  = d_ridevalue + d_hailing + d_surcharge
```

This is what makes the "unclassified" bucket tractable: instead of a residual with no explanation, you get which of three components moved and by how much. On a 96-ride sample, shock *value* split 58% `d_ridevalue` / 41% `Non_Issue` / ~1% `d_surcharge` / 0% `d_hailing` — indicative only, so re-run it on your window before quoting. But it points at **`d_ridevalue` as where the real investigation lives**, and §5 is how you interrogate it. Note this is value, not rides: buckets 4+5 are ~65% of shock *rides* while contributing far less per ride, so the two views rank causes differently and you should say which you mean. Run `residual_decomp.sql` early — it usually reframes the question.

## 4. Cause ladder (exclusive, first match wins)

Applied to `Fare_Diff > 0`. Bucket sizes, averages and confidence: `references/baselines.md`.

| # | Bucket | Test | Verdict |
|---|---|---|---|
| 1 | Surge / PD mismatch | `ROUND(pc_surge,4) <> ROUND(rd_surge,4)` OR same for `DISCRIMINATIONMULTIPLIER` | **TECH BUG** (hypothesis) |
| 2 | Surcharge mismatch | `withinA` AND dropoff at dest AND `ROUND(rd.SURCHARGE + rd.INTERCITYSURCHARGE,2) <> ROUND(pc.SURCHARGE,2)` (ex-VAT both sides) | **TECH BUG** (hypothesis) |
| 3 | Wrong pickup pin | PC pickup vs first `ride_offered` event > 100 m | **TECH BUG**, low confidence (proxy) |
| 4 | Prior unpaid / cancel fine | `CANCELLATIONFINE(+VAT) > 0.01` — if spillover recovery (`prev_outs` match ±0.02), **exclude from NET shock counts** | **LEGITIMATE** recovery / prior cancel |
| 5 | Waiting charges | `WAITINGCHARGES + VATONWAITINGCHARGES > 0.01` | **LEGITIMATE** |
| 6 | Rounding | `0 < Fare_Diff <= 0.01` | **TECH BUG**, penny impact; empty among strict shocks |
| 7 | Additional time | `ADDITIONALTIMEVALUE > 0.01` AND dropoff at dest | **LEGITIMATE** charge, disclosure gap |
| 8 | Unclassified | else | **UNKNOWN** → decompose with §3 |

Two traps. **Precedence is a reporting choice**: tech flags rank above contractual ones so a ride with both counts as the bug; flipping the order moved SA bucket 2 from roughly 4k to ~20.3k with no data change. State the version. **Bucket 6 can't appear among strict shocks** (defined as ≤0.01), so pick one denominator — all positive gaps or strict shocks — and label it.

Buckets 4, 5 and 7 are ~85% of shock volume and all legitimate; open tech tickets (1–3) explain ~1.2%. A rising *overall* shock rate is therefore usually more waiting / cancel / additional-time volume, not a new defect. Check the mix before calling regression.

## 5. Interrogating `d_ridevalue`

Ride value differing from the quote is the dominant residual driver and the least documented. Work down these, stopping at the first that explains the delta:

1. **Was dropoff at destination?** `DROPOFFATDESTINATION = false` ⇒ trip was re-Googled; both fare and surcharge legitimately move. Expected, not a bug — but quantify it, because it is a large slice of bucket 8 and product has never labelled it.
2. **Which scenario?** `withinA` should charge the quote. A `withinA` ride with material `d_ridevalue` *and* dropoff at destination is the strongest bug signal in this dataset — there is no documented mechanism for it.
3. **Additional time?** `ADDITIONALTIMECOMP` / `ADDITIONALTIMEVALUE` explain withinB/beyondB growth. Check the maths: `ACTUALTIME − APPLIEDESTIMATETIME` (minutes) × `FACTORFORADDITIONALTIME`. A value that doesn't reconcile is a finding.
4. **Applied vs original estimate.** `APPLIEDESTIMATEFARE`/`TIME`/`DISTANCE` vs `ORIGINALESTIMATE*` shows whether the engine re-estimated. A silent re-estimate on a withinA dropoff-at-dest ride is a bug candidate.
5. **Charging inputs.** `CHARGINGDISTANCESOURCE` / `CHARGINGTIMESOURCE` (`applied_estimate` vs taximeter vs scaled) say which path ran. `TAXIMETERCASE` / `TAXIMETERSTATE` confirm the branch.
6. **Multipliers.** Even when equal, `SURGEMULTIPLIER` and `DISCRIMINATIONMULTIPLIER` scale the whole delta — a 0.1 difference on a large fare is a large absolute gap.
7. **Scaled distance.** `SCALEDDISTANCE > 0` = speed-cap / GPS-spoofing path. Very rare (≈0–16 per 29 days); any material volume is itself the finding.

Units trap: `ACTUALTIME` / `APPLIEDESTIMATETIME` / `MAXWITHINMINUTESVARIANCE` are **minutes**, `TIMETHRESHHOLDS*VALUE` are **seconds**. Band checks use `ACTUALTIME * 60`.  
`withinA` = A-band **or** `ACTUALTIME − APPLIEDESTIMATETIME ≤ MAXWITHINMINUTESVARIANCE`. Scaled distance uses `FIXEDSPEEDCAP` (`SCALEDDISTANCE = ActualTime × FIXEDSPEEDCAP`).

## 6. Method

**Sizing a problem:** `quantum.sql` for rides / % / total excess / avg / P90 per market → `causes.sql` for the bucket mix → `residual_decomp.sql` on the buckets that matter. Check against `baselines.md` before interpreting; a shock rate far from ~41% SA / ~26% JO means a broken query, not a changed world.

**Explaining a movement:** did volume move (rates and per-ride averages, never totals) → which `issue_type` → which scenario → which bucket → which component. One city ⇒ likely local config; all cities ⇒ platform release or pipeline.

**One complaining ride:** `ride_audit.sql` dumps every input side by side. Read it in §5 order; the first line that breaks is the answer.

Aggregate in Snowflake — the universe is ~5M rides per 29 days. Never pull ride-level rows for a population question.

## 7. Reporting

State: bucket + verdict, precedence version and denominator, ride count and share, avg and total excess **per market in its own currency**, area codes and window, confidence, and the query (plus Snowflake query ID) so it reproduces.

Say **"tech bug (hypothesis)"** for buckets 1–2 (no documented reason for the discrepancy, root cause unconfirmed, ticket open) · **"directional, low confidence"** for bucket 3 · **"legitimate"** for 4–5 · **"legitimate charge, disclosure gap"** for 7 · **"unexplained — decomposed to <component>"** for 8. Avoid "confirmed bug", "root cause", "fixed": nothing in this taxonomy is engineering-confirmed. And don't read causation into a bucket — buckets are signatures assigned by precedence, so a bucket-5 ride may also carry a surcharge mismatch the ordering suppressed.

## 8. Maintaining this skill

Formulas and taxonomy in this file · mechanics, columns and gotchas in `references/mechanics.md` · numbers, tickets and sanity checks in `references/baselines.md`. Update the matching `assets/sql/` template in the same pass — drift between prose and SQL is the failure mode that matters. Note the date and source (SME, query ID, validation run) beside each change, and if a bucket definition or precedence changes, say so loudly: prior figures stop being comparable.

Known gaps: `MinFare` and `FixSpeedCap` absent from BI · no dropoff-pin-accuracy flag (wrong-dropoff cases land in bucket 8) · no Google/taximeter path-on-map fields · `ACTUALDISCRIMINATIONMULTIPLIER` unvalidated (use `DISCRIMINATIONMULTIPLIER`) · PriceCheck discounts not populated.

---
Locked 2026-08-03 · Snowflake-validated 2026-08-04 · taxonomy precedence revised 2026-08-10 · residual decomposition validated 2026-08-10.
