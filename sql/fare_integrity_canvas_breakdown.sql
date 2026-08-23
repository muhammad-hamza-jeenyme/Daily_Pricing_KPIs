-- Canvas-only metrics: scenario NET shock rates + exclusive GROSS cause mix
-- Spec: docs/alert-rules.md | memory/PROJECT_CONTEXT.md
-- Companion to: sql/fare_integrity_channel_summary.sql
--
-- OUTPUT A (grain = scenario_city | scenario_country):
--   NET shock rate by scenario segment.
--   NET shock = Fare_Diff > 0.01 AND NOT spillover recovery.
--   pct_shock = 100 * NET shocks in segment / ALL completed rides (contribution rate;
--     same denominator as channel Cumulative PriceShocks %).
--   Segments:
--     withinA_at_dest  — withinA + dropoffatdestination = 'true'
--     withinA_not_dest — withinA + dropoff <> 'true' (null/false = not dest)
--     withinB_at_dest  — withinB + dropoff = 'true'
--     withinB_not_dest — withinB + not at dest
--     beyondB          — beyondB (no dropoff split)
--
-- OUTPUT B (grain = cause_mix, report_date only, country level):
--   Among rides with Fare_Diff > 0.01 (GROSS — includes spillover recovery),
--   exclusive first-match cause. pct_shock = 100 * bucket / gross shocks.
--   Buckets per country must sum ≈ 100% (agent verifies; no TOTAL_CHECK row).
--   Precedence (exact order):
--     1. pickup_mismatch
--     2. pd_mismatch          (both PD multipliers non-null, differ at 4dp)
--     3. surge_mismatch       (both surge non-null, differ at 4dp)
--     4. surcharge_mismatch   (withinA + dropoff true + surcharge ex-VAT mismatch)
--     5. previous_wallet_balance  (is_spillover_recovery)
--     6. waiting_time         ((wait + vwait) > 0.01)
--     7. withinA_at_dest
--     8. withinA_not_dest
--     9. withinB_at_dest
--    10. withinB_not_dest
--    11. beyondB
--    12. unclassified
--
-- SPILLOVER (LOOKBACK_DAYS = 30 — do not shrink):
--   Exclude recovery leg: ZEROIFNULL(prev_outs) > 0
--     AND ABS(prev_outs - CANCELLATIONFINE) <= 0.02.
--   Lookback starts 30 days BEFORE win_start so DoD/WoW/MoM days still see prior outs.
--
-- Fare_Diff (locked):
--   Norm receipt = TOTALAMOUNTWITHTAX + DISCOUNT + VATONDISCOUNT
--   Shown = VALUE + VAT(hailing) + ROUND(SURCHARGE * IFF(SA,1.15,1.0), 2)
--   Fare_Diff = ROUND(Norm receipt - Shown, 2)
--
-- City buckets: SA RUH/JED/MAD/DMM/MEC/Others | JO AMM/IRB/ZRQ/Others

WITH params AS (
    SELECT
        DATEADD('day', -1, CURRENT_DATE()) AS report_date,
        DATEADD('day', -2, CURRENT_DATE()) AS dod_date,
        DATEADD('day', -8, CURRENT_DATE()) AS wow_date,
        DATEADD('day', -29, CURRENT_DATE()) AS mom_date,
        DATEADD('day', -29, CURRENT_DATE()) AS win_start,
        CURRENT_DATE() AS win_end,
        /* Spillover LAG must see rides before every day in [win_start, win_end) */
        DATEADD('day', -30, DATEADD('day', -29, CURRENT_DATE())) AS lookback_start,
        30 AS lookback_days
),

LookbackRides AS (
    SELECT
        rd.rideid,
        rd.passengerid,
        rd.created,
        rd.outstandingbalance AS outs
    FROM jeeny_prod.ride.details rd
    JOIN jeeny_prod.general.areas ga ON rd.area_code = ga.area_code
    CROSS JOIN params p
    WHERE rd.createddate >= p.lookback_start
      AND rd.createddate < p.win_end
      AND ga.country_code IN ('SA', 'JO')
),

PrevOuts AS (
    SELECT
        rideid,
        LAG(outs) OVER (PARTITION BY passengerid ORDER BY created) AS prev_outs
    FROM LookbackRides
),

