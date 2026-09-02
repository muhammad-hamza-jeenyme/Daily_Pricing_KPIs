# Slack channel message template (Pulsar — fare tables + discount exposure)

**Data source:** `JEENY_PROD.RIDE.PRICESHOCKS` +
`JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS` via
`sql/priceshocks_daily_digest_v2.sql`. Do not recompute ride-level fares in the
agent.

**No prose before fare tables.** Append the compact discount block after each
country's seven fare tables.

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

These seven tables remain based on the locked `fare_diff`; do not replace them
with `net_fare_diff`. Post-discount passenger impact is shown separately below.

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

*Discount exposure (post-discount):*
…SA compact block defined below…
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

*Discount exposure (post-discount):*
…JO compact block defined below…

:clipboard: *Canvas breakdown:* F0BN0E7RJ31
```

## Discount exposure block

Use `output_kind=discount` rows from `PRICESHOCKS` (`metric_family=DISCOUNT`).
Never mix SAR and JOD. For each country map these exact `metric_name` values:

| Need | `metric_name` | Fields |
|------|---------------|--------|
| Cap-bound share | `cap_bound_total__ride_share` | `pct`, `rides_flagged` |
| Cap-bound shock | `cap_bound_total__net_shock` | `pct`, `rides_flagged`, `rides_denom`, `amount_value` |
| Undiscounted rate | `no_discount__net_shock` | `pct` |
| Partly shielded shocks | `pct_bound_total__net_shock` | `rides_flagged`, `amount_value` |
| Partly shielded gross | `pct_bound_total__gross_shock` | `amount_value` |
| Absorption | `pct_bound_total__absorption` | `pct` |
| Promised not applied | `promised_not_applied` | `rides_flagged` |
| Worst segment | max `pct` among `*_capped__net_shock` / `*_pct_bound__net_shock` | use `amount_value` as avg excess proxy via segment `__gross_shock.avg_value` if needed; prefer segment `__net_shock.pct` and that segment's `__gross_shock.avg_value` |

Currency: SA = SAR, JO = JOD.

Required shape:

```text
*Discount exposure (post-discount):*
No shock buffer: {cap_bound_total__net_shock.rides_flagged}/{cap_bound_total__net_shock.rides_denom} capped rides shocked
({cap_bound_total__net_shock.pct}%; {cap_bound_total__ride_share.pct}% of all rides)
Passenger excess: {cap_bound_total__net_shock.amount_value} {currency}
vs {no_discount__net_shock.pct}% on undiscounted rides
Partly shielded: {pct_bound_total__net_shock.rides_flagged} shock rides
{pct_bound_total__gross_shock.amount_value} → {pct_bound_total__net_shock.amount_value} {currency}
({pct_bound_total__absorption.pct}% absorbed)
Worst: {segment} · {segment__net_shock.pct}% · avg {segment__gross_shock.avg_value} {currency}
Promised but not applied: {promised_not_applied.rides_flagged} rides
```

Formatting:

- This is plain Slack text, not a code fence.
- Round rates to 2 decimals and currency to 2.
- Use arrows only between amounts in the same currency.
- Keep existing headline/table labels unchanged.
- Do not add `net_fare_diff` to the headline Cumulative table.
- If combined SA+JO `promised_not_applied.rides_flagged > 200`, prefix that line with
  `:warning:` in both country messages.
- Prefix the relevant line with `:warning:` when
  `cap_bound_total__ride_share.dod_pp` rises, a capped segment's
  `__net_shock.dod_pp` rises faster than `no_discount__net_shock`, or a
  percentage-bound `__net_shock.avg_value` (`avg_d_discount`) moves toward zero.
- Negative `avg_value` on `__net_shock` means the discount grew and absorbed
  part of the overrun — not a loss.

## Canvas link footer (JO message only)

Use canvas id `F0BN0E7RJ31` (or the live canvas URL). Do not put the bot token in the message.
