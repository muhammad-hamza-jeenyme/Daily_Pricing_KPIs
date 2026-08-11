# Slack channel message template (Pulsar — short)

Style matches bizfin-bot daily report.  
**Channel KPIs:**
1. `% rides with fare increase` (`increase_pricing` only — residual after waiting/cancel; **not** all positive fare gaps)
2. **Surcharge mismatch** rides (withinA + dropoff at dest, PC vs Details surcharge)
3. **Pickup estimate mismatch** rides (PriceCheck pickup vs `ride_offered` > 100m)
4. **Surge mismatch** rides (`ROUND(PC.SURGEMULTIPLIER,4) <> ROUND(Details.SURGEMULTIPLIER,4)`)
5. **PD mismatch** rides (`ROUND(PC.DISCRIMINATIONMULTIPLIER,4) <> ROUND(Details.DISCRIMINATIONMULTIPLIER,4)`)

## Table formatting (required)

- Put each city table inside a Slack code fence (monospace).
- **Fixed-width columns** — pad every cell so headers and values line up vertically.
- Column order SA: `RUH | JED | MAD | DMM | MEC | Others | Total`
- Column order JO: `AMM | IRB | ZRQ | Others | Total`
- **Total** = country-level value for that metric (same as country headline), **not** a sum of city % rates.
  - For count tables: Total = country ride count for that mismatch (= sum of city buckets).
  - For `%inc` / `vs DoD`: Total = country `%` / country DoD pp.
- Right-align numbers inside each column width. Suggested widths: label `6`, cities `6`, Others `7`, Total `7`.

## Example shape

```text
:flag-sa: *SA Fare Increase % (August 10, 2026 | Monday):*

*% rides with fare increase:*
:warning: 17.03%  ·  DoD +1.00pp | WoW +0.45pp | MoM -0.55pp
• vs prior 7d avg 16.85%
• Rides 103,438

*Surcharge mismatch (withinA + at dest):*
1,814 rides (1.75%) · DoD +62 | WoW +53 | vs7d avg 1863

*Pickup mismatch (>100m vs offer):*
5 rides (0.00%) · DoD +1 | WoW -4 | vs7d avg 6

*Surge mismatch (PC vs Details):*
12 rides (0.01%) · DoD +2 | WoW -1 | vs7d avg 10

*PD mismatch (PC vs Details):*
8 rides (0.01%) · DoD 0 | WoW +1 | vs7d avg 7

*City-wise (% fare increase):*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
%inc   |  14.1 |  18.8 |  16.8 |  18.3 |  19.2 |   20.6 |   17.0
vs DoD |  +1.6 |  +0.4 |  -0.4 |  +1.6 |  +1.5 |   +1.5 |   +1.0
```

*City-wise (surcharge mismatch rides):*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
n      |   587 |   777 |   169 |    75 |    47 |    159 |   1814
```

*City-wise (pickup mismatch rides):*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
n      |     0 |     1 |     1 |     1 |     1 |      1 |      5
```

*City-wise (surge mismatch rides):*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
n      |     … |     … |     … |     … |     … |      … |      …
```

*City-wise (PD mismatch rides):*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
n      |     … |     … |     … |     … |     … |      … |      …
```

:flag-jo: *JO …* (same blocks; cities AMM | IRB | ZRQ | Others | Total)

:clipboard: *Detailed watches:* https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31
```

## Rules
- Keep channel short; put investigation detail on **Canvas**.
- Flag with :warning: only when yesterday count/rate **> prior 7d avg** (major shift).
- SQL: `sql/fare_integrity_channel_summary.sql`
- Never invent numbers — pad/format only what Snowflake returns.
