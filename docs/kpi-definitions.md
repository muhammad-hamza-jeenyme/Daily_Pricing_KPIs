# Pricing KPI definitions

Status: **Draft scaffold** — metrics TBD after pricing structure is documented.

## Comparison windows

| Window | Definition |
|--------|------------|
| **DoD** | Yesterday vs prior day (exact rule TBD) |
| **WoW** | Yesterday vs ~7 days earlier (weekday alignment TBD) |
| **MoM** | Yesterday vs **28 days before** |

Reporting day = **yesterday** relative to the 11:30 AM PKT Cloud Agent run (confirm timezone cutover with data team).

## KPI catalogue

| KPI | Definition / formula | Grain | Source (Snowflake) | Why it matters | Status |
|-----|----------------------|-------|--------------------|----------------|--------|
| _TBD_ | | | | | pending |

## Notes

- Add only KPIs Pricing can act on or must monitor for health.
- Each KPI needs clear numerator/denominator and null/zero handling.
- Prefer metrics available by the morning run (freshness SLA TBD).
