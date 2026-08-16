-- Channel summary: cumulative price shocks, residual fare increase, rounding,
-- surcharge / pickup / surge / PD mismatch
-- Country + major cities + Others (SA/JO)
-- Major SA: RUH, JED, MAD, DMM, MEC | Major JO: AMM, IRB, ZRQ
-- Spec: docs/alert-rules.md | automations/DAILY_SLACK_INSTRUCTIONS.md
--
-- Cumulative price shocks % = Fare_Diff > 0.01 (any reason: waiting, cancel,
--   additional time, residual pricing, tech bugs). EXCLUDES rounding.
-- Residual fare increase % = increase_pricing only (Fare_Diff > 0.01 AND Residual > 0.01).
-- Rounding % = 0 < ABS(Fare_Diff) <= 0.01 (tech bug / penny noise).
-- Surcharge mismatch: withinA + dropoff at destination AND
--   (Details.SURCHARGE + Details.INTERCITYSURCHARGE) != PriceChecks.SURCHARGE
-- Pickup mismatch: PriceCheck pickup vs first ride_offered location > 100m
-- Surge / PD mismatch: ROUND(PC.*,4) <> ROUND(Details.*,4); both non-null

WITH params AS (
    SELECT
        DATEADD('day', -1, CURRENT_DATE()) AS report_date,
        DATEADD('day', -2, CURRENT_DATE()) AS dod_date,
        DATEADD('day', -3, CURRENT_DATE()) AS trend_t2_date,
        DATEADD('day', -8, CURRENT_DATE()) AS wow_date,
        DATEADD('day', -29, CURRENT_DATE()) AS mom_date,
        DATEADD('day', -8, CURRENT_DATE()) AS avg7_start,
        DATEADD('day', -2, CURRENT_DATE()) AS avg7_end,
        /* 28 complete days ending day before report_date (excludes report day) */
        DATEADD('day', -29, CURRENT_DATE()) AS avg28_start,
        DATEADD('day', -2, CURRENT_DATE()) AS avg28_end,
        DATEADD('day', -29, CURRENT_DATE()) AS win_start,
        CURRENT_DATE() AS win_end
),

BaseRides AS (
    SELECT
        rd.rideid,
        rd.createddate,
        rd.area_code,
        ga.country_code AS country,
        rd.request_service,
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
        COALESCE(rr.vatoncancellationfine, 0) AS rr_vatcancelfine,
        COALESCE(rr.waitingcharges, 0) AS rr_waitingcharges,
        COALESCE(rr.vatonwaitingcharges, 0) AS rr_vatwaitingcharges,
        pc.pickuplat,
        pc.pickuplong,
        pc.actualdatetime AS pc_actualdatetime
    FROM jeeny_prod.ride.details rd
    JOIN jeeny_prod.ride.upfront uf ON rd.rideid = uf.rideid
    JOIN jeeny_prod.ride.receipts rr ON rd.rideid = rr.rideid
    JOIN jeeny_prod.general.areas ga ON rd.area_code = ga.area_code
    JOIN jeeny_prod.passengers.pricechecks pc
        ON pc.rideid = rd.rideid
       AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
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
        ROUND(
            (b.rr_total + b.rr_discount + b.rr_vatdiscount)
            - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2
        ) AS fare_diff,
        ROUND(
            (b.rr_total + b.rr_discount + b.rr_vatdiscount)
            - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross)
            - (b.rr_cancelfine + b.rr_vatcancelfine + b.rr_waitingcharges + b.rr_vatwaitingcharges), 2
        ) AS residual,
        /* Cumulative price shock: any Fare_Diff > 0.01 (excludes rounding) */
        CASE
            WHEN ROUND(
                (b.rr_total + b.rr_discount + b.rr_vatdiscount)
                - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2
            ) > 0.01
            THEN 1 ELSE 0
        END AS is_cumulative_price_shock,
        /* Residual pricing increase (excludes waiting/cancel-explained) */
        CASE
            WHEN ROUND(
                (b.rr_total + b.rr_discount + b.rr_vatdiscount)
                - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2
            ) > 0.01
             AND ROUND(
                (b.rr_total + b.rr_discount + b.rr_vatdiscount)
                - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross)
                - (b.rr_cancelfine + b.rr_vatcancelfine + b.rr_waitingcharges + b.rr_vatwaitingcharges), 2
             ) > 0.01
            THEN 1 ELSE 0
        END AS is_increase_pricing,
        /* Rounding tech bug: 0 < |Fare_Diff| <= 0.01 */
        CASE
            WHEN ABS(ROUND(
                (b.rr_total + b.rr_discount + b.rr_vatdiscount)
                - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2
            )) > 0
             AND ABS(ROUND(
                (b.rr_total + b.rr_discount + b.rr_vatdiscount)
                - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2
            )) <= 0.01
            THEN 1 ELSE 0
        END AS is_rounding,
        CASE
            WHEN LOWER(b.upfrontscenario) = 'withina'
             AND LOWER(TO_VARCHAR(b.dropoffatdestination)) = 'true'
             AND ROUND(b.rd_surcharge + b.rd_intercitysurcharge, 2)
                 != ROUND(b.pc_surcharge_ex_vat, 2)
            THEN 1 ELSE 0
        END AS is_surcharge_mismatch,
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
            WHEN b.pc_surge IS NOT NULL
             AND b.rd_surge IS NOT NULL
             AND ROUND(b.pc_surge, 4) <> ROUND(b.rd_surge, 4)
            THEN 1 ELSE 0
        END AS is_surge_mismatch,
        CASE
            WHEN b.pc_pd IS NOT NULL
             AND b.rd_pd IS NOT NULL
             AND ROUND(b.pc_pd, 4) <> ROUND(b.rd_pd, 4)
            THEN 1 ELSE 0
        END AS is_pd_mismatch
    FROM BaseRides b
    LEFT JOIN OfferEvent oe ON oe.rideid = b.rideid
),

