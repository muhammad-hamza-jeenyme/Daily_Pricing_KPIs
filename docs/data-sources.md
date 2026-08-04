# Data sources — Snowflake

Status: **Validated** via MCP on 2026-08-04 (`docs/validation-run-2026-08-04.md`).

## Runtime

- Agent: Cursor Cloud Agent (planned 11:30 AM PKT)
- Access: Snowflake MCP `sql_exec_tool`
- Primary SQL: `sql/fare_integrity_daily_digest.sql`

## Objects

| Object | Role |
|--------|------|
| `JEENY_PROD.RIDE.DETAILS` | Boarded rides, `CREATEDDATE` (Saudi), surge/PD, area |
| `JEENY_PROD.RIDE.UPFRONT` | Scenario, ORIG/CHARGING fares, scaled distance, dropoff flag |
| `JEENY_PROD.RIDE.RECEIPTS` | Final `TOTALAMOUNTWITHTAX`, waiting, cancel, discount |
| `JEENY_PROD.PASSENGERS.PRICECHECKS` | PriceCheck `VALUE`, `VAT` (hailing), `SURCHARGE` (ex-VAT) |
| `JEENY_PROD.GENERAL.AREAS` | `country_code` (SA / JO) |

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
