# Data sources — Snowflake

Status: updated 2026-08-31 — daily digests read `RIDE.PRICESHOCKS`.

## Runtime

- Agent: Cursor Cloud Agent (**11:00 AM PKT**)
- Access: Snowflake MCP `sql_exec_tool`
- **Primary (daily):** `JEENY_PROD.RIDE.PRICESHOCKS` via `sql/priceshocks_daily_digest.sql`
- Spec: `docs/priceshocks-table.md`
- Spillover logic (baked into BI table): `docs/payment-spillover-price-shocks.md`

## Objects

| Object | Role |
|--------|------|
| **`JEENY_PROD.RIDE.PRICESHOCKS`** | **Daily digest source** — CHANNEL / SCENARIO / CAUSE_MIX by city & country; refreshed by BI before 11:00 AM PKT |
| `JEENY_PROD.RIDE.DETAILS` | Boarded rides (upstream of BI table / debug) |
| `JEENY_PROD.RIDE.UPFRONT` | Scenario, ORIG estimate, variance caps (upstream / debug) |
| `JEENY_PROD.RIDE.RECEIPTS` | Final totals, waiting, cancel, discount (upstream / debug) |
| `JEENY_PROD.PASSENGERS.PRICECHECKS` | PriceCheck VALUE / VAT / SURCHARGE (upstream / debug) |
| `JEENY_PROD.GENERAL.AREAS` | `country_code` SA / JO |
| `JEENY_PROD.PASSENGERS.TRANSACTIONS` | Wallet investigation |
| `JEENY_PROD.GENERAL.JTRANSACTION` | Card VOID / 2nd debit investigation |

## Daily agent filters

- Report date = `CURRENT_DATE - 1`
- Require `MAX(PRICESHOCKS.RIDE_DATE) >= report_date` before posting
- Comparisons: DoD (−1d), WoW (−7d), MoM (−28d) on stored `PCT`

## Universe (encoded in BI table)

- `DETAILS.BOARDED IS NOT NULL`
- `UPFRONT.ORIGINALESTIMATEFARE IS NOT NULL`
- `country_code IN ('SA','JO')`

## Timezone

- `RIDE_DATE` / `CREATEDDATE`: Saudi calendar date
- Agent schedule: 11:00 AM PKT