DailyCountry AS (
    SELECT
        createddate,
        country,
        COUNT(*) AS ride_count,
        SUM(is_cumulative_price_shock) AS cumulative_shock_rides,
        ROUND(100.0 * SUM(is_cumulative_price_shock) / NULLIF(COUNT(*), 0), 2) AS pct_cumulative_shock,
        SUM(is_increase_pricing) AS increase_pricing_rides,
        ROUND(100.0 * SUM(is_increase_pricing) / NULLIF(COUNT(*), 0), 2) AS pct_increase_pricing,
        SUM(is_rounding) AS rounding_rides,
        ROUND(100.0 * SUM(is_rounding) / NULLIF(COUNT(*), 0), 2) AS pct_rounding,
        SUM(is_surcharge_mismatch) AS surcharge_mismatch_rides,
        ROUND(100.0 * SUM(is_surcharge_mismatch) / NULLIF(COUNT(*), 0), 2) AS pct_surcharge_mismatch,
        SUM(is_pickup_mismatch) AS pickup_mismatch_rides,
        ROUND(100.0 * SUM(is_pickup_mismatch) / NULLIF(COUNT(*), 0), 2) AS pct_pickup_mismatch,
        SUM(is_surge_mismatch) AS surge_mismatch_rides,
        ROUND(100.0 * SUM(is_surge_mismatch) / NULLIF(COUNT(*), 0), 2) AS pct_surge_mismatch,
        SUM(is_pd_mismatch) AS pd_mismatch_rides,
        ROUND(100.0 * SUM(is_pd_mismatch) / NULLIF(COUNT(*), 0), 2) AS pct_pd_mismatch
    FROM Classified
    GROUP BY 1, 2
),