BaseRides AS (
    SELECT
        rd.rideid,
        rd.passengerid,
        rd.createddate,
        rd.area_code,
        ga.country_code AS country,
        CASE
            WHEN ga.country_code = 'SA' AND rd.area_code IN ('RUH', 'JED', 'MAD', 'DMM', 'MEC')
                THEN rd.area_code
            WHEN ga.country_code = 'JO' AND rd.area_code IN ('AMM', 'IRB', 'ZRQ')
                THEN rd.area_code
            ELSE 'Others'
        END AS city_bucket,
        uf.upfrontscenario,
        uf.dropoffatdestination,
        COALESCE(pc.value, 0) AS pc_value,
        COALESCE(pc.vat, 0) AS pc_vat_hailing,
        ROUND(COALESCE(pc.surcharge, 0) * IFF(ga.country_code = 'SA', 1.15, 1.0), 2) AS pc_surcharge_gross,
        COALESCE(pc.surcharge, 0) AS pc_surcharge_ex_vat,
        COALESCE(rd.surcharge, 0) AS rd_surcharge,
        COALESCE(rd.intercitysurcharge, 0) AS rd_intercitysurcharge,
        pc.surgemultiplier AS pc_surge,
        rd.surgemultiplier AS rd_surge,
        pc.discriminationmultiplier AS pc_pd,
        rd.discriminationmultiplier AS rd_pd,
        COALESCE(rr.totalamountwithtax, 0) AS rr_total,
        COALESCE(rr.discount, 0) AS rr_discount,
        COALESCE(rr.vatondiscount, 0) AS rr_vatdiscount,
        COALESCE(rr.cancellationfine, 0) AS rr_cancelfine,
        COALESCE(rr.waitingcharges, 0) AS rr_waitingcharges,
        COALESCE(rr.vatonwaitingcharges, 0) AS rr_vatwaitingcharges,
        pv.prev_outs,
        pc.pickuplat,
        pc.pickuplong
    FROM jeeny_prod.ride.details rd
    JOIN jeeny_prod.ride.upfront uf ON rd.rideid = uf.rideid
    JOIN jeeny_prod.ride.receipts rr ON rd.rideid = rr.rideid
    JOIN jeeny_prod.general.areas ga ON rd.area_code = ga.area_code
    JOIN jeeny_prod.passengers.pricechecks pc
        ON pc.rideid = rd.rideid
       AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
    LEFT JOIN PrevOuts pv ON pv.rideid = rd.rideid
    CROSS JOIN params p
    WHERE rd.boarded IS NOT NULL
      AND uf.originalestimatefare IS NOT NULL
      AND ga.country_code IN ('SA', 'JO')
      AND rd.createddate >= p.win_start
      AND rd.createddate < p.win_end
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY rd.rideid
        ORDER BY pc.actualdatetime DESC NULLS LAST
    ) = 1
),

OfferEvent AS (
    SELECT
        e.id AS rideid,
        e.location_lat,
        e.location_lng
    FROM jeeny_prod.ride.eventhistory e
    CROSS JOIN params p
    WHERE e.event_name = 'ride_offered'
      AND e.triggered_at >= p.win_start
      AND e.triggered_at < DATEADD('day', 2, p.win_end)
      AND e.location_lat IS NOT NULL
      AND e.location_lng IS NOT NULL
      AND e.location_lat BETWEEN -90 AND 90
      AND e.location_lng BETWEEN -180 AND 180
      AND NOT (e.location_lat = 0 AND e.location_lng = 0)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY e.id ORDER BY e.triggered_at) = 1
),

