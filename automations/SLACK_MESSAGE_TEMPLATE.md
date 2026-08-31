# Slack channel message template (Pulsar — tables only)

**No prose before tables.** Header + table titles + monospace tables only.

## Critical: JO formatting break (fix)

Slack often **truncates or breaks fences** when SA+JO are one long message. After ~2 JO tables the rest renders as plain text.

**Required posting pattern**
1. **Webhook message 1 — SA only** (all 7 SA tables). Close every fence.
2. **Webhook message 2 — JO only** (all 7 JO tables) + canvas link at the end.
3. Never put SA and JO in the same webhook payload.
4. Each table: title line **outside** fence → open ` ``` ` → 5–6 data lines → close ` ``` ` → next title. Count fences: must be **even** per message.
5. Do not nest fences. Do not use ` ```text ` if it causes issues — plain ` ``` ` is fine.
6. If a fence fails QA, rebuild that country message from scratch before sending.

## Channel KPI tables (this order, each country)

1. Cumulative PriceShocks % — **NET**
2. Residual fare increase % — **NET**
3. Rounding error %
4. Surcharge mismatch %
5. Pickup mismatch %
6. Surge mismatch %
7. PD mismatch %

## Table formatting

- Fixed-width cells; right-align numbers.
- Rows: `%inc` | `DoD` | `WoW` | `MoM`
- SA: `City | RUH | JED | MAD | DMM | MEC | Others | Total`
- JO: `City | AMM | IRB | ZRQ | Others | Total` only
- **Total** = country grain from SQL
- Cell widths: label `6`, city `6`, Others `7`, Total `7`

### SA header

```
City   |  RUH  |  JED  |  MAD  |  DMM  |  MEC  | Others |  Total
-------|-------|-------|-------|-------|-------|--------|-------
```

### JO header

```
City   |  AMM  |  IRB  |  ZRQ  | Others |  Total
-------|-------|-------|-------|--------|-------
```

## Message 1 shape (SA only)

```
:flag-sa: *SA Fare Integrity (Month DD, YYYY | Weekday)*

*Cumulative PriceShocks %:*
```
…SA table…
```
*Residual fare increase %:*
```
…SA table…
```
…Rounding, Surcharge, Pickup, Surge, PD — each with its own open/close fence…
```

## Message 2 shape (JO only)

```
:flag-jo: *JO Fare Integrity (Month DD, YYYY | Weekday)*

*Cumulative PriceShocks %:*
```
City   |  AMM  |  IRB  |  ZRQ  | Others |  Total
-------|-------|-------|-------|--------|-------
%inc   |  … |  … |  … |    … |    …
DoD    |  … |  … |  … |    … |    …
WoW    |  … |  … |  … |    … |    …
MoM    |  … |  … |  … |    … |    …
```
*Residual fare increase %:*
```
…same JO grid…
```
*Rounding error %:*
```
…same JO grid…
```
*Surcharge mismatch %:*
```
…same JO grid…
```
*Pickup mismatch %:*
```
…same JO grid…
```
*Surge mismatch %:*
```
…same JO grid…
```
*PD mismatch %:*
```
…same JO grid…
```

:clipboard: *Canvas breakdown:* https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31
```

## Rules

- Optional `:warning:` on table title if country Total `%inc` > prior 7d avg.
- SQL: `sql/priceshocks_daily_digest.sql` (`metric_family=CHANNEL`)
- Never invent numbers.
- Pre-send JO check: 7 titles, 7 open fences, 7 close fences, every row has JO columns only.
