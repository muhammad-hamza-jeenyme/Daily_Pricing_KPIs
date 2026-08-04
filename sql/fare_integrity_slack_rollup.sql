-- Fare integrity rollup for Slack (v1)
-- Watchlist cities only: RUH, JED, MAD, DMM, MEC, AMM, IRB, ZRQ
-- Outputs yesterday KPIs with DoD, WoW, MoM, and vs prior-14d average
-- Watch flag: yesterday_value > avg(prior 14 complete days)
-- Spec: docs/alert-rules.md

WITH params AS (
    SELECT
        DATEADD('day', -1, CURRENT_DATE()) AS report_date,
        DATEADD('day', -2, CURRENT_DATE()) AS dod_date,
        DATEADD('day', -8, CURRENT_DATE()) AS wow_date,
        DATEADD('day', -29, CURRENT_DATE()) AS mom_date,
        DATEADD('day', -15, CURRENT_DATE()) AS avg14_start,  -- yesterday-14
        DATEADD('day', -2, CURRENT_DATE()) AS avg14_end      -- yesterday-1
),

BaseData AS (
    SELECT
        rd.createddate,
        rd.area_code,
        ga.country_code AS country,
        uf.upfrontscenario,
        COALESCE(uf.scaleddistance, 0) AS scaleddistance,
        COALESCE(pc.value, 0) AS pc_value,
        COALESCE(pc.vat, 0) AS pc_vat_hailing,
        ROUND(COALESCE(pc.surcharge, 0) * IFF(ga.country_code = 'SA', 1.15, 1.0), 2) AS pc_surcharge_gross,
        COALESCE(rr.totalamountwithtax, 0) AS rr_total,
        COALESCE(rr.discount, 0) AS rr_discount,
        COALESCE(rr.vatondiscount, 0) AS rr_vatdiscount,
        COALESCE(rr.cancellationfine, 0) AS rr_cancelfine,
        COALESCE(rr.vatoncancellationfine, 0) AS rr_vatcancelfine,
        COALESCE(rr.waitingcharges, 0) AS rr_waitingcharges,
        COALESCE(rr.vatonwaitingcharges, 0) AS rr_vatwaitingcharges
    FROM jeeny_prod.ride.details rd
    JOIN jeeny_prod.ride.upfront uf ON rd.rideid = uf.rideid
    JOIN jeeny_prod.ride.receipts rr ON rd.rideid = rr.rideid
    JOIN jeeny_prod.general.areas ga ON rd.area_code = ga.area_code
    JOIN jeeny_prod.passengers.pricechecks pc
        ON pc.rideid = rd.rideid
       AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
    WHERE rd.boarded IS NOT NULL
      AND uf.originalestimatefare IS NOT NULL
      AND ga.country_code IN ('SA', 'JO')
      AND rd.area_code IN ('RUH', 'JED', 'MAD', 'DMM', 'MEC', 'AMM', 'IRB', 'ZRQ')
      AND rd.createddate >= DATEADD('day', -29, CURRENT_DATE())
      AND rd.createddate < CURRENT_DATE()
),

Classified AS (
    SELECT
        createddate,
        area_code,
        country,
        upfrontscenario,
        IFF(scaleddistance > 0, 1, 0) AS scaled_distance_flag,
        ROUND(
            (rr_total + rr_discount + rr_vatdiscount)
            - (pc_value + pc_vat_hailing + pc_surcharge_gross),
            2
        ) AS fare_diff,
        ROUND(
            (rr_total + rr_discount + rr_vatdiscount)
            - (pc_value + pc_vat_hailing + pc_surcharge_gross)
            - (rr_cancelfine + rr_vatcancelfine + rr_waitingcharges + rr_vatwaitingcharges),
            2
        ) AS residual,
        CASE
            WHEN ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat_hailing + pc_surcharge_gross), 2
            ) = 0 THEN 'matched'
            WHEN ABS(ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat_hailing + pc_surcharge_gross), 2
            )) <= 0.01 THEN 'rounding'
            WHEN ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat_hailing + pc_surcharge_gross), 2
            ) > 0.01
             AND ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat_hailing + pc_surcharge_gross)
                - (rr_cancelfine + rr_vatcancelfine + rr_waitingcharges + rr_vatwaitingcharges), 2
             ) <= 0.01 THEN 'increase_non_issue'
            WHEN ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat_hailing + pc_surcharge_gross), 2
            ) > 0.01 THEN 'increase_pricing'
            WHEN ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat_hailing + pc_surcharge_gross), 2
            ) < -0.01 THEN 'decrease_pricing'
            ELSE 'unclassified'
        END AS issue_type
    FROM BaseData
),

