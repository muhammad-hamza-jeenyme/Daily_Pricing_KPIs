# Canvas template — Pricing fare-integrity watches

**Fixed channel canvas (update daily — do not create a new canvas):**  
- URL: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31  
- Canvas ID: `F0BN0E7RJ31`  
- This is **not** a secret — put it in Agent Instructions / this file only.

Style reference (DX daily):  
https://easytaxime.slack.com/docs/T33U3F6CW/F0BL188MU3C

## Each run
1. `slack_read_canvas` on `F0BN0E7RJ31` to get fresh `section_id_mapping`.
2. Replace body with today’s report (date clearly at the top).
3. Link this same URL in the Pulsar channel message footer.

## Required top-of-canvas date

Title / first heading must include the report date, e.g.:

`Pricing Fare Integrity Daily — 2026-08-05`  
and in the body: `Report date: ![](slack_date:2026-08-05)` (or bold `**2026-08-05**` if date chips unavailable).

## Structure to write into `F0BN0E7RJ31`

```markdown
# :bar_chart: Pricing Fare Integrity Daily — YYYY-MM-DD

**Report date:** YYYY-MM-DD (weekday)

**N** watches · **M** areas · KPI focus: % rides with fare increase (`increase_pricing`) and related fare-integrity metrics

---

## :flag-sa: Saudi Arabia — X watches

### :eyes: Watch

`RUH`

* **% rides with fare increase**: **13.3** vs 13.9 avg (↓ vs baseline)
    * d/d -0.3pp · w/w -0.2pp · m/m -4.5pp · vol 41,485
    * :mag: Check dropoff≠dest, withinB share, surcharge path.

### :rotating_light: Alerts

(Only major shifts: yesterday > prior 7d avg)

---

## :flag-jo: Jordan — Y watches

### :eyes: Watch
…

### :rotating_light: Alerts
…

---

> Target date: **YYYY-MM-DD** · Baseline: prior 7 complete days · Comparison: d/d, w/w, m/m · Channel: % fare increase summary only
```

## Watch / Alert rules
- Group by country, then by `` `AREA_CODE` ``.
- Each item: **KPI**: **yesterday** vs **7d avg**.
- Sub-bullet: `d/d · w/w · m/m · vol {rides}`
- Sub-bullet: `:mag:` short Pricing hint.
- Canvas KPIs: `%increase_pricing`, `%decrease_pricing`, `%withinB`, `%beyondB`, `%rounding`, `avg_fare_diff`, scaled-distance if > 0.
- If Canvas update fails: keep short channel message; one-line note that canvas update failed.