DailyCity AS (
    SELECT
        createddate,
        country,
        city_bucket,
        COUNT(*) AS ride_count,
        SUM(is_cumulative_price_shock) AS cumulative_shock_rides,
        ROUND(100.0 * SUM(is_cumulative_price_shock) / NULLIF(COUNT(*), 0), 2) AS pct_cumulative_shock,
        SUM(is_increase_pricing) AS increase_pricing_rides,
        ROUND(100.0 * SUM(is_increase_pricing) / NULLIF(COUNT(*), 0), 2) AS pct_increase_pricing,
        SUM(is_rounding) AS rounding_rides,
        ROUND(100.0 * SUM(is_rounding) / NULLIF(COUNT(*), 0), 2) AS pct_rounding,
        SUM(is_surcharge_mismatch) AS surcharge_mismatch_rides,
        ROUND(100.0 * SUM(is_surcharge_mismatch) / NULLIF(COUNT(*), 0), 2) AS pct_surcharge_mismatch,
        SUM(is_pickup_mismatch) AS pickup_mismatch_rides,
        ROUND(100.0 * SUM(is_pickup_mismatch) / NULLIF(COUNT(*), 0), 2) AS pct_pickup_mismatch,
        SUM(is_surge_mismatch) AS surge_mismatch_rides,
        ROUND(100.0 * SUM(is_surge_mismatch) / NULLIF(COUNT(*), 0), 2) AS pct_surge_mismatch,
        SUM(is_pd_mismatch) AS pd_mismatch_rides,
        ROUND(100.0 * SUM(is_pd_mismatch) / NULLIF(COUNT(*), 0), 2) AS pct_pd_mismatch
    FROM Classified
    GROUP BY 1, 2, 3
),

CountryYesterday AS (
    SELECT c.* FROM DailyCountry c CROSS JOIN params p WHERE c.createddate = p.report_date
),
CountryDoD AS (
    SELECT * FROM DailyCountry CROSS JOIN params p WHERE createddate = p.dod_date
),
CountryWoW AS (
    SELECT * FROM DailyCountry CROSS JOIN params p WHERE createddate = p.wow_date
),
CountryMoM AS (
    SELECT * FROM DailyCountry CROSS JOIN params p WHERE createddate = p.mom_date
),
CountryAvg7 AS (
    SELECT
        country,
        ROUND(AVG(pct_cumulative_shock), 2) AS avg7_pct_cumulative_shock,
        ROUND(AVG(pct_increase_pricing), 2) AS avg7_pct_increase_pricing,
        ROUND(AVG(pct_rounding), 2) AS avg7_pct_rounding,
        ROUND(AVG(pct_surcharge_mismatch), 2) AS avg7_pct_surcharge_mismatch,
        ROUND(AVG(pct_pickup_mismatch), 2) AS avg7_pct_pickup_mismatch,
        ROUND(AVG(pct_surge_mismatch), 2) AS avg7_pct_surge_mismatch,
        ROUND(AVG(pct_pd_mismatch), 2) AS avg7_pct_pd_mismatch
    FROM DailyCountry CROSS JOIN params p
    WHERE createddate BETWEEN p.avg7_start AND p.avg7_end
    GROUP BY 1
),
/* Canvas exceptions: upper breach vs prior 28d mean + 2*sample stddev */
CountryAvg28 AS (
    SELECT
        country,
        ROUND(AVG(pct_cumulative_shock), 2) AS avg28_pct_cumulative_shock,
        ROUND(STDDEV_SAMP(pct_cumulative_shock), 4) AS sd28_pct_cumulative_shock,
        ROUND(AVG(pct_increase_pricing), 2) AS avg28_pct_increase_pricing,
        ROUND(STDDEV_SAMP(pct_increase_pricing), 4) AS sd28_pct_increase_pricing,
        ROUND(AVG(pct_rounding), 2) AS avg28_pct_rounding,
        ROUND(STDDEV_SAMP(pct_rounding), 4) AS sd28_pct_rounding,
        ROUND(AVG(pct_surcharge_mismatch), 2) AS avg28_pct_surcharge_mismatch,
        ROUND(STDDEV_SAMP(pct_surcharge_mismatch), 4) AS sd28_pct_surcharge_mismatch,
        ROUND(AVG(pct_pickup_mismatch), 2) AS avg28_pct_pickup_mismatch,
        ROUND(STDDEV_SAMP(pct_pickup_mismatch), 4) AS sd28_pct_pickup_mismatch,
        ROUND(AVG(pct_surge_mismatch), 2) AS avg28_pct_surge_mismatch,
        ROUND(STDDEV_SAMP(pct_surge_mismatch), 4) AS sd28_pct_surge_mismatch,
        ROUND(AVG(pct_pd_mismatch), 2) AS avg28_pct_pd_mismatch,
        ROUND(STDDEV_SAMP(pct_pd_mismatch), 4) AS sd28_pct_pd_mismatch
    FROM DailyCountry CROSS JOIN params p
    WHERE createddate BETWEEN p.avg28_start AND p.avg28_end
    GROUP BY 1
),
CountryTrendT2 AS (
    SELECT * FROM DailyCountry CROSS JOIN params p WHERE createddate = p.trend_t2_date
),

