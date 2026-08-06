-- Channel summary: % rides with fare increase (increase_pricing)
-- Country totals + major cities + Others (SA/JO)
-- Major SA: RUH, JED, MAD, DMM, MEC | Major JO: AMM, IRB, ZRQ
-- Spec: docs/alert-rules.md | automations/DAILY_SLACK_INSTRUCTIONS.md

WITH params AS (
    SELECT
        DATEADD('day', -1, CURRENT_DATE()) AS report_date,
        DATEADD('day', -2, CURRENT_DATE()) AS dod_date,
        DATEADD('day', -8, CURRENT_DATE()) AS wow_date,
        DATEADD('day', -29, CURRENT_DATE()) AS mom_date,
        DATEADD('day', -8, CURRENT_DATE()) AS avg7_start,
        DATEADD('day', -2, CURRENT_DATE()) AS avg7_end
),

BaseData AS (
    SELECT
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
      AND rd.createddate >= DATEADD('day', -29, CURRENT_DATE())
      AND rd.createddate < CURRENT_DATE()
),

Classified AS (
    SELECT
        createddate,
        country,
        city_bucket,
        CASE
            WHEN ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat_hailing + pc_surcharge_gross), 2
            ) > 0.01
             AND ROUND(
                (rr_total + rr_discount + rr_vatdiscount)
                - (pc_value + pc_vat_hailing + pc_surcharge_gross)
                - (rr_cancelfine + rr_vatcancelfine + rr_waitingcharges + rr_vatwaitingcharges), 2
             ) > 0.01
            THEN 1 ELSE 0
        END AS is_increase_pricing
    FROM BaseData
),

DailyCountry AS (
    SELECT
        createddate,
        country,
        COUNT(*) AS ride_count,
        SUM(is_increase_pricing) AS increase_pricing_rides,
        ROUND(100.0 * SUM(is_increase_pricing) / NULLIF(COUNT(*), 0), 2) AS pct_increase_pricing
    FROM Classified
    GROUP BY 1, 2
),

DailyCity AS (
    SELECT
        createddate,
        country,
        city_bucket,
        COUNT(*) AS ride_count,
        SUM(is_increase_pricing) AS increase_pricing_rides,
        ROUND(100.0 * SUM(is_increase_pricing) / NULLIF(COUNT(*), 0), 2) AS pct_increase_pricing
    FROM Classified
    GROUP BY 1, 2, 3
),

CountryYesterday AS (
    SELECT c.*
    FROM DailyCountry c
    CROSS JOIN params p
    WHERE c.createddate = p.report_date
),

CountryDoD AS (
    SELECT country, pct_increase_pricing AS dod_pct, ride_count AS dod_rides
    FROM DailyCountry CROSS JOIN params p WHERE createddate = p.dod_date
),

CountryWoW AS (
    SELECT country, pct_increase_pricing AS wow_pct, ride_count AS wow_rides
    FROM DailyCountry CROSS JOIN params p WHERE createddate = p.wow_date
),

CountryMoM AS (
    SELECT country, pct_increase_pricing AS mom_pct, ride_count AS mom_rides
    FROM DailyCountry CROSS JOIN params p WHERE createddate = p.mom_date
),

CountryAvg7 AS (
    SELECT country,
           ROUND(AVG(pct_increase_pricing), 2) AS avg7_pct,
           ROUND(AVG(ride_count), 0) AS avg7_rides
    FROM DailyCountry CROSS JOIN params p
    WHERE createddate BETWEEN p.avg7_start AND p.avg7_end
    GROUP BY 1
),

CityYesterday AS (
    SELECT c.*
    FROM DailyCity c
    CROSS JOIN params p
    WHERE c.createddate = p.report_date
),

CityDoD AS (
    SELECT country, city_bucket, pct_increase_pricing AS dod_pct
    FROM DailyCity CROSS JOIN params p WHERE createddate = p.dod_date
),

CityWoW AS (
    SELECT country, city_bucket, pct_increase_pricing AS wow_pct
    FROM DailyCity CROSS JOIN params p WHERE createddate = p.wow_date
),

CityMoM AS (
    SELECT country, city_bucket, pct_increase_pricing AS mom_pct
    FROM DailyCity CROSS JOIN params p WHERE createddate = p.mom_date
),

CityAvg7 AS (
    SELECT country, city_bucket,
           ROUND(AVG(pct_increase_pricing), 2) AS avg7_pct
    FROM DailyCity CROSS JOIN params p
    WHERE createddate BETWEEN p.avg7_start AND p.avg7_end
    GROUP BY 1, 2
)

-- Country grain
SELECT
    'country' AS grain,
    y.createddate AS report_date,
    y.country,
    NULL AS city_bucket,
    y.ride_count,
    y.pct_increase_pricing,
    ROUND(y.pct_increase_pricing - d.dod_pct, 2) AS dod_delta_pp,
    ROUND(y.pct_increase_pricing - w.wow_pct, 2) AS wow_delta_pp,
    ROUND(y.pct_increase_pricing - m.mom_pct, 2) AS mom_delta_pp,
    a.avg7_pct,
    IFF(y.pct_increase_pricing > a.avg7_pct, TRUE, FALSE) AS major_shift_vs_7d_avg,
    ROUND(100.0 * (y.ride_count - d.dod_rides) / NULLIF(d.dod_rides, 0), 1) AS dod_rides_pct,
    ROUND(100.0 * (y.ride_count - w.wow_rides) / NULLIF(w.wow_rides, 0), 1) AS wow_rides_pct
FROM CountryYesterday y
LEFT JOIN CountryDoD d ON y.country = d.country
LEFT JOIN CountryWoW w ON y.country = w.country
LEFT JOIN CountryMoM m ON y.country = m.country
LEFT JOIN CountryAvg7 a ON y.country = a.country

UNION ALL

-- City / Others grain
SELECT
    'city' AS grain,
    y.createddate AS report_date,
    y.country,
    y.city_bucket,
    y.ride_count,
    y.pct_increase_pricing,
    ROUND(y.pct_increase_pricing - d.dod_pct, 2) AS dod_delta_pp,
    ROUND(y.pct_increase_pricing - w.wow_pct, 2) AS wow_delta_pp,
    ROUND(y.pct_increase_pricing - m.mom_pct, 2) AS mom_delta_pp,
    a.avg7_pct,
    IFF(y.pct_increase_pricing > a.avg7_pct, TRUE, FALSE) AS major_shift_vs_7d_avg,
    NULL AS dod_rides_pct,
    NULL AS wow_rides_pct
FROM CityYesterday y
LEFT JOIN CityDoD d ON y.country = d.country AND y.city_bucket = d.city_bucket
LEFT JOIN CityWoW w ON y.country = w.country AND y.city_bucket = w.city_bucket
LEFT JOIN CityMoM m ON y.country = m.country AND y.city_bucket = m.city_bucket
LEFT JOIN CityAvg7 a ON y.country = a.country AND y.city_bucket = a.city_bucket

ORDER BY 1, 3, 4;
