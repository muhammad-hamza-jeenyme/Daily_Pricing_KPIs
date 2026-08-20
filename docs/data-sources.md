# Data sources — Snowflake

Status: **Validated** via MCP on 2026-08-04 (`docs/validation-run-2026-08-04.md`).

## Runtime

- Agent: Cursor Cloud Agent (**11:00 AM PKT**)
- Access: Snowflake MCP `sql_exec_tool`
- Primary SQL: `sql/fare_integrity_channel_summary.sql` (daily Pulsar; NET shocks)
- Headline: `sql/daily_price_shock_alert.sql`
- Spillover: `docs/payment-spillover-price-shocks.md`

## Objects

| Object | Role |
|--------|------|
| `JEENY_PROD.RIDE.DETAILS` | Boarded rides, `CREATEDDATE` (Saudi), surge/PD, area, `MODEOFPAYMENT`, `CARDFLAG`, `OUTSTANDINGBALANCE` |
| `JEENY_PROD.RIDE.UPFRONT` | Scenario, ORIG/CHARGING fares, scaled distance (`FIXEDSPEEDCAP`), WithinA max variance (`MAXWITHINMINUTESVARIANCE`), dropoff flag |
| `JEENY_PROD.RIDE.RECEIPTS` | Final `TOTALAMOUNTWITHTAX`, waiting, cancel (incl. spillover recovery), discount |
| `JEENY_PROD.PASSENGERS.PRICECHECKS` | PriceCheck `VALUE`, `VAT` (hailing), `SURCHARGE` (ex-VAT) |
| `JEENY_PROD.GENERAL.AREAS` | `country_code` (SA / JO) |
| `JEENY_PROD.PASSENGERS.TRANSACTIONS` | Wallet top-up on overpay / ride-change (investigation) |
| `JEENY_PROD.GENERAL.JTRANSACTION` | Card VOID / 2nd debit paths (investigation) |

## Join keys

- `DETAILS.RIDEID = UPFRONT.RIDEID = RECEIPTS.RIDEID = PRICECHECKS.RIDEID`
- `LOWER(PRICECHECKS.SERVICEFILTER) = LOWER(DETAILS.REQUEST_SERVICE)` — one row per ride
- `DETAILS.AREA_CODE = AREAS.AREA_CODE`

## Filters

- `DETAILS.BOARDED IS NOT NULL`
- `UPFRONT.ORIGINALESTIMATEFARE IS NOT NULL`
- `country_code IN ('SA','JO')`
- `CREATEDDATE >= CURRENT_DATE - 29 AND CREATEDDATE < CURRENT_DATE`

## Timezone

- `CREATEDDATE`: Saudi calendar date
- Snowflake `CURRENT_DATE` observed 2026-08-04 during validation → window 2026-07-06 … 2026-08-03

## Scenario casing (prod)

`withinA` | `withinB` | `beyondB`

**withinA** when either:
1. `ACTUALTIME * 60` ∈ `[TIMETHRESHHOLDSALOWVALUE, TIMETHRESHHOLDSAHIGHVALUE]`, or
2. `ACTUALTIME − APPLIEDESTIMATETIME ≤ MAXWITHINMINUTESVARIANCE` (minutes)
