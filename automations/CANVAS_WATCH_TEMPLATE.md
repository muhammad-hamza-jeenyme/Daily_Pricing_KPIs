# Canvas template — Price-shock and discount breakdown

**Fixed canvas:** `F0BN0E7RJ31` — https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31

## Retention
Keep **current run + previous 2 runs** (max 3 dated `##` sections). Drop older.

## Each run
1. Use **SCENARIO**, **CAUSE_MIX**, and **DISCOUNT** rows from
   `sql/priceshocks_daily_digest_v2.sql` (same run as channel — do not re-query
   ride-level SQL)
2. Read canvas → prepend today’s section → keep newest 3 only
3. Title at top: `# Pricing Fare Integrity — breakdown`
4. **Only** the tables below — no exceptions, no investigate list, no
   definitions, or alerts

## Today’s section

```markdown
## YYYY-MM-DD (Weekday)

### :flag-sa: SA — NET shock by scenario × dropoff
(contribution % of all completed rides; rows %inc / DoD / WoW / MoM; cols cities + Others + Total)

*WithinA · dropoff at destination:*
[monospace table]

*WithinA · dropoff not at destination:*
[table]

*WithinB · dropoff at destination:*
[table]

*WithinB · dropoff not at destination:*
[table]

*BeyondB:*
[table]

### :flag-jo: JO — NET shock by scenario × dropoff
(same 5 tables; JO cities AMM | IRB | ZRQ | Others | Total)

### Cause mix — last day only (GROSS Fare_Diff > 0.01, exclusive, sums to 100%)

*SA — % of fare-increase rides:*
```
Cause                        |    %
-----------------------------|------
pickup_mismatch              |   x.x
pd_mismatch                  |   x.x
surge_mismatch               |   x.x
surcharge_mismatch           |   x.x
previous_wallet_balance      |   x.x
waiting_time                 |   x.x
withinA_at_dest              |   x.x
withinA_not_dest             |   x.x
withinB_at_dest              |   x.x
withinB_not_dest             |   x.x
beyondB                      |   x.x
```
(Verify sum ≈ 100.0; omit empty causes)

*JO — % of fare-increase rides:*
[same cause list]

### Discount exposure — post-discount passenger experience

Use `output_kind=discount`, `row_type=SEGMENT`. Add one table per market.
Never combine SAR and JOD amounts.

*SA (SAR):*
```
Segment              | Ride% | Gross% | Net% | Avg dDisc | Gross excess | Net excess | Absorb%
---------------------|-------|--------|------|-----------|--------------|------------|--------
voucher_capped       |   x.x |    x.x |  x.x |     x.xxx |          x.x |        x.x |     x.x
voucher_pct_bound    |   x.x |    x.x |  x.x |    -x.xxx |          x.x |        x.x |     x.x
promoeng_capped      |   x.x |    x.x |  x.x |     x.xxx |          x.x |        x.x |     x.x
promoeng_pct_bound   |   x.x |    x.x |  x.x |    -x.xxx |          x.x |        x.x |     x.x
discount_no_source   |   x.x |    x.x |  x.x |     x.xxx |          x.x |        x.x |     x.x
no_discount          |   x.x |    x.x |  x.x |     0.000 |          x.x |        x.x |     0.0
```

*JO (JOD):*
[same segment table]

Below each market table add one compact line from `SUMMARY` rows:

`Capped: {cap_bound_total ride_share_pct}% of rides · partly-shielded absorption: {pct_bound_total absorption_pct}% · promised-not-applied: {count}`

---
```

## Table formatting
- Same monospace rules as channel (`automations/SLACK_MESSAGE_TEMPLATE.md`)
- Scenario: `METRIC_FAMILY=SCENARIO` from PriceShocks digest; `CITY_BUCKET` incl. `Total`
- Cause mix: `METRIC_FAMILY=CAUSE_MIX`, `CITY_BUCKET=Total`, `METRIC_NAME` = cause, `PCT` = %
- Discount: `output_kind=discount`; show `ride_share_pct`,
  `gross_shock_pct`, `net_shock_pct`, `avg_d_discount`,
  `gross_excess_amount`, `net_excess_amount`, and `absorption_pct`
- Omit a discount segment only when no row exists; render numeric zero as zero

## Definitions (agent-only — do not paste onto canvas)
| Block | Rule |
|-------|------|
| Scenario tables | NET shock contribution (pre-computed in `PRICESHOCKS`) |
| Cause mix | GROSS exclusive mix; includes `previous_wallet_balance` (spillover recovery) |
| Precedence | pickup → PD → surge → surcharge → wallet → waiting → scenario slices |
| Discount Gross% | Existing `fare_diff > 0.01`, spillover recovery excluded |
| Discount Net% | Passenger-experienced `net_fare_diff > 0.01`, spillover recovery excluded |
| `avg_d_discount < 0` | Discount grew and partly absorbed the overrun |
| `avg_d_discount ≈ 0` | Discount was capped; passenger had no shock buffer |
