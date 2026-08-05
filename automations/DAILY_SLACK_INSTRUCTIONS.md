# Slack bot instructions — daily fare-integrity report

Used by Cursor Cloud Automation. Post **only** to channel `C0BMWLMR03T`. Never list, read, or post to any other channel.

## Required MCP tools

| Tool | Required | Purpose |
|------|----------|---------|
| Snowflake MCP (`sql_exec_tool`) | Preferred | Run `sql/fare_integrity_slack_rollup.sql` |
| Snowflake SQL API via env PAT | Fallback | If MCP missing, run the same SQL with `SNOWFLAKE_*` secrets (`/api/v2/statements`) |
| Slack post (`send_slack_message`) | **Yes** | Daily alert to `C0BMWLMR03T` |
| Slack Canvas create/update | Preferred | Detailed report in channel Canvas |

If both Snowflake MCP and SQL API fail, post a short failure notice to `C0BMWLMR03T` only. Do not invent KPI numbers.

## Every run (11:00 AM PKT / cron `0 6 * * *` UTC)

1. From repo `muhammad-hamza-jeenyme/Daily_Pricing_KPIs`, run Snowflake SQL in `sql/fare_integrity_slack_rollup.sql` (watchlist cities only).
2. Summarize **yesterday** for: RUH, JED, MAD, DMM, MEC (SA) and AMM, IRB, ZRQ (JO).
3. Include DoD, WoW, MoM deltas and vs prior-14-day average for key KPIs (`pct_increase_pricing`, `pct_decrease_pricing`, `pct_increase_non_issue`, `pct_withinB`, `pct_beyondB`, `pct_rounding`, `avg_fare_diff`).
4. **Watch section:** any KPI where yesterday > prior 14d avg — list **Area_Code**, KPI name, yesterday value, 14d avg, and DoD/WoW/MoM deltas.
5. Publish a **detailed report in the channel Canvas** (city table with all KPIs + comparisons). Link the Canvas from the daily Slack message. If Canvas API is unavailable, post the full table as a threaded reply titled "Detailed report (Canvas pending)" so members can still review it.
6. Send **one** daily summary message (with Canvas / detail link) via Slack **only** to `C0BMWLMR03T`.
7. Do not use em dashes in Slack copy.

## Slack message template

```text
Pricing fare-integrity digest — {report_date}
Cities: SA RUH/JED/MAD/DMM/MEC | JO AMM/IRB/ZRQ

## Snapshot
{one line per city: rides | %inc_pricing | %withinB | %beyondB | avg_fare_diff | DoD/WoW/MoM on %inc_pricing}

## Watch (yesterday > prior 14d avg)
{bullets: Area | KPI | yesterday | 14d avg | DoD | WoW | MoM}
(or "None today")

## Detailed report
Open the channel Canvas: {canvas_link_or_thread}
```

## Hard constraints

- Slack destination is exclusively `C0BMWLMR03T`. Do not DM users. Do not post elsewhere.
- Token-efficient: use the rollup SQL, not ride-level dumps.
- If Snowflake fails, post a short failure notice to `C0BMWLMR03T` only.
- Do not invent thresholds beyond: watch = yesterday > prior 14d average.
- Do not fabricate KPI values from stale validation snapshots.
