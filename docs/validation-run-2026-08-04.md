# Snowflake validation — 2026-08-04

Query: `sql/fare_integrity_daily_digest.sql` (rolled up by issue × scenario × country for token efficiency).  
MCP: `user-snowflake` / `sql_exec_tool`.  
Window: `createddate` **2026-07-06 → 2026-08-03** (`CURRENT_DATE` = 2026-08-04).

## Outcome

Query **succeeded**. Scenario values in prod: `withinA`, `withinB`, `beyondB` (not `BeyondB`).

## 29-day totals (SA + JO)

Approx **5.18M** boarded rides with destination in scope.

### By country × scenario × issue_type (ride_count)

| Country | Scenario | matched | rounding | increase_non_issue | increase_pricing | decrease_pricing |
|---------|----------|---------|----------|--------------------|------------------|------------------|
| JO | withinA | 1,631,732 | 25,969 | 262,056 | 86,346 | 83,719 |
| JO | withinB | 300 | 607 | 704 | 276,234 | 17,715 |
| JO | beyondB | 1,447 | 20 | 152 | 1,569 | 1,269 |
| SA | withinA | 1,415,057 | 64,831 | 662,794 | 99,862 | 121,127 |
| SA | withinB | 520 | 88 | 1,605 | 391,411 | 26,316 |
| SA | beyondB | 420 | 8 | 222 | 735 | 2,321 |

### Notes from run

- **withinB** is dominated by `increase_pricing` (expected: additional time path).
- **increase_non_issue** is large on withinA (waiting / prior cancel fine).
- **beyondB** is rare vs withinA/withinB.
- **Scaled distance** rides ≈ 0–16 over 29d (very rare).
- Surge/PD mismatches exist but are small vs volume (investigate later if rising).

## Yesterday (2026-08-03) — top areas by `increase_pricing` rides

| Area | Country | Rides | Sum fare_diff |
|------|---------|------:|--------------:|
| AMM | JO | 8,105 | 8,372 |
| JED | SA | 5,910 | 45,111 |
| RUH | SA | 5,504 | 36,235 |
| IRB | JO | 2,771 | 2,543 |
| ZRQ | JO | 2,094 | 1,806 |
| MAD | SA | 1,762 | 12,872 |
| DMM | SA | 1,152 | 7,856 |
| MEC | SA | 1,004 | 7,411 |

## Next

1. Add DoD/WoW/MoM rollup on this digest grain.
2. Define Slack alert thresholds (e.g. withinB % / increase_pricing rate by area).
3. Cloud Agent schedule **11:00 AM PKT** (`0 6 * * *` UTC).
