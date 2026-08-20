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

Cumulative / Residual rates are **NET of spillover recovery**.

If none fire → write `_No 28d±2σ exceptions_`.

## Today’s section shape

```markdown
## YYYY-MM-DD (Weekday)

### Trend (country Total, last 3 runs → oldest) — NET shocks
SA Cumulative: t2 → t1 → **t0**
SA Residual:   t2 → t1 → **t0**
JO Cumulative: …
JO Residual:   …

Use country rows: `pct_cumulative_shock` / `pct_increase_pricing` = t0, `*_trend_t1`, `*_trend_t2`.

### Spillover monitor (not a shock)
SA recovery %: **x.x** · JO: **y.y** (`pct_spillover_recovery`)
Only call out if clearly elevated vs recent runs.

### Exceptions (28d mean + 2σ)
- `JED` · Residual fare increase % · **…** (avg28 … · σ … · thresh …)
- …

### Investigate today
1. **City · KPI** — why (one line)
2. Optional second lead

If no exceptions: `_No investigate leads — quiet day._`
```

## Do not put on canvas
- Channel tables / full KPI matrices  
- Definition glossaries / payment essays (link repo docs if needed)  
- Quiet KPIs that did not breach 28d+2σ  

## Quick defs (agent-only — do not paste onto canvas)
| KPI | Rule |
|-----|------|
| Cumulative / Residual | NET — exclude spillover recovery |
| Spillover recovery | prior `OUTSTANDINGBALANCE` matched by next-ride `CANCELLATIONFINE` (±0.02) |
| Spec | `docs/payment-spillover-price-shocks.md` |