CityYesterday AS (
    SELECT c.* FROM DailyCity c CROSS JOIN params p WHERE c.createddate = p.report_date
),
CityDoD AS (
    SELECT * FROM DailyCity CROSS JOIN params p WHERE createddate = p.dod_date
),
CityWoW AS (
    SELECT * FROM DailyCity CROSS JOIN params p WHERE createddate = p.wow_date
),
CityMoM AS (
    SELECT * FROM DailyCity CROSS JOIN params p WHERE createddate = p.mom_date
),
CityAvg7 AS (
    SELECT
        country,
        city_bucket,
        ROUND(AVG(pct_cumulative_shock), 2) AS avg7_pct_cumulative_shock,
        ROUND(AVG(pct_increase_pricing), 2) AS avg7_pct_increase_pricing,
        ROUND(AVG(pct_rounding), 2) AS avg7_pct_rounding,
        ROUND(AVG(pct_surcharge_mismatch), 2) AS avg7_pct_surcharge_mismatch,
        ROUND(AVG(pct_pickup_mismatch), 2) AS avg7_pct_pickup_mismatch,
        ROUND(AVG(pct_surge_mismatch), 2) AS avg7_pct_surge_mismatch,
        ROUND(AVG(pct_pd_mismatch), 2) AS avg7_pct_pd_mismatch
    FROM DailyCity CROSS JOIN params p
    WHERE createddate BETWEEN p.avg7_start AND p.avg7_end
    GROUP BY 1, 2
),
CityAvg28 AS (
    SELECT
        country,
        city_bucket,
        ROUND(AVG(pct_cumulative_shock), 2) AS avg28_pct_cumulative_shock,
        ROUND(STDDEV_SAMP(pct_cumulative_shock), 4) AS sd28_pct_cumulative_shock,
        ROUND(AVG(pct_increase_pricing), 2) AS avg28_pct_increase_pricing,
        ROUND(STDDEV_SAMP(pct_increase_pricing), 4) AS sd28_pct_increase_pricing,
        ROUND(AVG(pct_rounding), 2) AS avg28_pct_rounding,
        ROUND(STDDEV_SAMP(pct_rounding), 4) AS sd28_pct_rounding,
        ROUND(AVG(pct_surcharge_mismatch), 2) AS avg28_pct_surcharge_mismatch,
        ROUND(STDDEV_SAMP(pct_surcharge_mismatch), 4) AS sd28_pct_surcharge_mismatch,
        ROUND(AVG(pct_pickup_mismatch), 2) AS avg28_pct_pickup_mismatch,
        ROUND(STDDEV_SAMP(pct_pickup_mismatch), 4) AS sd28_pct_pickup_mismatch,
        ROUND(AVG(pct_surge_mismatch), 2) AS avg28_pct_surge_mismatch,
        ROUND(STDDEV_SAMP(pct_surge_mismatch), 4) AS sd28_pct_surge_mismatch,
        ROUND(AVG(pct_pd_mismatch), 2) AS avg28_pct_pd_mismatch,
        ROUND(STDDEV_SAMP(pct_pd_mismatch), 4) AS sd28_pct_pd_mismatch
    FROM DailyCity CROSS JOIN params p
    WHERE createddate BETWEEN p.avg28_start AND p.avg28_end
    GROUP BY 1, 2
)

