# Digital payment spillover & price-shock double-count

Status: **locked 2026-08-19** (Payments PM + validated SQL).  
Applies to daily Pulsar digests and `sql/daily_price_shock_alert.sql` / `sql/fare_integrity_channel_summary.sql`.

## Problem

On **digital** payments (mainly Apple Pay, Credit Card — Master / Visa / Mada via `DETAILS.MODEOFPAYMENT` + `CARDFLAG`), if final fare exceeds the amount already held/charged by less than the **second-transaction threshold**:

| Market | Spillover / 2nd-debit threshold |
|--------|----------------------------------|
| SA | ~**1 SAR** |
| JO | ~**0.1 JOD** |

then there is **no second card debit**. The remainder sits as `RIDE.DETAILS.OUTSTANDINGBALANCE` and is recovered on the passenger’s **next** ride as `RECEIPTS.CANCELLATIONFINE` (often with `VATONCANCELLATIONFINE = 0` because VAT was charged on the originating ride).

**Cash rides do not have this path.**

Without a fix, the same money is counted twice:

1. Originating ride — waiting / additional time / etc. → `Fare_Diff > 0.01` (true shock)
2. Next ride — “prior cancellation fine” / unpaid balance → another `Fare_Diff > 0.01` (recovery, **not** a new shock)

~12.7% of 30-day gross shock rides were this recovery double-count (SA ~41%→~34%; JO ~26%→~25% after exclusion).

## Payment flows (PM — underpay / overpay)

### A) Overpay — charged/held more than final fare
1. **Excess → Jeeny wallet** — keep card charge; credit difference (`PASSENGERS.TRANSACTIONS` — Wallet Topup through ride change). Common on Apple Pay Mada.
2. **Excess → card** — for PA methods (CC / AP Visa·MC): VOID pre-auth then debit final fare (`JTRANSACTION` VOID + DIRECT_PAYMENT). Small excess on PA can also be capture + wallet; large excess more often RV→DB.

### B) Underpay — final fare more than held/charged
3. **Remainder ≤ spillover threshold** → **outstanding** (`DETAILS.OUTSTANDINGBALANCE`); no 2nd debit.
4. **Remainder > threshold** → 2nd debit (capture/settle first amount, then another DB for the delta).

### How to check
| Signal | Where |
|--------|--------|
| Wallet credit | `PASSENGERS.TRANSACTIONS` by `RIDEID` |
| Card reverse / 2nd debit | `GENERAL.JTRANSACTION` (+ `TRANSACTIONEVENTS`) |
| Outstanding | `RIDE.DETAILS.OUTSTANDINGBALANCE` |

## Locked exclusion (recovery leg only)

```
prev_outs = LAG(OUTSTANDINGBALANCE) OVER (
  PARTITION BY PASSENGERID ORDER BY CREATED
)

is_spillover_recovery =
  ZEROIFNULL(prev_outs) > 0
  AND ABS(prev_outs - COALESCE(RECEIPTS.CANCELLATIONFINE, 0)) <= 0.02
```

- Compare **ex-VAT** cancelfine to prior outs (do not include `VATONCANCELLATIONFINE` in the ABS match).
- **Exclude recovery rides** from Cumulative PriceShocks and Residual fare-increase KPIs.
- Keep the **originating** ride in shock counts (where the increase actually happened).
- **LOOKBACK_DAYS = 30** is load-bearing (~60% recover within 24h, ~90% within 7d, ~99% within 30d). Shrinking lookback silently reintroduces double-count. Channel SQL lookback starts **30 days before** the digest window start.

## KPI impact

| KPI | Definition after fix |
|-----|----------------------|
| Cumulative PriceShocks % | `Fare_Diff > 0.01` **and not** `is_spillover_recovery` |
| Residual fare increase % | `increase_pricing` **and not** `is_spillover_recovery` |
| Spillover recovery % | monitor only — recovery legs / completed rides |
| Rounding / Surge / PD / Surcharge / Pickup mismatch | unchanged (independent detectors) |

Report **net** shocks in Slack. Optionally keep gross vs excluded visible for regression checks (`sql/daily_price_shock_alert.sql`).

## Do not

- Ignore `OUTSTANDINGBALANCE` for shock reporting (old v1 note is obsolete).
- Treat every `CANCELLATIONFINE` as a fresh pricing shock without checking prior outs.
- Shrink spillover lookback below 30 days for production digests.
