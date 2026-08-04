# Alert rules — severity & thresholds

Status: **Draft** — wire after DoD/WoW/MoM rollup on digest.

## Severity levels

| Level | Intent | Slack behaviour (proposed) |
|-------|--------|----------------------------|
| **Warning** | Soft deviation; watch | Include in daily digest |
| **Alert** | Actionable pricing issue | Highlight; tag owners if agreed |
| **Major shift** | Large / unusual movement | Top of digest |

## Candidate metrics (from validation 2026-08-04)

Thresholds TBD — start from yesterday vs −1d / −7d / −28d on:

- `% increase_pricing` by area
- `% withinB` by area
- `avg_fare_diff` / `sum_residual` for `increase_pricing`
- `rounding` rate (bug watch)
- `scaled_distance_rides` by area (spoofing watch)
- surge / PD mismatch counts

## Evaluation logic (proposed)

1. Run `sql/fare_integrity_daily_digest.sql`
2. Pivot yesterday vs DoD/WoW/MoM baselines
3. Classify severity per metric/area
4. Post Slack digest

## Ownership

| Severity | Notify |
|----------|--------|
| Warning / Alert / Major shift | Pricing Slack channel (TBD) |
