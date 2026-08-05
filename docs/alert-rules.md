# Alert rules — severity & thresholds

Status: **v1 decisions locked** (2026-08-04).

## Slack

| Item | Value |
|------|-------|
| Channel ID | `C0BMWLMR03T` |
| Cadence | Daily report + watch callouts at **11:00 AM PKT** |
| Runner | **Cursor Cloud Agent / Automation** (must not depend on laptop) |
| Poster | **Pulsar** Incoming Webhook only (not Cursor Slack send) |

## In-scope cities (major markets)

Fixed watchlist (top boarded volume):

| Country | Area codes |
|---------|------------|
| SA | `RUH`, `JED`, `MAD`, `DMM`, `MEC` |
| JO | `AMM`, `IRB`, `ZRQ` |

Only these 8 areas appear in Slack alerts / daily report (full digest SQL may still compute all areas for diagnostics).

## KPIs monitored (per area, yesterday)

Rates / levels derived from `sql/fare_integrity_daily_digest.sql`:

| KPI | Definition |
|-----|------------|
| `pct_increase_pricing` | `increase_pricing` rides / total rides |
| `pct_decrease_pricing` | `decrease_pricing` rides / total rides |
| `pct_withinB` | withinB rides / total rides |
| `pct_beyondB` | beyondB rides / total rides |
| `pct_rounding` | rounding rides / total rides |
| `pct_increase_non_issue` | increase_non_issue / total |
| `avg_fare_diff` | avg fare_diff (all issue types or pricing-only — report both if useful) |
| `scaled_distance_rides` | count where scaled distance used |

## Comparisons

| Window | Definition |
|--------|------------|
| **DoD** | Yesterday vs day before |
| **WoW** | Yesterday vs 7 days earlier |
| **MoM** | Yesterday vs **28 days** earlier |
| **vs 14d avg** | Yesterday vs **average of the prior 14 complete days** (`yesterday-14` … `yesterday-1`) |

## Watch rule (v1)

Flag **watch** for an area + KPI when:

`yesterday_value > avg(prior_14_complete_days)`

Slack must name the **Area_Code**, KPI, yesterday value, 14d avg, and optionally DoD/WoW/MoM deltas.

> No extra % buffer yet — any increase above the 14d average counts. Tighten later if noisy.

## Message shape (proposed)

1. **Daily report** — always for the 8 cities: totals + issue mix + scenario mix + DoD/WoW/MoM on key rates.
2. **Watch** — bullet list of area × KPI where yesterday > 14d avg (and show WoW/MoM if also elevated).
3. **Detailed report** — channel Canvas (fallback: Pulsar follow-up message if Canvas API unavailable).

## Severity (roll-up)

| Level | When |
|-------|------|
| Daily digest | Always post |
| Watch | Any KPI above 14d avg for a watchlist city |
| Alert / Warning tiers | TBD once we see noise (e.g. only if also WoW ↑ and volume ≥ N) |

## Ownership

Pricing Slack channel `C0BMWLMR03T`.
