# Jeeny pricing structure

Status: **Awaiting SME input** (first main goal of this project)

This document will capture how Jeeny pricing works end-to-end so KPI alerts stay grounded in real levers.

## Topics to cover (fill as details arrive)

### 1. Fare construction
- Base fare, distance, time, minimum fare, booking fee
- Service types / product lines (e.g. Economy, Plus, delivery — TBD)
- City / country differences

### 2. Dynamic pricing / surge
- How surge is computed and applied
- Caps, floors, multipliers
- When surge is shown to riders vs paid to captains

### 3. Captain / driver economics
- Commission / take rate
- Incentives, guarantees, bonuses
- Acceptance / cancellation effects on effective yield

### 4. Rider discounts & promos
- Coupon / promo funding (Jeeny vs partner)
- Impact on GMV, net revenue, and take rate

### 5. Geo & temporal dimensions
- City, zone, corridor
- Peak vs off-peak, weekday vs weekend, events

### 6. Pricing ops levers
- What Pricing / Ops can change day-to-day
- Config systems / ownership
- Typical failure modes that should trigger alerts

## Confirmed facts

_(none yet — pending first pricing walkthrough)_

## Open questions

- What is the unit of pricing decision (city × service × time)?
- Which metrics are leading vs lagging for pricing health?
- What timezone and “day” definition should Snowflake use relative to PKT 11:30 AM runs?
