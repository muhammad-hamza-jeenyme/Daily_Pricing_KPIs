# Pulsar channel summary template (fare-increase % only)

Post **only** via `PULSAR_SLACK_WEBHOOK_URL`. Never use Cursor `send_slack_message` for the digest body.

Source SQL: `sql/fare_integrity_channel_summary.sql`  
Watches detail lives in Canvas (see `CANVAS_WATCH_TEMPLATE.md`) — **not** in the channel.

## Shape

1. Header: `Pulsar · Pricing fare-integrity · {report_date}`
2. SA country line: `% fare ↑` + d/d · w/w · m/m · vs7d + rides (`area_label = ALL`)
3. SA city code line: `RUH | JED | MAD | DMM | MEC | Others` (each with %)
4. JO country line: same pattern
5. JO city code line: `AMM | IRB | ZRQ | Others`
6. Footer: always link the fixed Canvas  
   `Canvas: https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31`  
   If Canvas update failed this run, add one short note: `Canvas update failed (bot token missing).`

## Example

```
Pulsar · Pricing fare-integrity · 2026-08-05

*SA*  4.2% fare ↑ · d/d +0.3pp · w/w -0.1pp · m/m +0.8pp · vs7d +0.2pp · 120000 rides
RUH 3.8% | JED 5.1% | MAD 2.9% | DMM 4.0% | MEC 3.5% | Others 4.4%

*JO*  6.1% fare ↑ · d/d -0.2pp · w/w +0.5pp · m/m +1.1pp · vs7d +0.4pp · 45000 rides
AMM 6.5% | IRB 4.8% | ZRQ 5.2% | Others 5.9%

Canvas: https://easytaxime.slack.com/docs/...
```

## Formatting rules

- Percentages: 1 decimal (e.g. `12.3%`).
- Deltas: signed 1 decimal with `pp` suffix (e.g. `+0.4pp`, `-1.2pp`).
- `vs7d` = yesterday − prior 7 complete days average (pp).
- City lines: single monospace-friendly line of area codes.
- SA city order: RUH | JED | MAD | DMM | MEC | Others.
- JO city order: AMM | IRB | ZRQ | Others.
- No multi-KPI watch dumps in the channel.

## Failure

If Snowflake fails, POST one line only:

```
Pulsar · Pricing fare-integrity · Snowflake query failed — no digest numbers today.
```
