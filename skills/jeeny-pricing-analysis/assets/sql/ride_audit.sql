-- ONE RIDE, every input side by side. For a complaining passenger or a suspicious ride.
-- Read the output in SKILL.md §5 order; the first line that breaks is the answer.
-- Replace the rideid list. Safe to pass several ids.

WITH ids AS (SELECT column1 AS rideid FROM VALUES ('<RIDEID_1>'), ('<RIDEID_2>')),

R AS (
    SELECT
        rd.rideid, rd.createddate, rd.area_code, ga.country_code AS country,
        rd.request_service,

        -- quote
        pc.actualdatetime          AS pc_time,
        pc.servicefilter,
        pc.value                   AS pc_value,
        pc.vat                     AS pc_vat_hailing,
        pc.surcharge               AS pc_surcharge_ex_vat,
        ROUND(COALESCE(pc.surcharge,0) * IFF(ga.country_code='SA',1.15,1.0), 2) AS pc_surcharge_gross,
        pc.basefare, pc.minimumfare,
        pc.distance                AS pc_distance_km,
        pc.duration                AS pc_duration_min,
        pc.surgemultiplier         AS pc_surge,
        pc.discriminationmultiplier AS pc_pd,
        pc.randomisation_israndomised, pc.randomisation_basesurge, pc.randomisation_finalsurge,
        pc.pickuplat, pc.pickuplong, pc.destlat, pc.destlong,

        -- ride-side multipliers and surcharge (buckets 1 and 2)
        rd.surgemultiplier         AS rd_surge,
        rd.discriminationmultiplier AS rd_pd,
        rd.surcharge               AS rd_surcharge,
        rd.intercitysurcharge      AS rd_intercitysurcharge,
        rd.addresssourcespickup, rd.addresssourcesdestination,
        rd.destinationareacode, rd.requesteddestinationareacode,

        -- upfront: scenario and charging path
        uf.upfrontscenario, uf.dropoffatdestination,
        uf.originalestimatefare, uf.originalestimatetime, uf.originalestimatedistance,
        uf.appliedestimatefare,  uf.appliedestimatetime,  uf.appliedestimatedistance,
        uf.recalculatedfare, uf.taximeterfare, uf.taximeterformula,
        uf.taximetercase, uf.taximeterstate,
        uf.chargingdistance, uf.chargingdistancesource,
        uf.chargingtime,     uf.chargingtimesource,
        uf.chargingfare, uf.finalridefare,
        uf.actualtime, uf.additionaltimecomp, uf.additionaltimevalue,
        uf.factorforadditionaltime,
        uf.appliedfixedtimethresholdapplied, uf.appliedfixedtimethresholdvalue,
        uf.timethreshholdsahighvalue, uf.timethreshholdsahighpercentage,
        uf.timethreshholdsbhighvalue,
        uf.scaleddistance, uf.actualspeed, uf.estimatedspeed, uf.maxspeed,

        -- receipt line items
        rr.ridevalue, rr.vatonridevalue,
        rr.ridehailingsurcharge, rr.vatonridehailingsurcharge,
        rr.surcharge AS rr_surcharge, rr.vatonsurcharge,
        rr.intercitysurcharge AS rr_intercity, rr.vatonintercitysurcharge,
        rr.waitingcharges, rr.vatonwaitingcharges,
        rr.cancellationfine, rr.vatoncancellationfine,
        rr.discount, rr.vatondiscount,
        rr.totalamountwithtax, rr.unroundedridefinalvalue
    FROM jeeny_prod.ride.details rd
    JOIN ids                      i  ON i.rideid  = rd.rideid
    JOIN jeeny_prod.ride.upfront  uf ON rd.rideid = uf.rideid
    JOIN jeeny_prod.ride.receipts rr ON rd.rideid = rr.rideid
    JOIN jeeny_prod.general.areas ga ON rd.area_code = ga.area_code
    JOIN jeeny_prod.passengers.pricechecks pc
        ON  pc.rideid = rd.rideid
        AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY rd.rideid
                               ORDER BY pc.actualdatetime DESC NULLS LAST) = 1
)

SELECT
    R.*,
    -- the locked comparison
    ROUND(COALESCE(pc_value,0) + COALESCE(pc_vat_hailing,0) + COALESCE(pc_surcharge_gross,0), 2)
        AS pricecheck_shown,
    ROUND(COALESCE(totalamountwithtax,0) + COALESCE(discount,0) + COALESCE(vatondiscount,0), 2)
        AS normalized_receipt,
    ROUND((COALESCE(totalamountwithtax,0) + COALESCE(discount,0) + COALESCE(vatondiscount,0))
        - (COALESCE(pc_value,0) + COALESCE(pc_vat_hailing,0) + COALESCE(pc_surcharge_gross,0)), 2)
        AS fare_diff,
    ROUND(COALESCE(waitingcharges,0) + COALESCE(vatonwaitingcharges,0)
        + COALESCE(cancellationfine,0) + COALESCE(vatoncancellationfine,0), 2) AS non_issue,

    -- decomposition: which component moved
    ROUND((COALESCE(ridevalue,0) + COALESCE(vatonridevalue,0)) - COALESCE(pc_value,0), 2)
        AS d_ridevalue,
    ROUND((COALESCE(ridehailingsurcharge,0) + COALESCE(vatonridehailingsurcharge,0))
        - COALESCE(pc_vat_hailing,0), 2) AS d_hailing,
    ROUND((COALESCE(rr_surcharge,0) + COALESCE(vatonsurcharge,0)
         + COALESCE(rr_intercity,0) + COALESCE(vatonintercitysurcharge,0))
        - COALESCE(pc_surcharge_gross,0), 2) AS d_surcharge,

    -- per-bucket flags
    IFF(ROUND(COALESCE(pc_surge,0),4) <> ROUND(COALESCE(rd_surge,0),4)
     OR ROUND(COALESCE(pc_pd,0),4)    <> ROUND(COALESCE(rd_pd,0),4), TRUE, FALSE)
        AS flag_surge_pd_mismatch,
    IFF(LOWER(upfrontscenario) = 'withina'
    AND LOWER(TO_VARCHAR(dropoffatdestination)) = 'true'
    AND ROUND(COALESCE(rd_surcharge,0) + COALESCE(rd_intercitysurcharge,0), 2)
        <> ROUND(COALESCE(pc_surcharge_ex_vat,0), 2), TRUE, FALSE)
        AS flag_surcharge_mismatch,
    -- additional-time arithmetic check: should reconcile to ADDITIONALTIMEVALUE
    ROUND(COALESCE(additionaltimecomp,0) * COALESCE(factorforadditionaltime,0), 2)
        AS additional_time_recomputed,
    ROUND(COALESCE(actualtime,0) - COALESCE(appliedestimatetime,0), 2)
        AS actual_minus_applied_min,
    ROUND(COALESCE(actualtime,0) * 60, 0)      AS actualtime_seconds,   -- vs threshold (seconds)
    IFF(ROUND(COALESCE(appliedestimatefare,0),2) <> ROUND(COALESCE(originalestimatefare,0),2),
        TRUE, FALSE)                           AS flag_re_estimated
FROM R;
