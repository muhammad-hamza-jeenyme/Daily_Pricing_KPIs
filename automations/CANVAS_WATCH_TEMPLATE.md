# Canvas template — Price-shock breakdown only

**Fixed canvas:** `F0BN0E7RJ31` — https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31

## Retention
Keep **current run + previous 2 runs** (max 3 dated `##` sections). Drop older.

## Each run
1. Run `sql/fare_integrity_canvas_breakdown.sql`
2. Read canvas → prepend today’s section → keep newest 3 only
3. Title at top: `# Pricing Fare Integrity — breakdown`
4. **Only** the tables below — no exceptions, no investigate list, no definitions, no alerts

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
unclassified                 |   x.x
```
(Verify sum ≈ 100.0)

*JO — % of fare-increase rides:*
[same cause list]

---
```

## Table formatting
- Same monospace rules as channel (`automations/SLACK_MESSAGE_TEMPLATE.md`)
- Scenario tables: SQL `grain=scenario_city` + `scenario_country` → Total column
- Cause mix: SQL `grain=cause_mix`, `segment` = cause name, `pct_shock` = %

## Definitions (agent-only — do not paste onto canvas)
| Block | Rule |
|-------|------|
| Scenario tables | NET shock contribution: segment ∩ Fare_Diff>0.01 ∩ not spillover / all rides |
| Cause mix | GROSS Fare_Diff>0.01; exclusive first-match; includes `previous_wallet_balance` (spillover recovery) |
| Precedence | pickup → PD → surge → surcharge → wallet → waiting → scenario slices → unclassified |
