# Canvas template — Pricing fare-integrity watches

**Fixed channel canvas (prepend daily — keep history):**  
- URL: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31  
- Canvas ID: `F0BN0E7RJ31`  

Style reference (dated sections stacked): VoC-style canvas with newest day on top, older days below for scroll-back.

## Each run (history-preserving)

1. Read canvas `F0BN0E7RJ31` (full current body).
2. Build **today’s dated section** (structure below).
3. **Prepend** today’s section at the top of the canvas body.
4. **Keep all prior dated sections** below unchanged — do **not** replace or delete previous days.
5. Optional: keep a one-line title at the very top: `# Pricing Fare Integrity Daily` (stable; do not wipe history under it).
6. Link same URL in Pulsar channel footer.

**Never** overwrite the whole canvas with only today. If read fails, still post the channel message; note canvas error in one line.

## Structure for today’s section (prepend this block)

```markdown
## :bar_chart: YYYY-MM-DD (Weekday)

**N** watches · themes: Fare increase %, Surcharge / Pickup / Surge / PD mismatch

### :flag-sa: Saudi Arabia — X watches

#### :eyes: Watch

`RUH`

* **% rides with fare increase**: **13.3** vs 13.9 avg
    * d/d … · w/w … · m/m … · vol …
    * :mag: Residual fare increase after waiting/cancel (`increase_pricing` only).

* **Surcharge mismatch rides**: **40** vs 28 avg (withinA + dropoff at dest)
    * d/d … · w/w … · m/m …
    * :mag: PC.SURCHARGE ≠ Details.SURCHARGE + INTERCITYSURCHARGE despite withinA/at-dest.

* **Pickup mismatch rides (>100m)**: **12** vs 9 avg
    * d/d … · w/w … · m/m …
    * :mag: PriceCheck pickup vs first ride_offered location > 100m.

* **Surge mismatch rides**: **3** vs 2 avg
    * d/d … · w/w … · m/m …
    * :mag: PC.SURGEMULTIPLIER ≠ Details.SURGEMULTIPLIER.

* **PD mismatch rides**: **1** vs 1 avg
    * d/d … · w/w … · m/m …
    * :mag: PC.DISCRIMINATIONMULTIPLIER ≠ Details.DISCRIMINATIONMULTIPLIER.

#### :rotating_light: Alerts

(Only if yesterday > prior 7d avg)

---

### :flag-jo: Jordan — Y watches
…same…

---

> Target date: **YYYY-MM-DD** · Baseline: prior 7 complete days · SQL: fare_integrity_channel_summary.sql

---
```

After today’s block, the previous days’ `## :bar_chart: …` sections remain (newest → oldest when scrolling down).

## KPI definitions for watches
| Watch | Definition |
|-------|------------|
| Fare increase % | `increase_pricing` share only (not `increase_non_issue`) |
| Surcharge mismatch | withinA + dropoff at dest AND `(rd.SURCHARGE + rd.INTERCITYSURCHARGE) != pc.SURCHARGE` |
| Pickup mismatch | ST_DISTANCE(PC pickup, first `ride_offered` lat/lng) > 100m |
| Surge mismatch | both non-null AND `ROUND(pc.SURGEMULTIPLIER,4) <> ROUND(rd.SURGEMULTIPLIER,4)` |
| PD mismatch | both non-null AND `ROUND(pc.DISCRIMINATIONMULTIPLIER,4) <> ROUND(rd.DISCRIMINATIONMULTIPLIER,4)` |