SELECT
    'country' AS grain,
    y.createddate AS report_date,
    y.country,
    CAST(NULL AS VARCHAR) AS city_bucket,
    y.ride_count,
    y.pct_cumulative_shock,
    ROUND(y.pct_cumulative_shock - d.pct_cumulative_shock, 2) AS dod_delta_cumulative_pp,
    ROUND(y.pct_cumulative_shock - w.pct_cumulative_shock, 2) AS wow_delta_cumulative_pp,
    ROUND(y.pct_cumulative_shock - m.pct_cumulative_shock, 2) AS mom_delta_cumulative_pp,
    a.avg7_pct_cumulative_shock,
    IFF(y.pct_cumulative_shock > a.avg7_pct_cumulative_shock, TRUE, FALSE) AS major_shift_cumulative,
    b28.avg28_pct_cumulative_shock,
    b28.sd28_pct_cumulative_shock,
    IFF(
        b28.sd28_pct_cumulative_shock IS NOT NULL
        AND y.pct_cumulative_shock > b28.avg28_pct_cumulative_shock + 2 * b28.sd28_pct_cumulative_shock,
        TRUE, FALSE
    ) AS exception_28d_2sd_cumulative,
    d.pct_cumulative_shock AS cum_trend_t1,
    t2.pct_cumulative_shock AS cum_trend_t2,
    y.pct_increase_pricing,
    ROUND(y.pct_increase_pricing - d.pct_increase_pricing, 2) AS dod_delta_pp,
    ROUND(y.pct_increase_pricing - w.pct_increase_pricing, 2) AS wow_delta_pp,
    ROUND(y.pct_increase_pricing - m.pct_increase_pricing, 2) AS mom_delta_pp,
    a.avg7_pct_increase_pricing AS avg7_pct,
    IFF(y.pct_increase_pricing > a.avg7_pct_increase_pricing, TRUE, FALSE) AS major_shift_vs_7d_avg,
    b28.avg28_pct_increase_pricing,
    b28.sd28_pct_increase_pricing,
    IFF(
        b28.sd28_pct_increase_pricing IS NOT NULL
        AND y.pct_increase_pricing > b28.avg28_pct_increase_pricing + 2 * b28.sd28_pct_increase_pricing,
        TRUE, FALSE
    ) AS exception_28d_2sd_residual,
    d.pct_increase_pricing AS res_trend_t1,
    t2.pct_increase_pricing AS res_trend_t2,
    y.rounding_rides,
    y.pct_rounding,
    ROUND(y.pct_rounding - d.pct_rounding, 2) AS dod_delta_rounding_pp,
    ROUND(y.pct_rounding - w.pct_rounding, 2) AS wow_delta_rounding_pp,
    ROUND(y.pct_rounding - m.pct_rounding, 2) AS mom_delta_rounding_pp,
    a.avg7_pct_rounding,
    IFF(y.pct_rounding > a.avg7_pct_rounding, TRUE, FALSE) AS major_shift_rounding,
    b28.avg28_pct_rounding,
    b28.sd28_pct_rounding,
    IFF(
        b28.sd28_pct_rounding IS NOT NULL
        AND y.pct_rounding > b28.avg28_pct_rounding + 2 * b28.sd28_pct_rounding,
        TRUE, FALSE
    ) AS exception_28d_2sd_rounding,
    y.surcharge_mismatch_rides,
    y.pct_surcharge_mismatch,
    ROUND(y.pct_surcharge_mismatch - d.pct_surcharge_mismatch, 2) AS dod_delta_surcharge_pp,
    ROUND(y.pct_surcharge_mismatch - w.pct_surcharge_mismatch, 2) AS wow_delta_surcharge_pp,
    ROUND(y.pct_surcharge_mismatch - m.pct_surcharge_mismatch, 2) AS mom_delta_surcharge_pp,
    a.avg7_pct_surcharge_mismatch,
    IFF(y.pct_surcharge_mismatch > a.avg7_pct_surcharge_mismatch, TRUE, FALSE) AS major_shift_surcharge_mismatch,
    b28.avg28_pct_surcharge_mismatch,
    b28.sd28_pct_surcharge_mismatch,
    IFF(
        b28.sd28_pct_surcharge_mismatch IS NOT NULL
        AND y.pct_surcharge_mismatch > b28.avg28_pct_surcharge_mismatch + 2 * b28.sd28_pct_surcharge_mismatch,
        TRUE, FALSE
    ) AS exception_28d_2sd_surcharge,
    y.pickup_mismatch_rides,
    y.pct_pickup_mismatch,
    ROUND(y.pct_pickup_mismatch - d.pct_pickup_mismatch, 2) AS dod_delta_pickup_pp,
    ROUND(y.pct_pickup_mismatch - w.pct_pickup_mismatch, 2) AS wow_delta_pickup_pp,
    ROUND(y.pct_pickup_mismatch - m.pct_pickup_mismatch, 2) AS mom_delta_pickup_pp,
    a.avg7_pct_pickup_mismatch,
    IFF(y.pct_pickup_mismatch > a.avg7_pct_pickup_mismatch, TRUE, FALSE) AS major_shift_pickup_mismatch,
    b28.avg28_pct_pickup_mismatch,
    b28.sd28_pct_pickup_mismatch,
    IFF(
        b28.sd28_pct_pickup_mismatch IS NOT NULL
        AND y.pct_pickup_mismatch > b28.avg28_pct_pickup_mismatch + 2 * b28.sd28_pct_pickup_mismatch,
        TRUE, FALSE
    ) AS exception_28d_2sd_pickup,
    y.surge_mismatch_rides,
    y.pct_surge_mismatch,
    ROUND(y.pct_surge_mismatch - d.pct_surge_mismatch, 2) AS dod_delta_surge_pp,
    ROUND(y.pct_surge_mismatch - w.pct_surge_mismatch, 2) AS wow_delta_surge_pp,
    ROUND(y.pct_surge_mismatch - m.pct_surge_mismatch, 2) AS mom_delta_surge_pp,
    a.avg7_pct_surge_mismatch,
    IFF(y.pct_surge_mismatch > a.avg7_pct_surge_mismatch, TRUE, FALSE) AS major_shift_surge_mismatch,
    b28.avg28_pct_surge_mismatch,
    b28.sd28_pct_surge_mismatch,
    IFF(
        b28.sd28_pct_surge_mismatch IS NOT NULL
        AND y.pct_surge_mismatch > b28.avg28_pct_surge_mismatch + 2 * b28.sd28_pct_surge_mismatch,
        TRUE, FALSE
    ) AS exception_28d_2sd_surge,
    y.pd_mismatch_rides,
    y.pct_pd_mismatch,
    ROUND(y.pct_pd_mismatch - d.pct_pd_mismatch, 2) AS dod_delta_pd_pp,
    ROUND(y.pct_pd_mismatch - w.pct_pd_mismatch, 2) AS wow_delta_pd_pp,
    ROUND(y.pct_pd_mismatch - m.pct_pd_mismatch, 2) AS mom_delta_pd_pp,
    a.avg7_pct_pd_mismatch,
    IFF(y.pct_pd_mismatch > a.avg7_pct_pd_mismatch, TRUE, FALSE) AS major_shift_pd_mismatch,
    b28.avg28_pct_pd_mismatch,
    b28.sd28_pct_pd_mismatch,
    IFF(
        b28.sd28_pct_pd_mismatch IS NOT NULL
        AND y.pct_pd_mismatch > b28.avg28_pct_pd_mismatch + 2 * b28.sd28_pct_pd_mismatch,
        TRUE, FALSE
    ) AS exception_28d_2sd_pd
