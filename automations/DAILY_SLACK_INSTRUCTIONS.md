# Slack bot instructions — daily fare-integrity report

Used by Cursor Cloud Automation. Post **only** to channel `C0BMWLMR03T`. Never list, read, or post to any other channel.

## Every run (11:30 AM PKT)

1. From repo `muhammad-hamza-jeenyme/Daily_Pricing_KPIs` on `main`, run Snowflake SQL in `sql/fare_integrity_slack_rollup.sql` (watchlist cities only).
2. Summarize **yesterday** for: RUH, JED, MAD, DMM, MEC, AMM, IRB, ZRQ.
3. Include DoD, WoW, MoM deltas and vs prior-7-day average for key KPIs (`pct_increase_pricing`, `pct_withinB`, `pct_beyondB`, `pct_rounding`, `pct_decrease_pricing`, `avg_fare_diff`).
4. **Major shifts:** any KPI where yesterday > prior 7d avg — list **Area_Code**, KPI name, yesterday value, 7d avg, and DoD/WoW/MoM deltas.
5. Optionally create/update a Slack canvas **in the same channel only** with the city table.
6. Send **one** daily message (and canvas link if created) via Slack **only** to `C0BMWLMR03T`.

## Hard constraints

- Slack destination is exclusively `C0BMWLMR03T`. Do not DM users. Do not post elsewhere.
- Token-efficient: use the rollup SQL, not ride-level dumps.
- If Snowflake fails, post a short failure notice to `C0BMWLMR03T` only.
- Do not invent thresholds beyond: major shift = yesterday > prior 7d average.