Classified AS (
    SELECT
        b.createddate,
        b.country,
        b.city_bucket,
        b.rideid,
        LOWER(b.upfrontscenario) AS scenario,
        LOWER(TO_VARCHAR(b.dropoffatdestination)) AS dropoff,
        ROUND(
            (b.rr_total + b.rr_discount + b.rr_vatdiscount)
            - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2
        ) AS fare_diff,
        IFF(
            ZEROIFNULL(b.prev_outs) > 0
            AND ABS(b.prev_outs - b.rr_cancelfine) <= 0.02,
            1, 0
        ) AS is_spillover_recovery,
        /* NET cumulative price shock */
        CASE
            WHEN ROUND(
                (b.rr_total + b.rr_discount + b.rr_vatdiscount)
                - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2
            ) > 0.01
             AND NOT (
                ZEROIFNULL(b.prev_outs) > 0
                AND ABS(b.prev_outs - b.rr_cancelfine) <= 0.02
             )
            THEN 1 ELSE 0
        END AS is_net_shock,
        CASE
            WHEN b.pickuplat IS NOT NULL
             AND b.pickuplong IS NOT NULL
             AND b.pickuplat BETWEEN -90 AND 90
             AND b.pickuplong BETWEEN -180 AND 180
             AND NOT (b.pickuplat = 0 AND b.pickuplong = 0)
             AND oe.location_lat IS NOT NULL
             AND ST_DISTANCE(
                    TO_GEOGRAPHY(ST_MAKEPOINT(b.pickuplong, b.pickuplat)),
                    TO_GEOGRAPHY(ST_MAKEPOINT(oe.location_lng, oe.location_lat))
                 ) > 100
            THEN 1 ELSE 0
        END AS is_pickup_mismatch,
        CASE
            WHEN b.pc_pd IS NOT NULL
             AND b.rd_pd IS NOT NULL
             AND ROUND(b.pc_pd, 4) <> ROUND(b.rd_pd, 4)
            THEN 1 ELSE 0
        END AS is_pd_mismatch,
        CASE
            WHEN b.pc_surge IS NOT NULL
             AND b.rd_surge IS NOT NULL
             AND ROUND(b.pc_surge, 4) <> ROUND(b.rd_surge, 4)
            THEN 1 ELSE 0
        END AS is_surge_mismatch,
        CASE
            WHEN LOWER(b.upfrontscenario) = 'withina'
             AND LOWER(TO_VARCHAR(b.dropoffatdestination)) = 'true'
             AND ROUND(b.rd_surcharge + b.rd_intercitysurcharge, 2)
                 != ROUND(b.pc_surcharge_ex_vat, 2)
            THEN 1 ELSE 0
        END AS is_surcharge_mismatch,
        IFF(
            (COALESCE(b.rr_waitingcharges, 0) + COALESCE(b.rr_vatwaitingcharges, 0)) > 0.01,
            1, 0
        ) AS is_waiting_time,
        /* Scenario segment for OUTPUT A (NULL = unknown scenario, excluded) */
        CASE
            WHEN LOWER(b.upfrontscenario) = 'withina'
             AND LOWER(TO_VARCHAR(b.dropoffatdestination)) = 'true'
                THEN 'withinA_at_dest'
            WHEN LOWER(b.upfrontscenario) = 'withina'
                THEN 'withinA_not_dest'
            WHEN LOWER(b.upfrontscenario) = 'withinb'
             AND LOWER(TO_VARCHAR(b.dropoffatdestination)) = 'true'
                THEN 'withinB_at_dest'
            WHEN LOWER(b.upfrontscenario) = 'withinb'
                THEN 'withinB_not_dest'
            WHEN LOWER(b.upfrontscenario) = 'beyondb'
                THEN 'beyondB'
            ELSE NULL
        END AS scenario_segment
    FROM BaseRides b
    LEFT JOIN OfferEvent oe ON oe.rideid = b.rideid
),

/* ---------- OUTPUT A: daily segment contribution rates (city + country) ----------
   pct_shock = 100 * (NET shocks in segment) / (all completed rides in city|country)
   Same denominator as channel Cumulative — segment rates are additive contributions.
*/

SegmentList AS (
    SELECT column1 AS segment FROM VALUES
        ('withinA_at_dest'),
        ('withinA_not_dest'),
        ('withinB_at_dest'),
        ('withinB_not_dest'),
        ('beyondB')
),

DailyCitySegment AS (
    SELECT
        c.createddate,
        c.country,
        c.city_bucket,
        s.segment,
        COUNT(*) AS ride_count,
        ROUND(
            100.0 * SUM(IFF(c.scenario_segment = s.segment AND c.is_net_shock = 1, 1, 0))
            / NULLIF(COUNT(*), 0),
            2
        ) AS pct_shock
    FROM Classified c
    CROSS JOIN SegmentList s
    GROUP BY 1, 2, 3, 4
),

DailyCountrySegment AS (
    SELECT
        c.createddate,
        c.country,
        s.segment,
        COUNT(*) AS ride_count,
        ROUND(
            100.0 * SUM(IFF(c.scenario_segment = s.segment AND c.is_net_shock = 1, 1, 0))
            / NULLIF(COUNT(*), 0),
            2
        ) AS pct_shock
    FROM Classified c
    CROSS JOIN SegmentList s
    GROUP BY 1, 2, 3
),

CityYesterday AS (
    SELECT c.* FROM DailyCitySegment c CROSS JOIN params p WHERE c.createddate = p.report_date
),
CityDoD AS (
    SELECT * FROM DailyCitySegment CROSS JOIN params p WHERE createddate = p.dod_date
),
CityWoW AS (
    SELECT * FROM DailyCitySegment CROSS JOIN params p WHERE createddate = p.wow_date
),
CityMoM AS (
    SELECT * FROM DailyCitySegment CROSS JOIN params p WHERE createddate = p.mom_date
),

CountryYesterday AS (
    SELECT c.* FROM DailyCountrySegment c CROSS JOIN params p WHERE c.createddate = p.report_date
),
CountryDoD AS (
    SELECT * FROM DailyCountrySegment CROSS JOIN params p WHERE createddate = p.dod_date
),
CountryWoW AS (
    SELECT * FROM DailyCountrySegment CROSS JOIN params p WHERE createddate = p.wow_date
),
CountryMoM AS (
    SELECT * FROM DailyCountrySegment CROSS JOIN params p WHERE createddate = p.mom_date
),

