-- Fare integrity digest (v1) — RUN THIS for daily / MCP validation
-- Grain: createddate × area_code × upfrontscenario × issue_type
-- Window: last 29 complete Saudi calendar days (excludes today)
-- Compare: PriceCheck shown vs Receipts normalized (discount add-back)
-- Scenarios in prod: withinA | withinB | beyondB
-- Spec: docs/pricing-structure.md | Validation: docs/validation-run-2026-08-04.md

WITH BaseData AS (
    SELECT
        rd.createddate,
        rd.area_code,
        ga.country_code AS country,
        rd.rideid,
        uf.upfrontscenario,
        uf.dropoffatdestination,
        COALESCE(uf.scaleddistance, 0) AS scaleddistance,
        pc.surgemultiplier AS pc_surge,
        pc.discriminationmultiplier AS pc_disc,
        rd.surgemultiplier AS rd_surge,
        rd.discriminationmultiplier AS rd_disc,
        COALESCE(pc.value, 0) AS pc_value,
        COALESCE(pc.vat, 0) AS pc_vat_hailing,
        COALESCE(pc.surcharge, 0) AS pc_surcharge_ex_vat,
        /* PC.SURCHARGE is ex-VAT; hard VAT factor by country */
        ROUND(
            COALESCE(pc.surcharge, 0) * IFF(ga.country_code = 'SA', 1.15, 1.0),
            2
        ) AS pc_surcharge_gross,
        COALESCE(rr.totalamountwithtax, 0) AS rr_total,
        COALESCE(rr.discount, 0) AS rr_discount,
        COALESCE(rr.vatondiscount, 0) AS rr_vatdiscount,
        COALESCE(rr.cancellationfine, 0) AS rr_cancelfine,
        COALESCE(rr.vatoncancellationfine, 0) AS rr_vatcancelfine,
        COALESCE(rr.waitingcharges, 0) AS rr_waitingcharges,
        COALESCE(rr.vatonwaitingcharges, 0) AS rr_vatwaitingcharges
    FROM jeeny_prod.ride.details rd
    JOIN jeeny_prod.ride.upfront uf
        ON rd.rideid = uf.rideid
    JOIN jeeny_prod.ride.receipts rr
        ON rd.rideid = rr.rideid
    JOIN jeeny_prod.general.areas ga
        ON rd.area_code = ga.area_code
    JOIN jeeny_prod.passengers.pricechecks pc
        ON pc.rideid = rd.rideid
       AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
    WHERE rd.boarded IS NOT NULL
      AND uf.originalestimatefare IS NOT NULL
      AND ga.country_code IN ('SA', 'JO')
      AND rd.createddate >= DATEADD('day', -29, CURRENT_DATE())
      AND rd.createddate < CURRENT_DATE()
),

RideFlags AS (
    SELECT
        createddate,
        area_code,
        country,
        rideid,
        upfrontscenario,
        dropoffatdestination,
        scaleddistance,
        ROUND(pc_value + pc_vat_hailing + pc_surcharge_gross, 2) AS pricecheck_shown,
        ROUND(rr_total + rr_discount + rr_vatdiscount, 2) AS normalized_receipt,
        ROUND(
            (rr_total + rr_discount + rr_vatdiscount)
            - (pc_value + pc_vat_hailing + pc_surcharge_gross),
            2
        ) AS fare_diff,
        ROUND(
            rr_cancelfine + rr_vatcancelfine + rr_waitingcharges + rr_vatwaitingcharges,
            2
        ) AS non_issue_amount,
        ROUND(
            (rr_total + rr_discount + rr_vatdiscount)
            - (pc_value + pc_vat_hailing + pc_surcharge_gross)
            - (rr_cancelfine + rr_vatcancelfine + rr_waitingcharges + rr_vatwaitingcharges),
            2
        ) AS residual,
        IFF(ABS(pc_surge - rd_surge) > 0.001, 1, 0) AS surge_mismatch,
        IFF(ABS(pc_disc - rd_disc) > 0.001, 1, 0) AS pd_mismatch,
        IFF(scaleddistance > 0, 1, 0) AS scaled_distance_flag,
        IFF(LOWER(TO_VARCHAR(dropoffatdestination)) = 'false', 1, 0) AS dropoff_not_at_dest
    FROM BaseData
),

Classified AS (
    SELECT
        *,
        CASE
            WHEN fare_diff = 0 THEN 'matched'
            WHEN ABS(fare_diff) <= 0.01 THEN 'rounding'
            WHEN fare_diff > 0.01 AND residual <= 0.01 THEN 'increase_non_issue'
            WHEN fare_diff > 0.01 AND residual > 0.01 THEN 'increase_pricing'
            WHEN fare_diff < -0.01 THEN 'decrease_pricing'
            ELSE 'unclassified'
        END AS issue_type
    FROM RideFlags
)

SELECT
    createddate,
    area_code,
    country,
    upfrontscenario,
    issue_type,
    COUNT(*) AS ride_count,
    ROUND(SUM(fare_diff), 2) AS sum_fare_diff,
    ROUND(AVG(fare_diff), 4) AS avg_fare_diff,
    ROUND(SUM(residual), 2) AS sum_residual,
    ROUND(AVG(residual), 4) AS avg_residual,
    ROUND(SUM(non_issue_amount), 2) AS sum_non_issue,
    SUM(dropoff_not_at_dest) AS dropoff_not_at_dest_rides,
    SUM(scaled_distance_flag) AS scaled_distance_rides,
    SUM(surge_mismatch) AS surge_mismatch_rides,
    SUM(pd_mismatch) AS pd_mismatch_rides
FROM Classified
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1 DESC, 2, 4, 5;