DailyArea AS (
    SELECT
        createddate,
        area_code,
        country,
        COUNT(*) AS ride_count,
        SUM(IFF(issue_type = 'increase_pricing', 1, 0)) AS increase_pricing_rides,
        SUM(IFF(issue_type = 'decrease_pricing', 1, 0)) AS decrease_pricing_rides,
        SUM(IFF(issue_type = 'increase_non_issue', 1, 0)) AS increase_non_issue_rides,
        SUM(IFF(issue_type = 'rounding', 1, 0)) AS rounding_rides,
        SUM(IFF(issue_type = 'matched', 1, 0)) AS matched_rides,
        SUM(IFF(upfrontscenario = 'withinB', 1, 0)) AS withinB_rides,
        SUM(IFF(upfrontscenario = 'beyondB', 1, 0)) AS beyondB_rides,
        SUM(IFF(upfrontscenario = 'withinA', 1, 0)) AS withinA_rides,
        SUM(scaled_distance_flag) AS scaled_distance_rides,
        ROUND(AVG(fare_diff), 4) AS avg_fare_diff,
        ROUND(SUM(IFF(issue_type = 'increase_pricing', residual, 0)), 2) AS sum_pricing_residual,
        ROUND(100.0 * SUM(IFF(issue_type = 'increase_pricing', 1, 0)) / NULLIF(COUNT(*), 0), 4)
            AS pct_increase_pricing,
        ROUND(100.0 * SUM(IFF(issue_type = 'decrease_pricing', 1, 0)) / NULLIF(COUNT(*), 0), 4)
            AS pct_decrease_pricing,
        ROUND(100.0 * SUM(IFF(issue_type = 'increase_non_issue', 1, 0)) / NULLIF(COUNT(*), 0), 4)
            AS pct_increase_non_issue,
        ROUND(100.0 * SUM(IFF(issue_type = 'rounding', 1, 0)) / NULLIF(COUNT(*), 0), 4)
            AS pct_rounding,
        ROUND(100.0 * SUM(IFF(upfrontscenario = 'withinB', 1, 0)) / NULLIF(COUNT(*), 0), 4)
            AS pct_withinB,
        ROUND(100.0 * SUM(IFF(upfrontscenario = 'beyondB', 1, 0)) / NULLIF(COUNT(*), 0), 4)
            AS pct_beyondB
    FROM Classified
    GROUP BY 1, 2, 3
),

Yesterday AS (
    SELECT d.*
    FROM DailyArea d
    CROSS JOIN params p
    WHERE d.createddate = p.report_date
),

DoD AS (
    SELECT d.area_code,
           d.pct_increase_pricing AS dod_pct_increase_pricing,
           d.pct_decrease_pricing AS dod_pct_decrease_pricing,
           d.pct_increase_non_issue AS dod_pct_increase_non_issue,
           d.pct_withinB AS dod_pct_withinB,
           d.pct_beyondB AS dod_pct_beyondB,
           d.pct_rounding AS dod_pct_rounding,
           d.avg_fare_diff AS dod_avg_fare_diff,
           d.ride_count AS dod_ride_count
    FROM DailyArea d
    CROSS JOIN params p
    WHERE d.createddate = p.dod_date
),

WoW AS (
    SELECT d.area_code,
           d.pct_increase_pricing AS wow_pct_increase_pricing,
           d.pct_decrease_pricing AS wow_pct_decrease_pricing,
           d.pct_increase_non_issue AS wow_pct_increase_non_issue,
           d.pct_withinB AS wow_pct_withinB,
           d.pct_beyondB AS wow_pct_beyondB,
           d.pct_rounding AS wow_pct_rounding,
           d.avg_fare_diff AS wow_avg_fare_diff,
           d.ride_count AS wow_ride_count
    FROM DailyArea d
    CROSS JOIN params p
    WHERE d.createddate = p.wow_date
),

MoM AS (
    SELECT d.area_code,
           d.pct_increase_pricing AS mom_pct_increase_pricing,
           d.pct_decrease_pricing AS mom_pct_decrease_pricing,
           d.pct_increase_non_issue AS mom_pct_increase_non_issue,
           d.pct_withinB AS mom_pct_withinB,
           d.pct_beyondB AS mom_pct_beyondB,
           d.pct_rounding AS mom_pct_rounding,
           d.avg_fare_diff AS mom_avg_fare_diff,
           d.ride_count AS mom_ride_count
    FROM DailyArea d
    CROSS JOIN params p
    WHERE d.createddate = p.mom_date
),

Avg14 AS (
    SELECT
        d.area_code,
        ROUND(AVG(d.pct_increase_pricing), 4) AS avg14_pct_increase_pricing,
        ROUND(AVG(d.pct_decrease_pricing), 4) AS avg14_pct_decrease_pricing,
        ROUND(AVG(d.pct_increase_non_issue), 4) AS avg14_pct_increase_non_issue,
        ROUND(AVG(d.pct_withinB), 4) AS avg14_pct_withinB,
        ROUND(AVG(d.pct_beyondB), 4) AS avg14_pct_beyondB,
        ROUND(AVG(d.pct_rounding), 4) AS avg14_pct_rounding,
        ROUND(AVG(d.avg_fare_diff), 4) AS avg14_avg_fare_diff,
        ROUND(AVG(d.ride_count), 2) AS avg14_ride_count
    FROM DailyArea d
    CROSS JOIN params p
    WHERE d.createddate BETWEEN p.avg14_start AND p.avg14_end
    GROUP BY 1
)

