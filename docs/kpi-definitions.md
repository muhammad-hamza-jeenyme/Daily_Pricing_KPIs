# Pricing KPI definitions

Status: **v3 fare-integrity + discount exposure** — discount view added
2026-09-02. Existing fare-integrity KPIs remain unchanged.

## Comparison windows

| Window | Definition |
|--------|------------|
| **DoD** | Yesterday vs day before |
| **WoW** | Yesterday vs 7 days earlier |
| **MoM** | Yesterday vs **28 days before** |

`createddate` is Saudi calendar date. Agent runs **11:00 AM PKT**. Digest window = last 29 complete days (`createddate < CURRENT_DATE`).

## v1 catalogue — fare integrity

| KPI / dimension | Definition | Grain |
|-----------------|------------|-------|
| `ride_count` | Boarded rides with destination (ORIG estimate not null), SA+JO | day × area × scenario × issue_type |
| `issue_type` mix | matched / rounding / increase_non_issue / increase_pricing / decrease_pricing | same |
| `upfrontscenario` mix | withinA / withinB / beyondB share (prod casing) | day × area (+ rollup) |
| `sum_fare_diff` / `avg_fare_diff` | Normalized receipt − PriceCheck shown | same |
| `sum_residual` | Fare_Diff − non_issue (waiting+cancel) | same |
| `dropoff_not_at_dest_rides` | Dropoff ≠ destination | same |
| `scaled_distance_rides` | `SCALEDDISTANCE > 0` | day × area |
| `surge_mismatch_rides` | both non-null AND `ROUND(PC.SURGEMULTIPLIER,4) <> ROUND(Details.SURGEMULTIPLIER,4)` | day × area (+ channel city tables) |
| `pd_mismatch_rides` | both non-null AND `ROUND(PC.DISCRIMINATIONMULTIPLIER,4) <> ROUND(Details.DISCRIMINATIONMULTIPLIER,4)` | day × area (+ channel city tables) |
| `% rides with fare increase` / residual (channel) | `increase_pricing` only — residual after waiting/cancel; **excludes** spillover recovery legs | country / city |
| `Cumulative PriceShocks %` (channel) | `Fare_Diff > 0.01` any reason; **excludes** rounding **and** spillover recovery | country / city |
| `Spillover recovery %` (monitor) | next-ride cancel fine matching prior `OUTSTANDINGBALANCE` (±0.02); excluded from shock KPIs | country / city |
| `Rounding error %` (channel) | `0 < \|Fare_Diff\| ≤ 0.01` (tech bug) | country / city |

## Discount-exposure catalogue (post-discount)

Source: `JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS`, built by
`sql/bi_price_shock_discounts_daily.sql`.

| KPI / dimension | Definition | Grain |
|---|---|---|
| `discount_segment` | Six exclusive values: voucher/promo capped or percentage-bound, no source, no discount | day × country |
| `cap_bound_at_quote` | Percentage leg had already reached the program cap on quote base | day × country × segment |
| `net_fare_diff` | Charged net receipt − expected post-discount PriceCheck | ride input, aggregated daily |
| `d_discount` | Expected gross quote discount − actual gross final discount | ride input, aggregated daily |
| `net_shock_pct` | `net_fare_diff > 0.01`, excluding spillover recovery | day × country × segment |
| `gross_shock_pct` | Existing `fare_diff > 0.01`, excluding spillover recovery | same |
| `ride_share_pct` | Segment rides / all country rides | same |
| `gross_excess_amount` | Sum positive `fare_diff` on gross shocks | same, local currency |
| `net_excess_amount` | Sum positive `net_fare_diff` on net shocks | same, local currency |
| `absorption_pct` | `(gross excess − net excess) / gross excess × 100` | same |
| `promised_not_applied` | Valid single-code voucher at quote, actual gross discount ≤ 0.01 | day × country |

Interpretation of `d_discount`: negative = discount grew and absorbed part of
the overrun; approximately zero = capped/no buffer; positive = final discount
smaller than expected.

Do not replace the headline `fare_diff` KPIs with `net_fare_diff`. The headline
isolates pricing integrity; discount exposure is the passenger-experience
segment view. All new discount Slack/canvas analysis uses post-discount values.

## Formulas

See `docs/pricing-structure.md`,
`docs/price-shock-discounts-bi-handoff.md`,
`sql/priceshocks_daily_digest.sql` (active v1), and
`sql/priceshocks_daily_digest_v2.sql` (after BI cutover).
