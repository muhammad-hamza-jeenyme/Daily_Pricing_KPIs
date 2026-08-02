# Alert rules — severity & thresholds

Status: **TBD** — agree after KPI catalogue exists.

## Severity levels

| Level | Intent | Slack behaviour (proposed) |
|-------|--------|----------------------------|
| **Warning** | Soft deviation; watch | Include in daily digest, lower urgency |
| **Alert** | Actionable pricing issue | Highlight in digest; tag owners if agreed |
| **Major shift** | Large / unusual movement | Top of digest; strong callout |

Exact % / absolute thresholds per KPI: **TBD**.

## Evaluation logic (proposed)

For each KPI on yesterday:

1. Compute DoD, WoW, MoM (MoM = vs 28 days prior).
2. Classify each window against thresholds.
3. Roll up to max severity for that KPI.
4. Post digest when any KPI ≥ Warning (or always post daily summary — product decision TBD).

## Quiet / suppress rules (TBD)

- Holidays / known events
- Incomplete data / late Snowflake freshness
- Cities with volume below minimum sample size

## Ownership

| Severity | Notify | Escalate |
|----------|--------|----------|
| Warning | Pricing channel | — |
| Alert | Pricing channel + owner | TBD |
| Major shift | Pricing channel + owner | TBD |