FROM CountryYesterday y
LEFT JOIN CountryDoD d ON y.country = d.country
LEFT JOIN CountryWoW w ON y.country = w.country
LEFT JOIN CountryMoM m ON y.country = m.country
LEFT JOIN CountryAvg7 a ON y.country = a.country
LEFT JOIN CountryAvg28 b28 ON y.country = b28.country
LEFT JOIN CountryTrendT2 t2 ON y.country = t2.country

UNION ALL

SELECT
    'city' AS grain,
    y.createddate AS report_date,
    y.country,
    y.city_bucket,
    y.ride_count,
    y.pct_cumulative_shock,
    ROUND(y.pct_cumulative_shock - d.pct_cumulative_shock, 2) AS dod_delta_cumulative_pp,
    ROUND(y.pct_cumulative_shock - w.pct_cumulative_shock, 2) AS wow_delta_cumulative_pp,
    ROUND(y.pct_cumulative_shock - m.pct_cumulative_shock, 2) AS mom_delta_cumulative_pp,
    a.avg7_pct_cumulative_shock,
    IFF(y.pct_cumulative_shock > a.avg7_pct_cumulative_shock, TRUE, FALSE) AS major_shift_cumulative,
    b28.avg28_pct_cumulative_shock,
    b28.sd28_pct_cumulative_shock,
    IFF(
        b28.sd28_pct_cumulative_shock IS NOT NULL
        AND y.pct_cumulative_shock > b28.avg28_pct_cumulative_shock + 2 * b28.sd28_pct_cumulative_shock,
        TRUE, FALSE
    ) AS exception_28d_2sd_cumulative,
    CAST(NULL AS FLOAT) AS cum_trend_t1,
    CAST(NULL AS FLOAT) AS cum_trend_t2,
    y.pct_increase_pricing,
    ROUND(y.pct_increase_pricing - d.pct_increase_pricing, 2) AS dod_delta_pp,
    ROUND(y.pct_increase_pricing - w.pct_increase_pricing, 2) AS wow_delta_pp,
    ROUND(y.pct_increase_pricing - m.pct_increase_pricing, 2) AS mom_delta_pp,
    a.avg7_pct_increase_pricing AS avg7_pct,
    IFF(y.pct_increase_pricing > a.avg7_pct_increase_pricing, TRUE, FALSE) AS major_shift_vs_7d_avg,
    b28.avg28_pct_increase_pricing,
    b28.sd28_pct_increase_pricing,
    IFF(
        b28.sd28_pct_increase_pricing IS NOT NULL
        AND y.pct_increase_pricing > b28.avg28_pct_increase_pricing + 2 * b28.sd28_pct_increase_pricing,
        TRUE, FALSE
    ) AS exception_28d_2sd_residual,
    CAST(NULL AS FLOAT) AS res_trend_t1,
    CAST(NULL AS FLOAT) AS res_trend_t2,
    y.rounding_rides,
    y.pct_rounding,
    ROUND(y.pct_rounding - d.pct_rounding, 2) AS dod_delta_rounding_pp,
    ROUND(y.pct_rounding - w.pct_rounding, 2) AS wow_delta_rounding_pp,
    ROUND(y.pct_rounding - m.pct_rounding, 2) AS mom_delta_rounding_pp,
    a.avg7_pct_rounding,
    IFF(y.pct_rounding > a.avg7_pct_rounding, TRUE, FALSE) AS major_shift_rounding,
    b28.avg28_pct_rounding,
    b28.sd28_pct_rounding,
    IFF(
        b28.sd28_pct_rounding IS NOT NULL
        AND y.pct_rounding > b28.avg28_pct_rounding + 2 * b28.sd28_pct_rounding,
        TRUE, FALSE
    ) AS exception_28d_2sd_rounding,
    y.surcharge_mismatch_rides,
    y.pct_surcharge_mismatch,
    ROUND(y.pct_surcharge_mismatch - d.pct_surcharge_mismatch, 2) AS dod_delta_surcharge_pp,
    ROUND(y.pct_surcharge_mismatch - w.pct_surcharge_mismatch, 2) AS wow_delta_surcharge_pp,
    ROUND(y.pct_surcharge_mismatch - m.pct_surcharge_mismatch, 2) AS mom_delta_surcharge_pp,
    a.avg7_pct_surcharge_mismatch,
    IFF(y.pct_surcharge_mismatch > a.avg7_pct_surcharge_mismatch, TRUE, FALSE) AS major_shift_surcharge_mismatch,
    b28.avg28_pct_surcharge_mismatch,
    b28.sd28_pct_surcharge_mismatch,
    IFF(
        b28.sd28_pct_surcharge_mismatch IS NOT NULL
        AND y.pct_surcharge_mismatch > b28.avg28_pct_surcharge_mismatch + 2 * b28.sd28_pct_surcharge_mismatch,
        TRUE, FALSE
    ) AS exception_28d_2sd_surcharge,
    y.pickup_mismatch_rides,
    y.pct_pickup_mismatch,
    ROUND(y.pct_pickup_mismatch - d.pct_pickup_mismatch, 2) AS dod_delta_pickup_pp,
    ROUND(y.pct_pickup_mismatch - w.pct_pickup_mismatch, 2) AS wow_delta_pickup_pp,
    ROUND(y.pct_pickup_mismatch - m.pct_pickup_mismatch, 2) AS mom_delta_pickup_pp,
    a.avg7_pct_pickup_mismatch,
    IFF(y.pct_pickup_mismatch > a.avg7_pct_pickup_mismatch, TRUE, FALSE) AS major_shift_pickup_mismatch,
    b28.avg28_pct_pickup_mismatch,
    b28.sd28_pct_pickup_mismatch,
    IFF(
        b28.sd28_pct_pickup_mismatch IS NOT NULL
        AND y.pct_pickup_mismatch > b28.avg28_pct_pickup_mismatch + 2 * b28.sd28_pct_pickup_mismatch,
        TRUE, FALSE
    ) AS exception_28d_2sd_pickup,
    y.surge_mismatch_rides,
    y.pct_surge_mismatch,
    ROUND(y.pct_surge_mismatch - d.pct_surge_mismatch, 2) AS dod_delta_surge_pp,
    ROUND(y.pct_surge_mismatch - w.pct_surge_mismatch, 2) AS wow_delta_surge_pp,
    ROUND(y.pct_surge_mismatch - m.pct_surge_mismatch, 2) AS mom_delta_surge_pp,
    a.avg7_pct_surge_mismatch,
    IFF(y.pct_surge_mismatch > a.avg7_pct_surge_mismatch, TRUE, FALSE) AS major_shift_surge_mismatch,
    b28.avg28_pct_surge_mismatch,
    b28.sd28_pct_surge_mismatch,
    IFF(
        b28.sd28_pct_surge_mismatch IS NOT NULL
        AND y.pct_surge_mismatch > b28.avg28_pct_surge_mismatch + 2 * b28.sd28_pct_surge_mismatch,
        TRUE, FALSE
    ) AS exception_28d_2sd_surge,
    y.pd_mismatch_rides,
    y.pct_pd_mismatch,
    ROUND(y.pct_pd_mismatch - d.pct_pd_mismatch, 2) AS dod_delta_pd_pp,
    ROUND(y.pct_pd_mismatch - w.pct_pd_mismatch, 2) AS wow_delta_pd_pp,
    ROUND(y.pct_pd_mismatch - m.pct_pd_mismatch, 2) AS mom_delta_pd_pp,
    a.avg7_pct_pd_mismatch,
    IFF(y.pct_pd_mismatch > a.avg7_pct_pd_mismatch, TRUE, FALSE) AS major_shift_pd_mismatch,
    b28.avg28_pct_pd_mismatch,
    b28.sd28_pct_pd_mismatch,
    IFF(
        b28.sd28_pct_pd_mismatch IS NOT NULL
        AND y.pct_pd_mismatch > b28.avg28_pct_pd_mismatch + 2 * b28.sd28_pct_pd_mismatch,
        TRUE, FALSE
    ) AS exception_28d_2sd_pd
FROM CityYesterday y
LEFT JOIN CityDoD d ON y.country = d.country AND y.city_bucket = d.city_bucket
LEFT JOIN CityWoW w ON y.country = w.country AND y.city_bucket = w.city_bucket
LEFT JOIN CityMoM m ON y.country = m.country AND y.city_bucket = m.city_bucket
LEFT JOIN CityAvg7 a ON y.country = a.country AND y.city_bucket = a.city_bucket
LEFT JOIN CityAvg28 b28 ON y.country = b28.country AND y.city_bucket = b28.city_bucket

ORDER BY 1, 3, 4;
