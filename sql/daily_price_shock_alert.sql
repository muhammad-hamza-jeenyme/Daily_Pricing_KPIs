/* =====================================================================
   Jeeny — Daily price shock alert  (Snowflake / JEENY_PROD)
   v2.1  ·  2026-08-19  ·  spillover double-count excluded

   WHAT CHANGED vs the pre-2026-08-19 alert
   ----------------------------------------
   A digital-payment ride whose fare rises by less than the second-
   transaction threshold (~1 SAR KSA / ~0.1 JOD JO) does NOT get a second
   debit. The remainder is parked in RIDE.DETAILS.OUTSTANDINGBALANCE and
   recovered on the passenger's NEXT ride as a RECEIPTS.CANCELLATIONFINE
   line. Both rides were being reported as price shocks — the same money,
   twice. This query flags and excludes the RECOVERY leg (the second
   count), keeping the originating ride where the increase actually
   happened.

   Impact on the 30-day baseline: 233,078 of 1,834,184 shock rides (12.7%)
   were double counted. SA shock rate 41.35% -> 34.46%; JO 26.08% -> 24.65%.

   Smoke-tested on 2026-08-14 (query 01c67fb8-020a-d154-000b-86f71f026c3e):
     SA  75,592 completed  32,415 gross  -4,691 spillover  27,724 net  42.88% -> 36.68%
     JO  54,393 completed  13,682 gross    -715 spillover  12,967 net  25.15% -> 23.84%

   *** LOOKBACK IS LOAD-BEARING ***
   Recovery is NOT mostly next-day: only ~60% lands within 24h, ~90%
   within 7d, 99% within 30d (max observed ~50 days). LOOKBACK_DAYS = 30.
   Shrinking it silently reintroduces the double count.

   Notes
   -----
   - CREATEDDATE is already a Saudi calendar date. Do not re-timezone.
   - Never SUM SAR and JOD together. Money is reported per market.
   - RIDE.DETAILS lags ~1 day; the alert reports the last COMPLETE day.
   - Channel digests: sql/fare_integrity_channel_summary.sql (same spillover rule).
   ===================================================================== */

/* Written as ONE statement (no SET) so it works with runners that submit a
   single statement per call — the Snowflake MCP connector is one of these.
   To backfill a specific day, replace both DATEADD('day',-1,CURRENT_DATE())
   occurrences with a literal, e.g. DATE '2026-08-14'. */

WITH params AS (
    SELECT DATEADD('day', -1, CURRENT_DATE()) AS report_date,   -- last complete day
           30                                 AS lookback_days  -- see 6.5: do not shrink
),
lookback AS (
    /* Every ride in the lookback window, so LAG can see each passenger's
       previous ride and whether it left an unpaid remainder. */
    SELECT
        rd.RIDEID,
        rd.PASSENGERID,
        rd.CREATED,
        rd.OUTSTANDINGBALANCE AS outs
    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.GENERAL.AREAS ga
      ON rd.AREA_CODE = ga.AREA_CODE
    CROSS JOIN params p
    WHERE rd.CREATEDDATE BETWEEN DATEADD('day', -p.lookback_days, p.report_date)
                             AND p.report_date
      AND ga.COUNTRY_CODE IN ('SA', 'JO')
),

prev AS (
    SELECT
        RIDEID,
        LAG(outs) OVER (PARTITION BY PASSENGERID ORDER BY CREATED) AS prev_outs
    FROM lookback
),

base AS (
    SELECT
        rd.RIDEID,
        ga.COUNTRY_CODE                      AS country,
        rd.AREA_CODE                         AS area_code,
        rd.MODEOFPAYMENT                     AS payment_method,
        COALESCE(NULLIF(TRIM(rd.CARDFLAG), ''), '(none)') AS card_flag,

        /* ---- SME-locked comparison. Do not re-derive. ---------------- */
        ROUND(
            (COALESCE(rr.TOTALAMOUNTWITHTAX, 0)
             + COALESCE(rr.DISCOUNT, 0)
             + COALESCE(rr.VATONDISCOUNT, 0))
          - (COALESCE(pc.VALUE, 0)
             + COALESCE(pc.VAT, 0)
             + ROUND(COALESCE(pc.SURCHARGE, 0)
                     * IFF(ga.COUNTRY_CODE = 'SA', 1.15, 1.0), 2))
        , 2)                                 AS fare_diff,

        /* ---- Cause inputs -------------------------------------------- */
        COALESCE(rr.CANCELLATIONFINE, 0)         AS cfine,
        COALESCE(rr.VATONCANCELLATIONFINE, 0)    AS vcfine,
        COALESCE(rr.WAITINGCHARGES, 0)           AS wait_chg,
        COALESCE(rr.VATONWAITINGCHARGES, 0)      AS vwait_chg,
        COALESCE(uf.ADDITIONALTIMEVALUE, 0)      AS addl_time,
        LOWER(uf.UPFRONTSCENARIO)                AS scenario,
        LOWER(TO_VARCHAR(uf.DROPOFFATDESTINATION)) AS drop_at_dest,
        COALESCE(pc.SURGEMULTIPLIER, 0)          AS pc_surge,
        COALESCE(rd.SURGEMULTIPLIER, 0)          AS rd_surge,
        COALESCE(pc.DISCRIMINATIONMULTIPLIER, 0) AS pc_pd,
        COALESCE(rd.DISCRIMINATIONMULTIPLIER, 0) AS rd_pd,
        COALESCE(pc.SURCHARGE, 0)                AS pc_sur_exvat,
        COALESCE(rr.SURCHARGE, 0)
          + COALESCE(rr.INTERCITYSURCHARGE, 0)   AS rr_sur_exvat,

        /* ---- THE FIX -------------------------------------------------
           TRUE when this ride is merely recovering the unpaid remainder
           of the passenger's previous ride. VAT is deliberately excluded
           from the comparison: VATONCANCELLATIONFINE is 0 on recovery
           rows because VAT was already charged on the originating ride. */
        (ZEROIFNULL(pv.prev_outs) > 0
         AND ABS(pv.prev_outs - COALESCE(rr.CANCELLATIONFINE, 0)) <= 0.02)
                                             AS is_spillover_recovery

    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.RIDE.UPFRONT   uf ON rd.RIDEID = uf.RIDEID
    JOIN JEENY_PROD.RIDE.RECEIPTS  rr ON rd.RIDEID = rr.RIDEID
    JOIN JEENY_PROD.GENERAL.AREAS  ga ON rd.AREA_CODE = ga.AREA_CODE
    JOIN JEENY_PROD.PASSENGERS.PRICECHECKS pc
      ON pc.RIDEID = rd.RIDEID
     AND LOWER(pc.SERVICEFILTER) = LOWER(rd.REQUEST_SERVICE)
    LEFT JOIN prev pv ON pv.RIDEID = rd.RIDEID
    CROSS JOIN params p
    WHERE rd.BOARDED IS NOT NULL
      AND uf.ORIGINALESTIMATEFARE IS NOT NULL
      AND ga.COUNTRY_CODE IN ('SA', 'JO')
      AND rd.CREATEDDATE = p.report_date
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY rd.RIDEID
        ORDER BY pc.ACTUALDATETIME DESC NULLS LAST) = 1
),

