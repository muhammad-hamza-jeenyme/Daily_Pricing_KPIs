# Jeeny Pricing — Snowflake tables, joins & KPI map

**Audience:** Pricing / Analytics knowledge-share  
**Scope:** Fare-integrity v1 (PriceCheck vs Receipts)  
**Database:** `JEENY_PROD`  
**Status:** Locked 2026-08-03 · Snowflake-validated 2026-08-04  
**Canonical SQL:** `sql/fare_integrity_daily_digest.sql`

---

## 1. Mission (one line)

Compare **PriceCheck shown fare** to **Receipts normalized fare** on boarded rides with destination; classify gaps into **issue types**; split by **upfront scenario** (`withinA` / `withinB` / `beyondB`).

Journey: `PriceCheck → Request → Accept → Board → Finish`

Universe:

- `RIDE.DETAILS.BOARDED IS NOT NULL`
- `RIDE.UPFRONT.ORIGINALESTIMATEFARE IS NOT NULL` (destination selected)
- `GENERAL.AREAS.COUNTRY_CODE IN ('SA','JO')`
- Date: `DETAILS.CREATEDDATE` (Saudi calendar); digest = last **29** complete days

Digest grain: **day × AREA_CODE × UPFRONTSCENARIO × issue_type**

---

## 2. Objects overview

| Object | Schema | Grain / identifier | Role in pricing |
|--------|--------|--------------------|-----------------|
| `AREAS` | `GENERAL` | 1 row / `AREA_CODE` | Country (SA VAT vs JO); area dimension |
| `DETAILS` | `RIDE` | 1 row / `RIDEID` | Ride spine, boarded, service, surge/PD |
| `UPFRONT` | `RIDE` | 1 row / `RIDEID` | Scenario, estimates, scaled distance, dropoff flag |
| `RECEIPTS` | `RIDE` | 1 row / `RIDEID` | Final charged total + waiting/cancel/discount |
| `PRICECHECKS` | `PASSENGERS` | Multi-row per quote session; link via `RIDEID` | Shown fare: `VALUE`, `VAT` (hailing), `SURCHARGE` (ex-VAT) |

---

## 3. How to join

```
GENERAL.AREAS          RIDE.DETAILS          RIDE.UPFRONT
     │                      │                      │
     │ AREA_CODE            │ RIDEID ──────────────┤
     └──────────────────────┤                      │
                            │ RIDEID ──────────────┼── RIDE.RECEIPTS
                            │                      │
                            │ RIDEID               │
                            │ + LOWER(SERVICEFILTER)
                            │   = LOWER(REQUEST_SERVICE)
                            └──────────────────────┴── PASSENGERS.PRICECHECKS
```

| Join | Keys | Notes |
|------|------|-------|
| Areas → Details | `AREA_CODE` | Filter `country_code IN ('SA','JO')` |
| Details → Upfront | `RIDEID` | 1:1 when upfront exists |
| Details → Receipts | `RIDEID` | 1:1 when receipt exists |
| Details → PriceChecks | `RIDEID` **and** `LOWER(pc.SERVICEFILTER) = LOWER(rd.REQUEST_SERVICE)` | PriceChecks is **not** 1 row per ride — many service quotes per session; always filter by service |

---

## 4. Columns used (fare-integrity)

### 4.1 `JEENY_PROD.RIDE.DETAILS`

| Column | Identifier role | Use |
|--------|-----------------|-----|
| `RIDEID` | PK | Join spine |
| `CREATEDDATE` | Date dim | Day grain (Saudi) |
| `AREA_CODE` | FK → Areas | Area grain |
| `BOARDED` | Lifecycle | Universe: not null |
| `REQUEST_SERVICE` | Service | Match PriceCheck `SERVICEFILTER` |
| `SURGEMULTIPLIER` | Pricing | vs PC → `surge_mismatch` |
| `DISCRIMINATIONMULTIPLIER` | Pricing | vs PC → `pd_mismatch` |

### 4.2 `JEENY_PROD.RIDE.UPFRONT`

| Column | Use |
|--------|-----|
| `RIDEID` | PK / join |
| `UPFRONTSCENARIO` | `withinA` \| `withinB` \| `beyondB` (prod casing) |
| `ORIGINALESTIMATEFARE` | Universe: not null = had destination |
| `DROPOFFATDESTINATION` | `dropoff_not_at_dest` when false |
| `SCALEDDISTANCE` | `scaled_distance_rides` when > 0 |
| `FIXEDSPEEDCAP` | Speed used with `ACTUALTIME` to compute `SCALEDDISTANCE` when scaled distance applies |
| `MAXWITHINMINUTESVARIANCE` | Max WithinA allowance (minutes); see scenario rule below |
| `CHARGINGFARE` | **Not** used for primary compare (incomplete vs receipt) |
| `ACTUALTIME`, `APPLIEDESTIMATETIME`, `TIMETHRESHHOLDS*` | Explain scenario bands |

