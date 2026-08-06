# Slack Canvas — detailed watches template

Title: `Pricing Fare Integrity Daily — {report_date}`

Source SQL: `sql/fare_integrity_slack_rollup.sql` (8 major cities).  
DX style reference: channel Canvas docs (compact Watch / Alert sections per country).

Major shift / Watch rule: **yesterday > prior 7-day average**.

## Structure

1. Header: report date + short legend  
   `Watch = yesterday > prior 7d avg · d/d · w/w · m/m · vol`
2. **SA** section
   - **Watch** (and **Alerts** subheading only if any major shift)
   - One bullet per watchlist city with any flagged KPI
3. **JO** section — same

## Per-area line

```
{AREA} · {KPI} {yesterday}% vs7d {avg7}% ({vs7d_delta}pp) · d/d {dod}pp · w/w {wow}pp · m/m {mom}pp · vol {rides}
:mag: {short_hint}
```

Hints (pick one short phrase):
- `%increase_pricing` above 7d → `fare ↑ share elevated`
- `%decrease_pricing` above 7d → `fare ↓ share elevated`
- `%withinB` / `%beyondB` → `scenario mix shift`
- `%rounding` → `rounding share elevated`
- `avg_fare_diff` → `avg fare gap elevated`

## Rules

- Only list area × KPI where `major_shift_*` is true (Watch).
- If a country has zero watches: `No major shifts vs 7d avg.`
- Share Canvas link into the Pulsar channel summary footer.
- Webhook cannot create Canvas — needs `PULSAR_SLACK_BOT_TOKEN` (or equivalent Slack bot with `canvases:write` + channel access).
- If Canvas create fails: still post the short Pulsar channel summary; footer notes `Canvas: unavailable`.
