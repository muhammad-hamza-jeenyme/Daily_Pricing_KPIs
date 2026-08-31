# Slack channel message template (Pulsar — tables only)

**Data source:** `JEENY_PROD.RIDE.PRICESHOCKS` via `sql/priceshocks_daily_digest.sql`  
(`metric_family = CHANNEL`). Do not recompute ride-level fares in the agent.

**No prose before tables.** Header + table titles + monospace tables only.

## Critical: JO formatting break (fix)

Slack often **truncates or breaks fences** when SA+JO are one long message. After ~2 JO tables the rest renders as plain text.

**Required posting pattern**
1. **Webhook message 1 — SA only** (all 7 SA tables). Close every fence.
2. **Webhook message 2 — JO only** (all 7 JO tables) + canvas link at the end.
3. Never put SA and JO in the same webhook payload.
4. Each table: title line **outside** fence → open ` ``` ` → 5–6 data lines → close ` ``` ` → next title. Count fences: must be **even** per message.
5. Do not nest fences. Plain ` ``` ` is fine.
6. If a fence fails QA, rebuild that country message from scratch before sending.

## Channel KPI tables (this order, each country)

Exact `metric_name` values from PriceShocks:

1. `cumulative_price_shocks_net` — Cumulative PriceShocks % — **NET**
2. `residual_fare_increase_net` — Residual fare increase % — **NET**
3. `rounding_error` — Rounding error %
4. `surcharge_mismatch` — Surcharge mismatch %
5. `pickup_mismatch` — Pickup mismatch %
6. `surge_mismatch` — Surge mismatch %
7. `pd_mismatch` — PD mismatch %

Ignore `spillover_recovery` for channel tables (monitor only).

## Table formatting

- Fixed-width cells; right-align numbers.
- Rows: `%inc` (= `pct`) | `DoD` (= `dod_pp`) | `WoW` | `MoM`
- SA: `City | RUH | JED | MAD | DMM | MEC | Others | Total`
- JO: `City | AMM | IRB | ZRQ | Others | Total` only
- **Total** = `city_bucket = Total`
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
…remaining JO tables…
```

:clipboard: *Canvas breakdown:* F0BN0E7RJ31
```

## Canvas link footer (JO message only)

Use canvas id `F0BN0E7RJ31` (or the live canvas URL). Do not put the bot token in the message.
