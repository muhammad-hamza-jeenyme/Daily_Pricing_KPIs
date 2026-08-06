-- Fare integrity CHANNEL SUMMARY (v1)
-- Grain: country total + named cities + Others (non-watchlist in that country)
-- Metric: % rides with increase_pricing only (+ DoD / WoW / MoM / vs prior 7d avg)
-- SA cities: RUH, JED, MAD, DMM, MEC (+ Others)
-- JO cities: AMM, IRB, ZRQ (+ Others)
-- Spec: automations/SLACK_MESSAGE_TEMPLATE.md

WITH params AS (
    SELECT
        DATEADD('day', -1, CURRENT_DATE()) AS report_date,
        DATEADD('day', -2, CURRENT_DATE()) AS dod_date,
        DATEADD('day', -8, CURRENT_DATE()) AS wow_date,
        DATEADD('day', -29, CURRENT_DATE()) AS mom_date,
        DATEADD('day', -8, CURRENT_DATE()) AS avg7_start,  -- yesterday-7
        DATEADD('day', -2, CURRENT_DATE()) AS avg7_end     -- yesterday-1
),

BaseData AS (
    SELECT
        rd.createddate,
        rd.area_code,
        ga.country_code AS country,
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
    /* database set via Snowflake session / API (SNOWFLAKE_DATABASE) */
    FROM ride.details rd
    JOIN ride.upfront uf ON rd.rideid = uf.rideid
    JOIN ride.receipts rr ON rd.rideid = rr.rideid
    JOIN general.areas ga ON rd.area_code = ga.area_code
    JOIN passengers.pricechecks pc
        ON pc.rideid = rd.rideid
       AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
    WHERE rd.boarded IS NOT NULL
      AND uf.originalestimatefare IS NOT NULL
      AND ga.country_code IN ('SA', 'JO')
      AND rd.createddate >= DATEADD('day', -29, CURRENT_DATE())
      AND rd.createddate < CURRENT_DATE()
),

Classified AS (
    SELECT
        createddate,
        area_code,
        country,
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

Labeled AS (
    SELECT
        createddate,
        country,
        CASE
            WHEN country = 'SA' AND area_code IN ('RUH', 'JED', 'MAD', 'DMM', 'MEC') THEN area_code
            WHEN country = 'JO' AND area_code IN ('AMM', 'IRB', 'ZRQ') THEN area_code
            ELSE 'Others'
        END AS area_label,
        issue_type
    FROM Classified
),

DailyBucket AS (
    SELECT
        createddate,
        country,
        area_label,
        COUNT(*) AS ride_count,
        ROUND(100.0 * SUM(IFF(issue_type = 'increase_pricing', 1, 0)) / NULLIF(COUNT(*), 0), 4)
            AS pct_increase_pricing
    FROM Labeled
    GROUP BY 1, 2, 3
),

DailyCountry AS (
    SELECT
        createddate,
        country,
        'ALL' AS area_label,
        COUNT(*) AS ride_count,
        ROUND(100.0 * SUM(IFF(issue_type = 'increase_pricing', 1, 0)) / NULLIF(COUNT(*), 0), 4)
            AS pct_increase_pricing
    FROM Labeled
    GROUP BY 1, 2
),

DailyAll AS (
    SELECT * FROM DailyBucket
    UNION ALL
    SELECT * FROM DailyCountry
),

Yesterday AS (
    SELECT d.*
    FROM DailyAll d
    CROSS JOIN params p
    WHERE d.createddate = p.report_date
),

DoD AS (
    SELECT d.country, d.area_label, d.pct_increase_pricing AS dod_pct, d.ride_count AS dod_rides
    FROM DailyAll d
    CROSS JOIN params p
    WHERE d.createddate = p.dod_date
),

WoW AS (
    SELECT d.country, d.area_label, d.pct_increase_pricing AS wow_pct, d.ride_count AS wow_rides
    FROM DailyAll d
    CROSS JOIN params p
    WHERE d.createddate = p.wow_date
),

MoM AS (
    SELECT d.country, d.area_label, d.pct_increase_pricing AS mom_pct, d.ride_count AS mom_rides
    FROM DailyAll d
    CROSS JOIN params p
    WHERE d.createddate = p.mom_date
),

Avg7 AS (
    SELECT
        d.country,
        d.area_label,
        ROUND(AVG(d.pct_increase_pricing), 4) AS avg7_pct_increase_pricing,
        ROUND(AVG(d.ride_count), 2) AS avg7_ride_count
    FROM DailyAll d
    CROSS JOIN params p
    WHERE d.createddate BETWEEN p.avg7_start AND p.avg7_end
    GROUP BY 1, 2
)

SELECT
    y.createddate AS report_date,
    y.country,
    y.area_label,
    y.ride_count,
    y.pct_increase_pricing,
    ROUND(y.pct_increase_pricing - d.dod_pct, 4) AS dod_delta_pp,
    ROUND(y.pct_increase_pricing - w.wow_pct, 4) AS wow_delta_pp,
    ROUND(y.pct_increase_pricing - m.mom_pct, 4) AS mom_delta_pp,
    a.avg7_pct_increase_pricing,
    ROUND(y.pct_increase_pricing - a.avg7_pct_increase_pricing, 4) AS vs7d_delta_pp,
    IFF(y.pct_increase_pricing > a.avg7_pct_increase_pricing, TRUE, FALSE) AS major_shift_vs7d,
    CASE
        WHEN y.country = 'SA' AND y.area_label = 'ALL' THEN 0
        WHEN y.country = 'SA' AND y.area_label = 'RUH' THEN 1
        WHEN y.country = 'SA' AND y.area_label = 'JED' THEN 2
        WHEN y.country = 'SA' AND y.area_label = 'MAD' THEN 3
        WHEN y.country = 'SA' AND y.area_label = 'DMM' THEN 4
        WHEN y.country = 'SA' AND y.area_label = 'MEC' THEN 5
        WHEN y.country = 'SA' AND y.area_label = 'Others' THEN 6
        WHEN y.country = 'JO' AND y.area_label = 'ALL' THEN 10
        WHEN y.country = 'JO' AND y.area_label = 'AMM' THEN 11
        WHEN y.country = 'JO' AND y.area_label = 'IRB' THEN 12
        WHEN y.country = 'JO' AND y.area_label = 'ZRQ' THEN 13
        WHEN y.country = 'JO' AND y.area_label = 'Others' THEN 14
        ELSE 99
    END AS sort_key
FROM Yesterday y
LEFT JOIN DoD d ON y.country = d.country AND y.area_label = d.area_label
LEFT JOIN WoW w ON y.country = w.country AND y.area_label = w.area_label
LEFT JOIN MoM m ON y.country = m.country AND y.area_label = m.area_label
LEFT JOIN Avg7 a ON y.country = a.country AND y.area_label = a.area_label
ORDER BY sort_key;
