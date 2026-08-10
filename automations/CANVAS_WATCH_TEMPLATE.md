# Canvas template — Pricing fare-integrity watches

**Fixed channel canvas (update daily — do not create a new canvas):**  
- URL: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31  
- Canvas ID: `F0BN0E7RJ31`  

Style reference: https://easytaxime.slack.com/docs/T33U3F6CW/F0BL188MU3C

## Each run
1. Read canvas `F0BN0E7RJ31`.
2. Replace body with today’s report (**date at top**).
3. Link same URL in Pulsar channel footer.

## Structure

```markdown
# :bar_chart: Pricing Fare Integrity Daily — YYYY-MM-DD

**Report date:** YYYY-MM-DD

**N** watches · themes: Fare increase %, Surcharge mismatch, Pickup estimate mismatch (>100m)

---

## :flag-sa: Saudi Arabia — X watches

### :eyes: Watch

`RUH`

* **% rides with fare increase**: **13.3** vs 13.9 avg
    * d/d … · w/w … · m/m … · vol …
    * :mag: Residual fare increase after waiting/cancel.

* **Surcharge mismatch rides**: **40** vs 28 avg (withinA + dropoff at dest)
    * d/d … · w/w … · m/m …
    * :mag: PC.SURCHARGE ≠ Details.SURCHARGE + INTERCITYSURCHARGE despite withinA/at-dest.

* **Pickup mismatch rides (>100m)**: **12** vs 9 avg
    * d/d … · w/w … · m/m …
    * :mag: PriceCheck pickup vs first ride_offered location > 100m — Google estimate used wrong pickup.

### :rotating_light: Alerts

(Only if yesterday > prior 7d avg)

---

## :flag-jo: Jordan — Y watches
…same…

---

> Target date: **YYYY-MM-DD** · Baseline: prior 7 complete days · SQL: fare_integrity_channel_summary.sql
```

## KPI definitions for watches
| Watch | Definition |
|-------|------------|
| Fare increase % | `increase_pricing` share |
| Surcharge mismatch | withinA + dropoff at dest AND `(rd.SURCHARGE + rd.INTERCITYSURCHARGE) != pc.SURCHARGE` |
| Pickup mismatch | ST_DISTANCE(PC pickup, first `ride_offered` lat/lng) > 100m |
