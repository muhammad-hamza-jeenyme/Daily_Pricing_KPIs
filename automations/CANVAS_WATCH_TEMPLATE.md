# Canvas template — Pricing fare-integrity (exception digest)

**Fixed canvas:** `F0BN0E7RJ31` — https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31

## Retention
Keep **current run + previous 2 runs only** (max 3 dated `##` sections). Drop older.

## Each run
1. Read canvas.
2. Build today’s section from SQL flags + country trend columns.
3. Prepend today; keep only newest 3 sections.
4. Stable title at top: `# Pricing Fare Integrity — watches`
5. **No definitions, essays, or full city matrices** on canvas.

## Exception rule (hard)
List a KPI×city (or country Total) **only if** SQL `exception_28d_2sd_* = TRUE`:

`yesterday_rate > avg28 + 2 * sd28`  
(baseline = 28 complete days ending the day before report date; sample stddev)

If none fire → write `_No 28d±2σ exceptions_`.

## Today’s section shape

```markdown
## YYYY-MM-DD (Weekday)

### Trend (country Total, last 3 runs → oldest)
SA Cumulative: t2 → t1 → **t0**   e.g. `41.8 → 42.1 → **43.9**`
SA Residual:   t2 → t1 → **t0**
JO Cumulative: …
JO Residual:   …

Use country rows: `pct_*` = t0, `*_trend_t1`, `*_trend_t2`.
Optional text sparkline: ▁▂▃▄▅▆▇ from the three values (min–max scaled).

### Exceptions (28d mean + 2σ)
- `JED` · Residual fare increase % · **18.8** (avg28 16.1 · σ 0.9 · thresh 17.9)
- `SA Total` · Surcharge mismatch % · …

### Investigate today
1. **JED · Residual** — breached 28d+2σ; DoD +x.xpp; check withinA+dest residual / surcharge if co-moving
2. Optional second lead only if a clearly distinct second exception

If no exceptions: `_No investigate leads — quiet day._`
```

## Do not put on canvas
- Channel tables / full KPI matrices  
- Definition glossaries  
- Quiet KPIs that did not breach 28d+2σ  
