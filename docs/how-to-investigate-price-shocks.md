# Investigating price shocks as an expert

A working guide for using the `jeeny-pricing-analysis` skill. The skill holds the facts; this is how to use them without producing a number you have to retract.

---

## The one-paragraph version

Every price-shock question reduces to: *the passenger was quoted X and paid Y — which term of Y ≠ X, and does that term have a legitimate mechanism behind it?* You answer it in three moves. **Size it** (`quantum.sql`) so you know whether you're looking at 1% or 40% of rides. **Split it** (`residual_decomp.sql`) so you know whether the ride value, the surcharge, the hailing fee or a contractual line item moved. **Attribute it** (`causes.sql`) so each ride lands in exactly one bucket with a verdict. Only then interpret. Most bad pricing analysis skips straight to attribution and ends up defending a bucket percentage nobody can reproduce.

---

## Ask the framing question first

Before any SQL, settle three things with whoever asked. Each one changes the headline number, and discovering the mismatch after you've presented is how credibility goes.

**Which metric do they mean by "price shock"?** Strict shock is `Fare_Diff > 0.01` — 41% of SA rides. `increase_pricing` additionally requires `Residual > 0.01` — 18%. Both are defensible; they differ by 1.7–2.4×. If someone says "40% of our rides have price shock" and someone else says "18%", they are both right and looking at different columns.

**Rides or money?** Waiting charges are 43% of shock *rides* but small per ride. Additional time is 19% of rides at ~6.37 SAR each. Rank causes by rides and you get one story; rank by value and you get another. Say which.

**Which denominator?** All positive gaps (`> 0`, rounding visible, ~4% larger) or strict shocks (`> 0.01`, rounding definitionally zero). Mixing tables from the two produces buckets that don't sum to 100%.

---

## The investigation, step by step

### 1. Size it, and sanity-check before you believe it

Run `quantum.sql`. You want rides, %, total excess, average and P90 — **per market, in its own currency**. Never a SAR+JOD total.

Then check against `references/baselines.md` §1 before interpreting a single number. Expect ~41% SA / ~26% JO and ~2.86M SA / ~2.50M JO rides over 30 days. A shock rate of 70% doesn't mean fares broke overnight; it means the PriceChecks join fanned out or the discount add-back is missing. **A surprising number is a bug in your query until proven otherwise** — this dataset has a fan-out trap and a missing-term trap that both produce plausible-looking wrong answers.

Look at the P90 next to the average. If the average moved but P90 didn't, you have more small gaps (usually volume mix). If P90 moved, something structural changed.

### 2. Split the gap before you attribute it

Run `residual_decomp.sql`. This is the step that separates expert work from bucket-counting, and it's the newest capability in the skill.

`Normalized_Receipt` is exactly its line items, so subtracting the quote term by term gives an **exact** identity:

```
Fare_Diff = d_ridevalue + d_hailing + d_surcharge + Non_Issue
```

which means `Residual = d_ridevalue + d_hailing + d_surcharge`. No unexplained remainder. Every riyal of every gap is attributed to a named fare component before any judgement is applied.

Three things this buys you:

- **The unclassified bucket stops being a black box.** Bucket 8 is ~14% of shocks at the highest average overcharge of any large bucket, and no open ticket covers it. Decomposed, it becomes "X% of bucket-8 value is ride-value delta on dropoff≠destination rides" — a statement engineering and product can act on.
- **It validates your own query.** The `identity_check` column must come out ~0. Non-zero means you dropped a receipt line item. This is a free correctness test on every run.
- **It tells you where to spend your time.** If `d_surcharge` is 1% of value, the surcharge-mismatch ticket is real but not where the money is, regardless of how much attention it's getting.

Cut it by scenario × dropoff-at-destination. That 2×3 grid is the single most informative table in this whole domain.

### 3. Attribute, and be honest about what precedence does

Run `causes.sql`. Eight exclusive buckets, first match wins, tech flags ranked above contractual ones.

The thing to internalise: **precedence is an editorial decision, not a measurement.** A ride with both a surcharge mismatch and a waiting charge has to go somewhere. Putting tech first moved SA bucket 2 from roughly 4k to ~20.3k rides — a 5× swing with zero change in the underlying data. So every bucket table you publish states its precedence version, and any comparison against an older table accounts for it. If you don't, someone will read the jump as a regression and open a ticket for a reordering you did.

Corollary: never read causation into a bucket. A bucket-5 ride *may* also have carried a surge mismatch that the ordering suppressed. Buckets are signatures, not diagnoses. When someone asks "how many rides are affected by the surcharge bug", the honest answer needs the precedence caveat attached.

### 4. Interrogate `d_ridevalue` — this is the real work

Ride value differing from the quote is the dominant residual driver and the least documented mechanism. `SKILL.md` §5 has the ladder; the judgement is in how you read it.

Work down and stop at the first thing that explains the delta:

