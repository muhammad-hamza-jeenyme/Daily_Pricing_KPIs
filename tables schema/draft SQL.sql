-- Legacy ride-level draft (superseded by sql/fare_integrity_daily_digest.sql).
-- Kept for reference during validation. Prefer the aggregate digest for daily runs.

WITH BaseData AS (
    SELECT 
        rd.createddate, 
        pc.area_code AS city, 
        ga.country_code AS country,
        rd.rideid,
        uf.UPFRONTSCENARIO, 
        uf.dropoffatdestination, 
        uf.ORIGINALESTIMATEFARE, 
        uf.CHARGINGFARE,
        pc.VALUE AS pc_value, 
        COALESCE(pc.VAT, 0) AS pc_vat, 
        COALESCE(pc.SURCHARGE, 0) AS pc_surcharge_ex_vat,
        ROUND(COALESCE(pc.SURCHARGE, 0) * IFF(ga.country_code = 'SA', 1.15, 1.0), 2) AS pc_surcharge_gross,
        rr.TOTALAMOUNTWITHTAX AS rr_total, 
        COALESCE(rr.CANCELLATIONFINE, 0) AS rr_cancelfine, 
        COALESCE(rr.VATONCANCELLATIONFINE, 0) AS rr_vatcancelfine, 
        COALESCE(rr.WAITINGCHARGES, 0) AS rr_waitingcharges, 
        COALESCE(rr.VATONWAITINGCHARGES, 0) AS rr_vatwaitingcharges, 
        COALESCE(rr.DISCOUNT, 0) AS rr_discount, 
        COALESCE(rr.VATONDISCOUNT, 0) AS rr_vatdiscount
    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.RIDE.UPFRONT uf ON rd.RIDEID = uf.RIDEID
    JOIN JEENY_PROD.RIDE.RECEIPTS rr ON rd.RIDEID = rr.RIDEID
    JOIN JEENY_PROD.GENERAL.AREAS ga ON rd.area_code = ga.area_code
    JOIN JEENY_PROD.PASSENGERS.PRICECHECKS pc 
        ON pc.rideid = rd.rideid 
       AND LOWER(pc.SERVICEFILTER) = LOWER(rd.REQUEST_SERVICE)
    WHERE rd.boarded IS NOT NULL
      AND uf.ORIGINALESTIMATEFARE IS NOT NULL
      AND ga.country_code IN ('SA', 'JO')
      AND rd.createddate >= DATEADD('day', -29, CURRENT_DATE())
      AND rd.createddate < CURRENT_DATE()
)

SELECT 
    *,
    ROUND(pc_value + pc_vat + pc_surcharge_gross, 2) AS pricecheck_shown,
    ROUND(rr_total + rr_discount + rr_vatdiscount, 2) AS normalized_receipt_fare,
    ROUND(rr_cancelfine + rr_vatcancelfine + rr_waitingcharges + rr_vatwaitingcharges, 2) AS non_issue_amount,
    ROUND(
        (rr_total + rr_discount + rr_vatdiscount)
        - (pc_value + pc_vat + pc_surcharge_gross),
        2
    ) AS fare_diff,
    ROUND(
        (rr_total + rr_discount + rr_vatdiscount)
        - (pc_value + pc_vat + pc_surcharge_gross)
        - (rr_cancelfine + rr_vatcancelfine + rr_waitingcharges + rr_vatwaitingcharges),
        2
    ) AS residual,
    CASE
        WHEN ROUND((rr_total + rr_discount + rr_vatdiscount) - (pc_value + pc_vat + pc_surcharge_gross), 2) = 0
            THEN 'matched'
        WHEN ABS(ROUND((rr_total + rr_discount + rr_vatdiscount) - (pc_value + pc_vat + pc_surcharge_gross), 2)) <= 0.01
            THEN 'rounding'
        WHEN ROUND((rr_total + rr_discount + rr_vatdiscount) - (pc_value + pc_vat + pc_surcharge_gross), 2) > 0.01
         AND ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat + pc_surcharge_gross)
                - (rr_cancelfine + rr_vatcancelfine + rr_waitingcharges + rr_vatwaitingcharges),
                2
             ) <= 0.01
            THEN 'increase_non_issue'
        WHEN ROUND((rr_total + rr_discount + rr_vatdiscount) - (pc_value + pc_vat + pc_surcharge_gross), 2) > 0.01
            THEN 'increase_pricing'
        WHEN ROUND((rr_total + rr_discount + rr_vatdiscount) - (pc_value + pc_vat + pc_surcharge_gross), 2) < -0.01
            THEN 'decrease_pricing'
        ELSE 'unclassified'
    END AS issue_type
FROM BaseData;
