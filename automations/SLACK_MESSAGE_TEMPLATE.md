# Slack channel message template (Pulsar — tables only)

**No prose before tables.** Country header + table title + monospace table only.  
Footer: canvas link once at the end.

Post **SA first, then JO**. Format JO with the **same care as SA**.

JO distortion usually comes from: (1) reusing SA city headers, (2) uneven padding, (3) unclosed / nested code fences after the long SA block. Avoid all three.

## Channel KPI tables (this order, both countries)

1. Cumulative PriceShocks %
2. Residual fare increase %
3. Rounding error %
4. Surcharge mismatch %
5. Pickup mismatch %
6. Surge mismatch %
7. PD mismatch %

## Table formatting (required — SA and JO)

- Each table body is inside its **own** Slack ` ``` ` code fence. Close the fence before the next `*Title:*` line.
- Fixed-width cells; pad with spaces so every `|` aligns vertically.
- Right-align numbers.
- Exactly 4 data rows: `%inc` | `DoD` | `WoW` | `MoM`
- **Total** = SQL `grain=country` rate/delta (not average of cities).
- Cell widths: label `6`, each city `6`, Others `7`, Total `7`.

### Headers (copy exactly)

SA:

```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
```

JO (5 value columns — never SA cities):

```
City   |  AMM  |  IRB  |  ZRQ  | Others |  Total
-------|-------|-------|-------|--------|-------
```

### JO hard rules

- Header must be `AMM | IRB | ZRQ | Others | Total` only.
- Same 4 rows and padding discipline as SA.
- After SA’s last table fence closes, start JO with a fresh `:flag-jo:` header (do not leave JO inside an open SA fence).
- Missing city bucket in SQL → still print the column as `0.0` / `+0.0` so the grid stays intact.
- Before send: verify every JO table has **6 pipes per row** (label + 5 values) and aligned columns.

## SA table body example (one KPI)

Title line (outside fence): `*Cumulative PriceShocks %:*`  
Then fence:

```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
%inc   |  41.2 |  45.1 |  38.0 |  42.5 |  44.0 |   40.1 |   42.3
DoD    |  +0.8 |  +0.3 |  -0.2 |  +1.1 |  +0.5 |   +0.4 |   +0.6
WoW    |  -0.4 |  +0.2 |  +0.1 |  -0.3 |  +0.0 |   -0.1 |   -0.1
MoM    |  -1.2 |  -0.8 |  -0.5 |  -1.0 |  -0.9 |   -0.7 |   -0.9
```

Repeat that SA grid for all 7 KPIs under:

`:flag-sa: *SA Fare Integrity (Month DD, YYYY | Weekday)*`

## JO table body examples (required — match this padding)

Country header (outside fences):

`:flag-jo: *JO Fare Integrity (Month DD, YYYY | Weekday)*`

### Cumulative PriceShocks %

```
City   |  AMM  |  IRB  |  ZRQ  | Others |  Total
-------|-------|-------|-------|--------|-------
%inc   |  28.4 |  31.2 |  29.0 |   27.5 |   28.9
DoD    |  +0.4 |  +0.6 |  -0.1 |   +0.2 |   +0.3
WoW    |  -0.2 |  +0.1 |  +0.0 |   -0.3 |   -0.1
MoM    |  -0.9 |  -0.7 |  -0.5 |   -0.8 |   -0.8
```

### Residual fare increase %

```
City   |  AMM  |  IRB  |  ZRQ  | Others |  Total
-------|-------|-------|-------|--------|-------
%inc   |  12.1 |  14.5 |  13.0 |   11.8 |   12.6
DoD    |  +0.3 |  +0.5 |  -0.2 |   +0.1 |   +0.2
WoW    |  +0.1 |  +0.0 |  -0.1 |   +0.2 |   +0.1
MoM    |  -0.6 |  -0.4 |  -0.3 |   -0.5 |   -0.5
```

### Rounding error % (|Δ|≤0.01)

```
City   |  AMM  |  IRB  |  ZRQ  | Others |  Total
-------|-------|-------|-------|--------|-------
%inc   |   0.9 |   1.1 |   1.0 |    0.8 |    0.9
DoD    |  +0.0 |  +0.1 |  -0.1 |   +0.0 |   +0.0
WoW    |  +0.0 |  -0.1 |  +0.0 |   +0.0 |   +0.0
MoM    |  -0.1 |  -0.1 |  -0.1 |   -0.2 |   -0.1
```

### Surcharge / Pickup / Surge / PD mismatch %

Same JO header + 4 rows (`%inc`/`DoD`/`WoW`/`MoM`). Example surcharge:

```
City   |  AMM  |  IRB  |  ZRQ  | Others |  Total
-------|-------|-------|-------|--------|-------
%inc   |   0.4 |   0.6 |   0.3 |    0.5 |    0.4
DoD    |  +0.0 |  +0.1 |  -0.1 |   +0.0 |   +0.0
WoW    |  -0.1 |  +0.0 |  +0.0 |   -0.1 |   -0.1
MoM    |  -0.2 |  -0.1 |  -0.1 |   -0.2 |   -0.2
```

After JO’s last table, footer once:

`:clipboard: *Watches (last 3 runs):* https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31`

## Rules

- Do **not** post country prose blocks above tables.
- Flag `:warning:` on a **table title** only when that KPI’s country Total `%inc` > prior 7d avg.
- SQL: `sql/fare_integrity_channel_summary.sql`
- Never invent numbers — pad/format only what Snowflake returns.
- **JO quality check before send:** 5 value columns, 4 data rows, closed fences, pipes aligned like the JO examples above.
