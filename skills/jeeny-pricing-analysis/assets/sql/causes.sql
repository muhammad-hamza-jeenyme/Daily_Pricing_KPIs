-- WHY: exclusive root-cause buckets, first match wins.
-- Precedence = tech flags (1-3) before contractual (4-5). A REPORTING CHOICE:
-- flipping it moved SA bucket 2 from roughly 4k to ~20.3k with no data change.
-- State the precedence version AND the denominator in any output.
--   gap_filter 'strict'   -> fare_diff > 0.01  (bucket 6 definitionally empty)
--   gap_filter 'positive' -> fare_diff > 0     (bucket 6 visible, totals ~4% higher)
-- Bucket detail, confidence and validated volumes: references/baselines.md §3.

WITH params AS (
    SELECT DATEADD('day', -30, CURRENT_DATE()) AS win_start,
           CURRENT_DATE()                      AS win_end
),

BaseRides AS (
    SELECT
        rd.rideid, rd.createddate, rd.area_code,
        ga.country_code                       AS country,
        uf.upfrontscenario, uf.dropoffatdestination,
        COALESCE(uf.scaleddistance, 0)        AS scaleddistance,
        COALESCE(uf.additionaltimevalue, 0)   AS additionaltimevalue,
        COALESCE(uf.additionaltimecomp, 0)    AS additionaltimecomp,
        uf.actualtime, uf.appliedestimatetime,          -- MINUTES
        uf.timethreshholdsahighvalue,                   -- SECONDS
        uf.appliedfixedtimethresholdapplied,
        uf.originalestimatefare, uf.appliedestimatefare,
        uf.chargingdistancesource, uf.chargingtimesource, uf.chargingfare,

        -- NOT coalesced on purpose: a NULL forced to 0 reads as a false mismatch
        pc.surgemultiplier                    AS pc_surge,
        pc.discriminationmultiplier           AS pc_pd,
        rd.surgemultiplier                    AS rd_surge,
        rd.discriminationmultiplier           AS rd_pd,

        -- quote side
        COALESCE(pc.value, 0)                 AS pc_value,           -- incl. SA ride VAT
        COALESCE(pc.vat, 0)                   AS pc_vat_hailing,     -- hailing, NOT ride VAT
        COALESCE(pc.surcharge, 0)             AS pc_surcharge_ex_vat,
        ROUND(COALESCE(pc.surcharge, 0) * IFF(ga.country_code = 'SA', 1.15, 1.0), 2)
                                              AS pc_surcharge_gross,
        pc.pickuplat, pc.pickuplong,

        -- end-of-ride surcharge for the bucket-2 ex-VAT compare
        COALESCE(rd.surcharge, 0)             AS rd_surcharge,
        COALESCE(rd.intercitysurcharge, 0)    AS rd_intercitysurcharge,

        -- charged side, line by line (needed for the decomposition)
        COALESCE(rr.totalamountwithtax, 0)    AS rr_total,
        COALESCE(rr.discount, 0)              AS rr_discount,
        COALESCE(rr.vatondiscount, 0)         AS rr_vatdiscount,
        COALESCE(rr.ridevalue, 0)             AS rr_ridevalue,
        COALESCE(rr.vatonridevalue, 0)        AS rr_vatridevalue,
        COALESCE(rr.ridehailingsurcharge, 0)  AS rr_hailing,
        COALESCE(rr.vatonridehailingsurcharge, 0) AS rr_vathailing,
        COALESCE(rr.surcharge, 0)             AS rr_surcharge,
        COALESCE(rr.vatonsurcharge, 0)        AS rr_vatsurcharge,
        COALESCE(rr.intercitysurcharge, 0)    AS rr_intercity,
        COALESCE(rr.vatonintercitysurcharge, 0) AS rr_vatintercity,
        COALESCE(rr.cancellationfine, 0)      AS rr_cancelfine,
        COALESCE(rr.vatoncancellationfine, 0) AS rr_vatcancelfine,
        COALESCE(rr.waitingcharges, 0)        AS rr_waiting,
        COALESCE(rr.vatonwaitingcharges, 0)   AS rr_vatwaiting
    FROM jeeny_prod.ride.details rd
    JOIN jeeny_prod.ride.upfront  uf ON rd.rideid = uf.rideid
    JOIN jeeny_prod.ride.receipts rr ON rd.rideid = rr.rideid
    JOIN jeeny_prod.general.areas ga ON rd.area_code = ga.area_code
    JOIN jeeny_prod.passengers.pricechecks pc
        ON  pc.rideid = rd.rideid
        AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
    CROSS JOIN params p
    WHERE rd.boarded IS NOT NULL
      AND uf.originalestimatefare IS NOT NULL
      AND ga.country_code IN ('SA', 'JO')
      AND rd.createddate >= p.win_start
      AND rd.createddate <  p.win_end
    QUALIFY ROW_NUMBER() OVER (PARTITION BY rd.rideid
                               ORDER BY pc.actualdatetime DESC NULLS LAST) = 1
),

