-- Canonical scaffold. Build every price-shock query on this.
-- Encodes: service-matched + de-duplicated PriceCheck join; money COALESCEd but
-- multipliers deliberately not; country surcharge gross-up kept alongside ex-VAT;
-- and the exact Fare_Diff decomposition (SKILL.md §3).
-- Swap the final SELECT for your own aggregation. Aggregate in Snowflake.

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

SELECT country, issue_type,
       COUNT(*) AS rides,
       ROUND(SUM(fare_diff), 2) AS sum_fare_diff,   -- local currency; never combine markets
       ROUND(AVG(fare_diff), 2) AS avg_fare_diff
FROM Classified
GROUP BY 1, 2
ORDER BY 1, 2;