bucketed AS (
    SELECT
        *,
        CASE
            WHEN ROUND(pc_surge, 4) <> ROUND(rd_surge, 4)
              OR ROUND(pc_pd, 4)    <> ROUND(rd_pd, 4)
                THEN '1_surge_or_pd_mismatch'
            WHEN scenario = 'withina'
             AND drop_at_dest = 'true'
             AND ROUND(rr_sur_exvat, 2) <> ROUND(pc_sur_exvat, 2)
                THEN '2_surcharge_mismatch'
            /* bucket 3 (pickup proxy) omitted — needs RIDE.EVENTHISTORY,
               ~0.01% of volume, not worth the daily scan */
            WHEN (cfine + vcfine) > 0.01
                THEN '4_prior_unpaid_balance'
            WHEN (wait_chg + vwait_chg) > 0.01
                THEN '5_waiting_time'
            WHEN fare_diff > 0 AND fare_diff <= 0.01
                THEN '6_rounding'
            WHEN addl_time > 0.01 AND drop_at_dest = 'true'
                THEN '7_additional_time'
            ELSE '8_unclassified'
        END AS cause_bucket
    FROM base
)

/* ---------------------------------------------------------------------
   OUTPUT 1 — headline for the Slack message.
   Report shocks_net. shocks_gross is kept alongside so the size of the
   correction stays visible and any regression in the fix is obvious.
   --------------------------------------------------------------------- */
SELECT
    MAX(DATEADD('day', -1, CURRENT_DATE()))                       AS report_date,
    country,
    COUNT(*)                                                      AS completed_rides,
    SUM(IFF(fare_diff > 0.01, 1, 0))                              AS shocks_gross,
    SUM(IFF(fare_diff > 0.01 AND is_spillover_recovery, 1, 0))    AS spillover_excluded,
    SUM(IFF(fare_diff > 0.01 AND NOT is_spillover_recovery, 1, 0)) AS shocks_net,
    ROUND(100.0 * SUM(IFF(fare_diff > 0.01 AND NOT is_spillover_recovery, 1, 0))
          / NULLIF(COUNT(*), 0), 2)                               AS pct_shock_net,
    ROUND(SUM(IFF(fare_diff > 0.01 AND NOT is_spillover_recovery, fare_diff, 0)), 2)
                                                                  AS excess_fare_net,
    ROUND(AVG(IFF(fare_diff > 0.01 AND NOT is_spillover_recovery, fare_diff, NULL)), 2)
                                                                  AS avg_overcharge_net,
    MAX(IFF(country = 'SA', 'SAR', 'JOD'))                        AS currency
FROM bucketed
GROUP BY country
ORDER BY country;


/* ---------------------------------------------------------------------
   OUTPUT 2 — cause mix (run as a second statement in the same job).
   Sanity band for a normal day, net of spillover:
     5_waiting ~50%  ·  7_additional_time ~22%  ·  8_unclassified ~16%
     4_prior_unpaid_balance ~11%  ·  2_surcharge ~1%  ·  1_surge_pd ~0.06%
   A day far outside this band is more likely a broken query than a
   changed world — check the join fan-out before escalating.
   ---------------------------------------------------------------------

SELECT
    country,
    cause_bucket,
    COUNT(*)                        AS shock_rides_net,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY country), 2) AS pct_of_net,
    ROUND(SUM(fare_diff), 2)        AS excess_fare_net
FROM bucketed
WHERE fare_diff > 0.01
  AND NOT is_spillover_recovery
GROUP BY country, cause_bucket
ORDER BY country, shock_rides_net DESC;

   ---------------------------------------------------------------------
   OUTPUT 3 — spillover monitor. Worth alerting on separately: if this
   climbs, more small fare increases are being deferred, which is a
   rider-experience signal even though it is excluded from shock counts.
   ---------------------------------------------------------------------

SELECT
    country,
    payment_method,
    card_flag,
    COUNT(*)                 AS recovery_leg_rides,
    ROUND(SUM(cfine), 2)     AS amount_recovered
FROM bucketed
WHERE is_spillover_recovery
GROUP BY country, payment_method, card_flag
ORDER BY country, recovery_leg_rides DESC;
*/