**Units:** `ACTUALTIME` / `APPLIEDESTIMATETIME` / `MAXWITHINMINUTESVARIANCE` = **minutes**; `TIMETHRESHHOLDS*VALUE` = **seconds**; percent columns = percentage points (e.g. 22 = +22%).

### 4.3 `JEENY_PROD.PASSENGERS.PRICECHECKS`

| Column | Locked meaning |
|--------|----------------|
| `RIDEID` | Link when quote converted |
| `SERVICEFILTER` | Match `DETAILS.REQUEST_SERVICE` (case-insensitive) |
| `VALUE` | Quoted fare incl. SA VAT when applicable; equals `ORIGINALESTIMATEFARE` |
| `VAT` | **Not** SA ride VAT — equals `Receipts.RIDEHAILINGSURCHARGE + VATONRIDEHAILINGSURCHARGE` |
| `SURCHARGE` | Ex-VAT at PriceCheck; gross = `ROUND(×1.15 SA / ×1.0 JO, 2)` |
| `BASEFARE` | Taximeter output (context) |
| `SURGEMULTIPLIER` / `DISCRIMINATIONMULTIPLIER` | Compare to Details |
| `MINIMUMFARE` | **Do not** use as MinFare — MinFare not in BI; use stored `VALUE` |

Session identifiers (not required for digest): `UNIQUEID`, `PRICECHECKSUNIQUEID`, `TRACEID`, `PASSENGERID`.

### 4.4 `JEENY_PROD.RIDE.RECEIPTS`

| Column | Use |
|--------|-----|
| `RIDEID` | PK / join |
| `TOTALAMOUNTWITHTAX` | Core of normalized receipt |
| `DISCOUNT` + `VATONDISCOUNT` | Add back (promo must not look like a fare decrease) |
| `WAITINGCHARGES` + `VATONWAITINGCHARGES` | Non-issue |
| `CANCELLATIONFINE` + `VATONCANCELLATIONFINE` | Non-issue |
| `RIDEHAILINGSURCHARGE` + `VATONRIDEHAILINGSURCHARGE` | Equals PC.`VAT` (validated) |

Ignore `OUTSTANDINGBALANCE` for this compare.

### 4.5 `JEENY_PROD.GENERAL.AREAS`

| Column | Use |
|--------|-----|
| `AREA_CODE` | PK; join + digest dimension |
| `COUNTRY_CODE` | SA / JO filter; surcharge VAT factor |
| `AREA_NAME`, `COUNTRY_NAME` | Labels |

---

## 5. Locked fare formulas

```
PC_Surcharge_Gross = ROUND(SURCHARGE × IFF(country = 'SA', 1.15, 1.0), 2)
PriceCheck_Shown   = VALUE + VAT + PC_Surcharge_Gross
Normalized_Receipt = TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT

Fare_Diff  = Normalized_Receipt − PriceCheck_Shown
Non_Issue  = waiting(+VAT) + cancellation_fine(+VAT)
Residual   = Fare_Diff − Non_Issue
```

**Why not `Upfront.CHARGINGFARE`?** It excludes hailing, waiting, cancel fine, discount, etc. Receipts are the passenger-facing charged total.

Surcharge can legitimately differ PriceCheck vs end-of-ride when **dropoff ≠ destination** (re-Google); that gap flows into `increase_pricing` / `decrease_pricing` via `Fare_Diff`.

---

## 6. `issue_type` classification

| Condition | `issue_type` | Meaning |
|-----------|--------------|---------|
| `Fare_Diff = 0` | `matched` | Exact match |
| `0 < \|Fare_Diff\| ≤ 0.01` | `rounding` | Penny noise |
| `Fare_Diff > 0.01` and `Residual ≤ 0.01` | `increase_non_issue` | Higher charge explained by waiting/cancel |
| `Fare_Diff > 0.01` and `Residual > 0.01` | `increase_pricing` | True price shock / pricing experience |
| `Fare_Diff < -0.01` | `decrease_pricing` | Charged less than shown |

---

## 7. Upfront scenarios

| Scenario | Meaning |
|----------|---------|
| **withinA** | **Either** (1) `ACTUALTIME * 60` ∈ `[TIMETHRESHHOLDSALOWVALUE, TIMETHRESHHOLDSAHIGHVALUE]`, **or** (2) `ACTUALTIME − APPLIEDESTIMATETIME ≤ MAXWITHINMINUTESVARIANCE`. A-low often ≈ 0 → finishing early is usually withinA. Can still increase if dropoff ≠ dest. |
| **withinB** | Outside A, inside B. Additional-time path; validation shows this is dominated by `increase_pricing`. |
| **beyondB** | Outside B — rare (B upper bound often very high). |