ScenarioCity AS (
    SELECT
        'scenario_city' AS grain,
        y.createddate AS report_date,
        y.country,
        y.city_bucket,
        y.segment,
        y.ride_count,
        y.pct_shock,
        ROUND(y.pct_shock - d.pct_shock, 2) AS dod_delta_pp,
        ROUND(y.pct_shock - w.pct_shock, 2) AS wow_delta_pp,
        ROUND(y.pct_shock - m.pct_shock, 2) AS mom_delta_pp
    FROM CityYesterday y
    LEFT JOIN CityDoD d
        ON y.country = d.country AND y.city_bucket = d.city_bucket AND y.segment = d.segment
    LEFT JOIN CityWoW w
        ON y.country = w.country AND y.city_bucket = w.city_bucket AND y.segment = w.segment
    LEFT JOIN CityMoM m
        ON y.country = m.country AND y.city_bucket = m.city_bucket AND y.segment = m.segment
),

ScenarioCountry AS (
    SELECT
        'scenario_country' AS grain,
        y.createddate AS report_date,
        y.country,
        CAST(NULL AS VARCHAR) AS city_bucket,
        y.segment,
        y.ride_count,
        y.pct_shock,
        ROUND(y.pct_shock - d.pct_shock, 2) AS dod_delta_pp,
        ROUND(y.pct_shock - w.pct_shock, 2) AS wow_delta_pp,
        ROUND(y.pct_shock - m.pct_shock, 2) AS mom_delta_pp
    FROM CountryYesterday y
    LEFT JOIN CountryDoD d
        ON y.country = d.country AND y.segment = d.segment
    LEFT JOIN CountryWoW w
        ON y.country = w.country AND y.segment = w.segment
    LEFT JOIN CountryMoM m
        ON y.country = m.country AND y.segment = m.segment
),

/* ---------- OUTPUT B: exclusive GROSS cause mix (report_date, country) ---------- */

GrossShocks AS (
    SELECT
        c.*,
        CASE
            WHEN c.is_pickup_mismatch = 1 THEN 'pickup_mismatch'
            WHEN c.is_pd_mismatch = 1 THEN 'pd_mismatch'
            WHEN c.is_surge_mismatch = 1 THEN 'surge_mismatch'
            WHEN c.is_surcharge_mismatch = 1 THEN 'surcharge_mismatch'
            WHEN c.is_spillover_recovery = 1 THEN 'previous_wallet_balance'
            WHEN c.is_waiting_time = 1 THEN 'waiting_time'
            WHEN c.scenario = 'withina' AND c.dropoff = 'true' THEN 'withinA_at_dest'
            WHEN c.scenario = 'withina' THEN 'withinA_not_dest'
            WHEN c.scenario = 'withinb' AND c.dropoff = 'true' THEN 'withinB_at_dest'
            WHEN c.scenario = 'withinb' THEN 'withinB_not_dest'
            WHEN c.scenario = 'beyondb' THEN 'beyondB'
            ELSE 'unclassified'
        END AS cause_bucket
    FROM Classified c
    CROSS JOIN params p
    WHERE c.createddate = p.report_date
      AND c.fare_diff > 0.01
),

CauseMix AS (
    SELECT
        'cause_mix' AS grain,
        p.report_date,
        g.country,
        CAST(NULL AS VARCHAR) AS city_bucket,
        g.cause_bucket AS segment,
        COUNT(*) AS ride_count,
        ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY g.country), 0), 2) AS pct_shock,
        CAST(NULL AS FLOAT) AS dod_delta_pp,
        CAST(NULL AS FLOAT) AS wow_delta_pp,
        CAST(NULL AS FLOAT) AS mom_delta_pp
    FROM GrossShocks g
    CROSS JOIN params p
    GROUP BY p.report_date, g.country, g.cause_bucket
)

SELECT grain, report_date, country, city_bucket, segment, ride_count,
       pct_shock, dod_delta_pp, wow_delta_pp, mom_delta_pp
FROM ScenarioCity

UNION ALL

SELECT grain, report_date, country, city_bucket, segment, ride_count,
       pct_shock, dod_delta_pp, wow_delta_pp, mom_delta_pp
FROM ScenarioCountry

UNION ALL

SELECT grain, report_date, country, city_bucket, segment, ride_count,
       pct_shock, dod_delta_pp, wow_delta_pp, mom_delta_pp
FROM CauseMix

ORDER BY country, grain, segment, city_bucket;
