# Slack channel message template (Pulsar — short)

Style matches bizfin-bot daily report.  
**Channel KPIs:**
1. `% rides with fare increase` (`increase_pricing`)
2. **Surcharge mismatch** rides (withinA + dropoff at dest, PC vs Details surcharge)
3. **Pickup estimate mismatch** rides (PriceCheck pickup vs `ride_offered` > 100m)

## Example shape

```text
:flag-sa: *SA Fare Increase % (August 05, 2026 | Wednesday):*

*% rides with fare increase:*
14.2%  ·  DoD +0.3pp | WoW -0.2pp | MoM -1.1pp
• vs prior 7d avg 13.8%
• Rides 96,611

*Surcharge mismatch (withinA + at dest):*
124 rides (0.13%) · DoD +10 | WoW -5 | vs7d avg 110

*Pickup mismatch (>100m vs offer):*
890 rides (0.92%) · DoD -20 | WoW +40 | vs7d avg 850

*City-wise (% fare increase):*
```
City   | RUH  | JED  | MAD  | DMM  | MEC  | Others |
-----------------------------------------------------
%inc   | 13.3 | 18.5 | 16.8 | 18.3 | 18.8 | 12.1  |
vs DoD | -0.3 | -0.4 | -0.7 | -0.3 | +0.5 | +0.2  |
```

*City-wise (surcharge mismatch rides):*
```
City | RUH | JED | MAD | DMM | MEC | Others |
---------------------------------------------
n    | 12  | 40  | 8   | 5   | 9   | 50     |
```

*City-wise (pickup mismatch rides):*
```
City | RUH | JED | MAD | DMM | MEC | Others |
---------------------------------------------
n    | …                                           |
```

:flag-jo: *JO …* (same blocks)

:clipboard: *Detailed watches:* https://easytaxime.slack.com/docs/T33U3F6CW/F0BN0E7RJ31
```

## Rules
- Keep channel short; put investigation detail on **Canvas**.
- Flag with :warning: only when yesterday count/rate **> prior 7d avg** (major shift).
- SQL: `sql/fare_integrity_channel_summary.sql`