1. **Dropoff at destination?** If false, the trip was re-Googled and the fare legitimately moved. Expected — but *quantify it anyway*, because it's a large slice of bucket 8 and product has never labelled it legitimate-vs-design-gap. That unlabelled volume is arguably the most valuable open question in the domain.
2. **Scenario?** `withinA` is supposed to charge the quote. **A `withinA` ride with dropoff at destination and a material `d_ridevalue` has no documented mechanism.** That is the strongest bug signal available in this dataset — stronger than any current ticket. If you find volume there, you've found something new.
3. **Additional time?** Recompute it: `(ACTUALTIME − APPLIEDESTIMATETIME) × FACTORFORADDITIONALTIME` should equal `ADDITIONALTIMEVALUE`. If it doesn't reconcile, that's a finding in itself. Watch the units — those are minutes, thresholds are seconds.
4. **Silent re-estimate?** `APPLIEDESTIMATEFARE ≠ ORIGINALESTIMATEFARE` on a dropoff-at-destination ride means the engine re-estimated without an obvious trigger.
5. **Charging path.** `CHARGINGDISTANCESOURCE` / `CHARGINGTIMESOURCE` / `TAXIMETERCASE` tell you which branch ran. A path that doesn't match the scenario is a bug candidate.
6. **Multipliers as amplifiers.** Even matching multipliers scale the delta — a 0.1 gap on a large fare is a large absolute overcharge.
7. **Scaled distance.** Normally ≈0–16 rides per 29 days. Any material volume *is* the finding.

### 5. For a single complaining ride

Run `ride_audit.sql` with the ride id. It dumps quote, ride, upfront and receipt side by side with the decomposition and per-bucket flags pre-computed, including the additional-time arithmetic check. Read it in the §5 order above. The first line that breaks is your answer, and you can usually give the passenger-facing explanation in one sentence.

---

## Judgement calls that separate expert from adequate

**Distinguish a defect from a disclosure failure.** Buckets 4, 5 and 7 are ~85% of shock volume and every one is a correctly applied charge. Passengers still experience them as being overcharged, because they were shown a fixed quote and never told it could grow. That is a product problem with a product fix (disclosure), not an engineering ticket. Filing it as a bug wastes engineering time and doesn't help the passenger. Conversely, don't let "it's working as designed" close the conversation — 41% of SA rides paying above quote is a real business problem whatever the mechanism.

**Lead with the honest headline.** Open tech tickets explain ~1.2% of shock rides. Fixing every known bug would barely move the shock rate. If a stakeholder believes the tickets are the story, correct that early — the leverage is in disclosure and in bucket 8, and letting them find out late costs you the room.

**Separate volume from rate, always.** Total excess fare rises when rides rise. Before reading any sum, check `ride_count`. Then read rates and per-ride averages. The single most common misreading of this dataset is a volume increase presented as a pricing regression.

**Localise before you theorise.** One city moving points at local config — area surcharge, intercity, taximeter. All cities moving points at a platform release or a pipeline problem. One day near the 7-day average is noise. Establish shape before proposing a cause.

**Carry confidence through to the conclusion.** Bucket 3 is a proxy: distance between the quote pin and where the ride was offered is not proof of a wrong Google pin — the passenger may have walked. Say "directional, low confidence" and mean it. Bucket 7's volume is solid; its *label* is what's arguable. Precision about which part is uncertain is what makes the certain parts credible.

**Say "hypothesis" while it is one.** Nothing in this taxonomy is engineering-confirmed. Avoid "confirmed bug", "root cause", "fixed". A finding that says "20,723 rides show a surcharge mismatch with no documented mechanism; hypothesis is X; here's the query" gets acted on. One that says "we found the root cause" gets challenged and unravels.

---

## Reporting template

State, in this order: the **bucket and verdict** · the **precedence version and denominator** · **ride count and share** · **average and total excess, per market in its own currency** · **area codes and the date window** · the **component the decomposition points to** · **confidence** · and the **query plus Snowflake query ID** so anyone can reproduce it.

If you can't produce the query ID, you don't have a finding yet — you have an impression.

---

## Failure modes, and the tell for each

| Failure | Tell |
|---|---|
| PriceChecks fanned out | Ride count above ~2.9M SA / ~2.5M JO per 30 days |
| Missing discount add-back | Shock rate low, `decrease_pricing` unusually high |
| Missing surcharge gross-up | Systematic small gaps in SA only |
| Compared against `CHARGINGFARE` | Every ride looks like a shock (hailing/waiting/discount excluded) |
| Treated `pc.VAT` as ride VAT | Gaps ≈ 15% of fare in SA |
| Dropped `INTERCITYSURCHARGE` | Every intercity ride flags as surcharge mismatch |
| Coalesced multipliers to 0 | Bucket 1 far above ~1k rides |
| Mixed currencies | A "total excess" with no market label |
| Mixed denominators | Buckets don't sum to 100% |
| Dropped a receipt line item | `identity_check` ≠ 0 in `residual_decomp.sql` |

---

## Where to push next

Three open fronts, in descending value:

1. **Bucket 8**, ~14% of shocks at the highest average overcharge of any large bucket, no ticket. Decompose it by component × dropoff × scenario. Most of it is expected to be dropoff≠destination — get that labelled by product, and see what's left.
2. **`withinA` + dropoff at destination + material `d_ridevalue`.** No documented mechanism. If there's volume, it's a new bug.
3. **Disclosure economics.** Buckets 4, 5 and 7 are ~85% of volume and legitimate. Quantify what fraction of complaints and churn they drive, and the case stops being an engineering backlog item.
