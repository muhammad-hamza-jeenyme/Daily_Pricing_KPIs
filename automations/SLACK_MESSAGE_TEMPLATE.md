# Slack channel message template (Pulsar — short)

Style matches bizfin-bot daily report: country KPI block + city-wise code table.  
**Only KPI in the channel message:** `% rides with fare increase` (`increase_pricing`).

## Example shape

```text
:flag-sa: *SA Fare Increase % (August 05, 2026 | Wednesday):*

*% rides with fare increase:*
14.2%  ·  DoD +0.3pp | WoW -0.2pp | MoM -1.1pp
• vs prior 7d avg 13.8% (:warning: above avg)
• Rides 96,611 · DoD rides +1% | WoW +3%

*City-wise (% fare increase):*
```
City   | RUH  | JED  | MAD  | DMM  | MEC  | Others |
-----------------------------------------------------
%inc   | 13.3 | 18.5 | 16.8 | 18.3 | 18.8 | 12.1  |
vs DoD | -0.3 | -0.4 | -0.7 | -0.3 | +0.5 | +0.2  |
vs WoW | -0.2 | -1.7 | -1.5 | +0.1 | +0.0 | -0.5  |
```

:flag-jo: *JO Fare Increase % (…):*
…same pattern…
City   | AMM  | IRB  | ZRQ  | Others |
…

:clipboard: *Detailed watches:* <canvas link>
```

## Rules
- Two country blocks: **SA** then **JO**.
- City columns = majors + **Others** (non-major areas in that country).
- No long bullet dumps of every KPI in the channel message.
- Link canvas for watches at the bottom.
