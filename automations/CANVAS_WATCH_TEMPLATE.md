# Slack Canvas — detailed watches template

**Fixed Canvas (do not create a new one each day)**  
- ID: `F0BN0E7RJ31`  
- URL: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31

Title / top of canvas (date must be obvious):
```
# Pricing Fare Integrity Daily — {report_date}
Report date: {report_date}
```

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

Each run: read Canvas `F0BN0E7RJ31` for section IDs, then replace content with today’s watches (do not create a new canvas).

Canvas replace path (bot token `PULSAR_SLACK_BOT_TOKEN`):
1. `auth.test`
2. `canvases.sections.lookup` with `section_types: any_header` (also ok: `h1`/`h2`/`h3`)
3. Delete **one section per** `canvases.edit` call (`operation: delete`) — batch delete+insert in one request often returns `invalid_arguments`
4. Then `canvases.edit` `insert_at_start` with today’s markdown
5. Never use the Incoming Webhook for canvas edits

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
- Share Canvas link into the Pulsar channel summary footer:  
  https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31
- Webhook cannot edit Canvas — needs `PULSAR_SLACK_BOT_TOKEN` (or equivalent Slack bot with `canvases:write` + channel access).
- If Canvas update fails: still post the short Pulsar channel summary; note canvas update failed in one line (do not dump multi-KPI watches into the channel).