SELECT
    y.createddate AS report_date,
    y.area_code,
    y.country,
    y.ride_count,
    y.pct_increase_pricing,
    y.pct_decrease_pricing,
    y.pct_increase_non_issue,
    y.pct_withinB,
    y.pct_beyondB,
    y.pct_rounding,
    y.avg_fare_diff,
    y.scaled_distance_rides,
    y.sum_pricing_residual,
    /* DoD deltas (pp for rates) */
    ROUND(y.pct_increase_pricing - d.dod_pct_increase_pricing, 4) AS dod_delta_pct_increase_pricing,
    ROUND(y.pct_decrease_pricing - d.dod_pct_decrease_pricing, 4) AS dod_delta_pct_decrease_pricing,
    ROUND(y.pct_increase_non_issue - d.dod_pct_increase_non_issue, 4) AS dod_delta_pct_increase_non_issue,
    ROUND(y.pct_withinB - d.dod_pct_withinB, 4) AS dod_delta_pct_withinB,
    ROUND(y.pct_beyondB - d.dod_pct_beyondB, 4) AS dod_delta_pct_beyondB,
    ROUND(y.pct_rounding - d.dod_pct_rounding, 4) AS dod_delta_pct_rounding,
    ROUND(y.avg_fare_diff - d.dod_avg_fare_diff, 4) AS dod_delta_avg_fare_diff,
    /* WoW */
    ROUND(y.pct_increase_pricing - w.wow_pct_increase_pricing, 4) AS wow_delta_pct_increase_pricing,
    ROUND(y.pct_decrease_pricing - w.wow_pct_decrease_pricing, 4) AS wow_delta_pct_decrease_pricing,
    ROUND(y.pct_withinB - w.wow_pct_withinB, 4) AS wow_delta_pct_withinB,
    ROUND(y.pct_beyondB - w.wow_pct_beyondB, 4) AS wow_delta_pct_beyondB,
    ROUND(y.pct_rounding - w.wow_pct_rounding, 4) AS wow_delta_pct_rounding,
    ROUND(y.avg_fare_diff - w.wow_avg_fare_diff, 4) AS wow_delta_avg_fare_diff,
    /* MoM */
    ROUND(y.pct_increase_pricing - m.mom_pct_increase_pricing, 4) AS mom_delta_pct_increase_pricing,
    ROUND(y.pct_decrease_pricing - m.mom_pct_decrease_pricing, 4) AS mom_delta_pct_decrease_pricing,
    ROUND(y.pct_withinB - m.mom_pct_withinB, 4) AS mom_delta_pct_withinB,
    ROUND(y.pct_beyondB - m.mom_pct_beyondB, 4) AS mom_delta_pct_beyondB,
    ROUND(y.pct_rounding - m.mom_pct_rounding, 4) AS mom_delta_pct_rounding,
    ROUND(y.avg_fare_diff - m.mom_avg_fare_diff, 4) AS mom_delta_avg_fare_diff,
    /* Prior 14d averages */
    a.avg14_pct_increase_pricing,
    a.avg14_pct_decrease_pricing,
    a.avg14_pct_increase_non_issue,
    a.avg14_pct_withinB,
    a.avg14_pct_beyondB,
    a.avg14_pct_rounding,
    a.avg14_avg_fare_diff,
    /* Watch flags: yesterday > prior 14d avg */
    IFF(y.pct_increase_pricing > a.avg14_pct_increase_pricing, TRUE, FALSE) AS watch_pct_increase_pricing,
    IFF(y.pct_decrease_pricing > a.avg14_pct_decrease_pricing, TRUE, FALSE) AS watch_pct_decrease_pricing,
    IFF(y.pct_increase_non_issue > a.avg14_pct_increase_non_issue, TRUE, FALSE) AS watch_pct_increase_non_issue,
    IFF(y.pct_withinB > a.avg14_pct_withinB, TRUE, FALSE) AS watch_pct_withinB,
    IFF(y.pct_beyondB > a.avg14_pct_beyondB, TRUE, FALSE) AS watch_pct_beyondB,
    IFF(y.pct_rounding > a.avg14_pct_rounding, TRUE, FALSE) AS watch_pct_rounding,
    IFF(y.avg_fare_diff > a.avg14_avg_fare_diff, TRUE, FALSE) AS watch_avg_fare_diff
FROM Yesterday y
LEFT JOIN DoD d ON y.area_code = d.area_code
LEFT JOIN WoW w ON y.area_code = w.area_code
LEFT JOIN MoM m ON y.area_code = m.area_code
LEFT JOIN Avg14 a ON y.area_code = a.area_code
ORDER BY y.country, y.ride_count DESC;