Charging inputs (withinB / beyondB) depend on AD vs ED and speed-in-limit vs scaled distance. See `docs/pricing-structure.md`.

---

## 8. Digest KPIs and relationships

| KPI | Calculation | Built from |
|-----|-------------|------------|
| `ride_count` | `COUNT(*)` | Join + universe filters |
| `sum_fare_diff` / `avg_fare_diff` | SUM/AVG of Fare_Diff | PC shown + normalized receipt |
| `sum_residual` / `avg_residual` | SUM/AVG of Residual | Fare_Diff − Non_Issue |
| `sum_non_issue` | SUM(waiting + cancel ± VAT) | Receipts |
| `dropoff_not_at_dest_rides` | Count dropoff ≠ dest | Upfront |
| `scaled_distance_rides` | Count `SCALEDDISTANCE > 0` | Upfront (rare) |
| `surge_mismatch_rides` | PC surge ≠ Details surge | PriceChecks + Details |
| `pd_mismatch_rides` | PC PD ≠ Details PD | PriceChecks + Details |
| `pct_increase_pricing` | increase_pricing / total | issue_type mix |
| `pct_decrease_pricing` | decrease_pricing / total | issue_type mix |
| `pct_withinB` / `pct_beyondB` | scenario / total | UPFRONTSCENARIO mix |
| `pct_increase_non_issue` | increase_non_issue / total | issue_type mix |

### How they relate (dependency tree)

```
PriceCheck_Shown ──┐
                   ├── Fare_Diff ──┬── issue_type (matched / rounding / …)
Normalized_Receipt ┘               │
                                   ├── residual = Fare_Diff − Non_Issue
Non_Issue (wait+cancel) ───────────┘
                                   │
UPFRONTSCENARIO ───────────────────┼── scenario mix KPIs
issue_type counts ─────────────────┼── pct_* rates for Slack
ride_count ────────────────────────┘
```

### Comparison windows (alerts)

| Window | Definition |
|--------|------------|
| **DoD** | Yesterday vs day before |
| **WoW** | Yesterday vs 7 days earlier |
| **MoM** | Yesterday vs **28 days** before (not calendar month) |
| **vs 7d avg** | Yesterday vs avg of prior 7 complete days → **major shift** if yesterday > 7d avg |

Slack watchlist: `RUH`, `JED`, `MAD`, `DMM`, `MEC` (SA) · `AMM`, `IRB`, `ZRQ` (JO). Channel: `C0BMWLMR03T`. Spec: `docs/alert-rules.md`.

---

## 9. Validation snapshot (2026-08-04)

- Query succeeded on Snowflake MCP; ~**5.18M** rides in 29-day window.
- Prod scenario casing: `withinA` | `withinB` | `beyondB`.
- **withinB** dominated by `increase_pricing` (expected).
- **increase_non_issue** large on withinA (waiting / prior cancel).
- **beyondB** rare; scaled-distance rides very rare (≈0–16 / 29d).

Details: `docs/validation-run-2026-08-04.md`.

---

## 10. Do / don’t

| Do | Don’t |
|----|-------|
| Use Receipts for charged total | Use `Upfront.CHARGINGFARE` as primary compare |
| Hardcode SA surcharge VAT ×1.15, JO ×1.0 | Infer VAT from VALUE ratios |
| Match PriceCheck by `SERVICEFILTER` = `REQUEST_SERVICE` | Join PriceChecks on `RIDEID` alone |
| Treat PC.`VAT` as hailing | Treat PC.`VAT` as SA ride VAT |
| Use stored `VALUE` | Invent MinFare from `MINIMUMFARE` |

---

## 11. Repo pointers

| Doc / file | Content |
|------------|---------|
| `docs/pricing-structure.md` | Full pricing mechanics |
| `docs/kpi-definitions.md` | KPI catalogue |
| `docs/data-sources.md` | Objects + joins |
| `docs/alert-rules.md` | Slack thresholds / cities |
| `sql/fare_integrity_daily_digest.sql` | Production aggregate query |
| `tables schema/draft SQL.sql` | Ride-level debug |
| `memory/PROJECT_CONTEXT.md` | Session memory |

BI catalog (full column dictionaries):  
`product-docs-main/bi-catalog/docs/` → Ride (`Details`, `Upfront`, `Receipts`), Passenger (`Pricechecks`), General (`Areas`).
