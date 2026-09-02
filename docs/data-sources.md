# Data sources — Snowflake

Status: updated 2026-09-02 — v2 adds post-discount facts after BI cutover.

## Runtime

- Agent: Cursor Cloud Agent (**11:00 AM PKT**)
- Access: Snowflake MCP `sql_exec_tool`
- **Primary fare integrity:** `JEENY_PROD.RIDE.PRICESHOCKS`
- **Primary discount exposure:** `JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS`
- **v2 consumer after BI cutover:** `sql/priceshocks_daily_digest_v2.sql`
- Specs: `docs/priceshocks-table.md` and
  `docs/price-shock-discounts-bi-handoff.md`
- Spillover logic (baked into BI table): `docs/payment-spillover-price-shocks.md`

## Objects

| Object | Role |
|--------|------|
| **`JEENY_PROD.RIDE.PRICESHOCKS`** | **Daily digest source** — CHANNEL / SCENARIO / CAUSE_MIX by city & country; refreshed by BI before 11:00 AM PKT |
| **`JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS`** | **Post-discount source** — discount segments, gross/net passenger impact, cap exposure, regression gates |
| `JEENY_PROD.RIDE.DETAILS` | Boarded rides (upstream of BI table / debug) |
| `JEENY_PROD.RIDE.UPFRONT` | Scenario, ORIG estimate, variance caps (upstream / debug) |
| `JEENY_PROD.RIDE.RECEIPTS` | Final totals, waiting, cancel, discount (upstream / debug) |
| `JEENY_PROD.PASSENGERS.PRICECHECKS` | PriceCheck VALUE / VAT / SURCHARGE (upstream / debug) |
| `JEENY_PROD.PASSENGERS.PRICECHECKKAFKAWITHPROMO` | Quote voucher validity, percentage/fixed value, VAT-inclusive cap; aggregate to `TRACEID` |
| `JEENY_PROD.PASSENGERS.PROMOTIONENGINE` | Automatic discount ride link; rate/cap inferred from trailing 7-day final behaviour |
| `JEENY_PROD.PASSENGERS.SAVINGS` | Cashback ledger only — never include in fare comparison |
| `JEENY_PROD.GENERAL.AREAS` | `country_code` SA / JO |
| `JEENY_PROD.PASSENGERS.TRANSACTIONS` | Wallet investigation |
| `JEENY_PROD.GENERAL.JTRANSACTION` | Card VOID / 2nd debit investigation |

## Daily agent filters

- Report date = `CURRENT_DATE - 1`
- Require both BI tables through `report_date` and zero failed discount gates
- Comparisons: DoD (−1d), WoW (−7d), MoM (−28d) on stored `PCT`
- Discount comparisons also include cap-bound ride share, post-discount shock
  rate, and average `d_discount`

## Universe (encoded in BI table)

- `DETAILS.BOARDED IS NOT NULL`
- `UPFRONT.ORIGINALESTIMATEFARE IS NOT NULL`
- `country_code IN ('SA','JO')`

## Timezone

- `RIDE_DATE` / `CREATEDDATE`: Saudi calendar date
- Agent schedule: 11:00 AM PKT
