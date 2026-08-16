# Slack channel message template (Pulsar — tables only)

**No prose before tables.** Country header + table title + monospace table only.  
Footer: canvas link once at the end.

## Channel KPI tables (this order)

1. **Cumulative PriceShocks %** — `Fare_Diff > 0.01` (waiting, cancel, additional time, residual pricing, tech bugs). **Excludes** rounding (`|Fare_Diff| ≤ 0.01`).
2. **Residual fare increase %** — `increase_pricing` only (`Fare_Diff > 0.01` AND residual after waiting/cancel `> 0.01`).
3. **Rounding error %** — `0 < |Fare_Diff| ≤ 0.01` (tech bug / penny noise).
4. **Surcharge mismatch %** — withinA + dropoff at dest, PC vs Details surcharge.
5. **Pickup mismatch %** — PC pickup vs `ride_offered` > 100m.
6. **Surge mismatch %** — `ROUND(PC.SURGEMULTIPLIER,4) <> ROUND(Details.SURGEMULTIPLIER,4)`.
7. **PD mismatch %** — `ROUND(PC.DISCRIMINATIONMULTIPLIER,4) <> ROUND(Details.DISCRIMINATIONMULTIPLIER,4)`.

## Table formatting (required)

- Slack code fence (monospace); **fixed-width** padded cells.
- SA columns: `RUH | JED | MAD | DMM | MEC | Others | Total`
- JO columns: `AMM | IRB | ZRQ | Others | Total`
- **Exactly 4 data rows** on every table:
  - `%inc` — yesterday rate (%)
  - `DoD` — pp vs day-before
  - `WoW` — pp vs 7 days earlier
  - `MoM` — pp vs 28 days earlier
- **Total** = country-level rate / delta (not average of city %).
- Right-align numbers. Suggested widths: label `6`, cities `6`, Others `7`, Total `7`.

## Example shape (SA) — no blocks above the first table

```text
:flag-sa: *SA Fare Integrity (August 10, 2026 | Monday)*

*Cumulative PriceShocks %:*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
%inc   |  41.2 |  45.1 |  38.0 |  42.5 |  44.0 |   40.1 |   42.3
DoD    |  +0.8 |  +0.3 |  -0.2 |  +1.1 |  +0.5 |   +0.4 |   +0.6
WoW    |  -0.4 |  +0.2 |  +0.1 |  -0.3 |  +0.0 |   -0.1 |   -0.1
MoM    |  -1.2 |  -0.8 |  -0.5 |  -1.0 |  -0.9 |   -0.7 |   -0.9
```

*Residual fare increase %:*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
%inc   |  14.1 |  18.8 |  16.8 |  18.3 |  19.2 |   20.6 |   17.0
DoD    |  +1.6 |  +0.4 |  -0.4 |  +1.6 |  +1.5 |   +1.5 |   +1.0
WoW    |  +0.5 |  +0.2 |  -0.1 |  +0.4 |  +0.3 |   +0.6 |   +0.4
MoM    |  -0.8 |  -0.3 |  -0.5 |  -0.2 |  -0.4 |   -0.1 |   -0.6
```

*Rounding error % (|Δ|≤0.01):*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
%inc   |   1.2 |   1.5 |   1.1 |   1.3 |   1.4 |    1.0 |    1.3
DoD    |  +0.1 |  +0.0 |  -0.1 |  +0.2 |  +0.0 |   +0.1 |   +0.1
WoW    |  +0.0 |  -0.1 |  +0.0 |  +0.1 |  -0.1 |   +0.0 |   +0.0
MoM    |  -0.2 |  -0.1 |  -0.1 |  -0.2 |  -0.1 |   -0.2 |   -0.2
```

*Surcharge mismatch %:*
```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
%inc   |   … |   … |   … |   … |   … |    … |    …
DoD    |   … |   … |   … |   … |   … |    … |    …
WoW    |   … |   … |   … |   … |   … |    … |    …
MoM    |   … |   … |   … |   … |   … |    … |    …
```

*Pickup mismatch %:*
```
…same 4-row shape…
```

*Surge mismatch %:*
```
…same 4-row shape…
```

*PD mismatch %:*
```
…same 4-row shape…
```

:flag-jo: *JO Fare Integrity (…)*  
(same table set; cities AMM | IRB | ZRQ | Others | Total)

:clipboard: *Watches (last 3 runs):* https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31
```

## Rules
- Do **not** post country prose blocks (no “X% · DoD … · Rides …” above tables).
- Flag `:warning:` on a **table title** only when that KPI’s country Total `%inc` > prior 7d avg.
- SQL: `sql/fare_integrity_channel_summary.sql`
- Never invent numbers — pad/format only what Snowflake returns.