Scored AS (
    SELECT
        b.*,
        ROUND(b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross, 2) AS pricecheck_shown,
        ROUND(b.rr_total + b.rr_discount + b.rr_vatdiscount, 2)        AS normalized_receipt,
        ROUND((b.rr_total + b.rr_discount + b.rr_vatdiscount)
            - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2) AS fare_diff,
        ROUND(b.rr_waiting + b.rr_vatwaiting + b.rr_cancelfine + b.rr_vatcancelfine, 2)
                                                                       AS non_issue,
        -- exact split of fare_diff (validated 100/100); residual = the three deltas
        ROUND((b.rr_ridevalue + b.rr_vatridevalue) - b.pc_value, 2)    AS d_ridevalue,
        ROUND((b.rr_hailing + b.rr_vathailing) - b.pc_vat_hailing, 2)  AS d_hailing,
        ROUND((b.rr_surcharge + b.rr_vatsurcharge + b.rr_intercity + b.rr_vatintercity)
            - b.pc_surcharge_gross, 2)                                 AS d_surcharge
    FROM BaseRides b
),

Classified AS (
    SELECT s.*,
        ROUND(s.fare_diff - s.non_issue, 2) AS residual,
        CASE WHEN s.fare_diff = 0                              THEN 'matched'
             WHEN ABS(s.fare_diff) <= 0.01                     THEN 'rounding'
             WHEN s.fare_diff > 0.01
              AND ROUND(s.fare_diff - s.non_issue, 2) <= 0.01  THEN 'increase_non_issue'
             WHEN s.fare_diff > 0.01                           THEN 'increase_pricing'
             WHEN s.fare_diff < -0.01                          THEN 'decrease_pricing'
             ELSE 'unclassified' END AS issue_type
    FROM Scored s
)

, OfferEvent AS (   -- first ride_offered location; only needed for bucket 3
    SELECT e.id AS rideid, e.location_lat, e.location_lng
    FROM jeeny_prod.ride.eventhistory e
    CROSS JOIN params p
    WHERE e.event_name = 'ride_offered'
      AND e.triggered_at >= p.win_start
      AND e.triggered_at <  DATEADD('day', 2, p.win_end)
      AND e.location_lat IS NOT NULL AND e.location_lng IS NOT NULL
      AND e.location_lat BETWEEN -90 AND 90
      AND e.location_lng BETWEEN -180 AND 180
      AND NOT (e.location_lat = 0 AND e.location_lng = 0)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY e.id ORDER BY e.triggered_at) = 1
),

Bucketed AS (
    SELECT c.*,
        CASE
          -- 1 TECH BUG (hyp): quote and ride priced on different multipliers
          WHEN ROUND(c.pc_surge, 4) <> ROUND(c.rd_surge, 4)
            OR ROUND(c.pc_pd, 4)    <> ROUND(c.rd_pd, 4)
            THEN '1_surge_or_pd_mismatch'
          -- 2 TECH BUG (hyp): surcharge moved with no re-Google. Ex-VAT both sides,
          --   INTERCITYSURCHARGE included or every intercity ride looks broken.
          WHEN LOWER(c.upfrontscenario) = 'withina'
           AND LOWER(TO_VARCHAR(c.dropoffatdestination)) = 'true'
           AND ROUND(c.rd_surcharge + c.rd_intercitysurcharge, 2)
               <> ROUND(c.pc_surcharge_ex_vat, 2)
            THEN '2_surcharge_mismatch_withina_dest'
          -- 3 TECH BUG, LOW confidence: proxy, not a measurement
          WHEN oe.location_lat IS NOT NULL
           AND c.pickuplat IS NOT NULL AND c.pickuplong IS NOT NULL
           AND c.pickuplat  BETWEEN -90 AND 90
           AND c.pickuplong BETWEEN -180 AND 180
           AND NOT (c.pickuplat = 0 AND c.pickuplong = 0)
           AND ST_DISTANCE(TO_GEOGRAPHY(ST_MAKEPOINT(c.pickuplong, c.pickuplat)),
                           TO_GEOGRAPHY(ST_MAKEPOINT(oe.location_lng, oe.location_lat))) > 100
            THEN '3_incorrect_pickup_google_estimate'
          WHEN (c.rr_cancelfine + c.rr_vatcancelfine) > 0.01 THEN '4_prev_cancellation_fine'
          WHEN (c.rr_waiting + c.rr_vatwaiting)       > 0.01 THEN '5_waiting_time_charges'
          WHEN c.fare_diff > 0 AND c.fare_diff <= 0.01       THEN '6_rounding_0_01'
          WHEN c.additionaltimevalue > 0.01
           AND LOWER(TO_VARCHAR(c.dropoffatdestination)) = 'true'
            THEN '7_additional_time_value'
          ELSE '8_unclassified'
        END AS cause_bucket
    FROM Classified c
    LEFT JOIN OfferEvent oe ON oe.rideid = c.rideid
    WHERE c.fare_diff > 0.01              -- 'strict'; use > 0 for 'positive'
)

SELECT country, cause_bucket,
       COUNT(*) AS rides,
       ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY country), 0), 2)
            AS pct_of_market,
       ROUND(AVG(fare_diff), 2) AS avg_gap,
       ROUND(SUM(fare_diff), 2) AS total_gap,
       -- which component drove each bucket
       ROUND(SUM(d_ridevalue), 2) AS sum_d_ridevalue,
       ROUND(SUM(d_surcharge), 2) AS sum_d_surcharge,
       ROUND(SUM(d_hailing), 2)   AS sum_d_hailing,
       ROUND(SUM(non_issue), 2)   AS sum_non_issue
FROM Bucketed
GROUP BY 1, 2
ORDER BY country, cause_bucket;