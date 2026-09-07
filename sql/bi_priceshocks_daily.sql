-- =============================================================================
-- Canonical BI query for full PRICESHOCKS rebuild
-- =============================================================================
-- BI deletes prior JEENY_PROD.RIDE.PRICESHOCKS data then inserts this output.
-- Covers CHANNEL + SCENARIO + CAUSE_MIX + DISCOUNT + GATE in one result set.
-- Fact window: last 30 complete CREATEDDATE days.
-- Spillover lookback: 30 days BEFORE win_start (do not shrink).
-- Specs:
--   docs/price-shock-discounts-bi-handoff.md
--   docs/priceshocks-table.md
--   docs/payment-spillover-price-shocks.md
-- Logic sources (verbatim formulas):
--   sql/bi_fare_integrity_daily_facts.sql  (CHANNEL / SCENARIO / CAUSE_MIX)
--   sql/bi_priceshocks_discount_extension.sql  (DISCOUNT / GATE)
-- GATE4 reconciles against CHANNEL cumulative_price_shocks_net Total rows from
-- THIS query (ChannelLong) — never against JEENY_PROD.RIDE.PRICESHOCKS.
-- =============================================================================

WITH params AS (
    SELECT
        DATEADD('day', -30, CURRENT_DATE()) AS win_start,
        CURRENT_DATE() AS win_end,
        DATEADD('day', -30, DATEADD('day', -30, CURRENT_DATE())) AS lookback_start,
        30 AS lookback_days,
        DATEADD('day', -6, DATEADD('day', -30, CURRENT_DATE())) AS pe_cfg_start
),

/* ---------- Shared spillover lookback (CHANNEL + DISCOUNT) ---------- */
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

/* ==========================================================================
   CHANNEL / SCENARIO / CAUSE_MIX  (from bi_fare_integrity_daily_facts.sql)
   ========================================================================== */

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
        COALESCE(rr.vatoncancellationfine, 0) AS rr_vatcancelfine,
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
        b.createddate AS ride_date,
        b.country,
        b.city_bucket,
        b.rideid,
        LOWER(b.upfrontscenario) AS scenario,
        LOWER(TO_VARCHAR(b.dropoffatdestination)) AS dropoff,
        ROUND(
            (b.rr_total + b.rr_discount + b.rr_vatdiscount)
            - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross), 2
        ) AS fare_diff,
        ROUND(
            (b.rr_total + b.rr_discount + b.rr_vatdiscount)
            - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross)
            - (b.rr_cancelfine + b.rr_vatcancelfine + b.rr_waitingcharges + b.rr_vatwaitingcharges), 2
        ) AS residual,
        IFF(
            ZEROIFNULL(b.prev_outs) > 0
            AND ABS(b.prev_outs - b.rr_cancelfine) <= 0.02,
            1, 0
        ) AS is_spillover_recovery,
        /* CHANNEL: Cumulative PriceShocks % (NET) */
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
        END AS is_cumulative_price_shock,
        /* CHANNEL: Residual fare increase % (NET) */
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
             AND NOT (
                ZEROIFNULL(b.prev_outs) > 0
                AND ABS(b.prev_outs - b.rr_cancelfine) <= 0.02
             )
            THEN 1 ELSE 0
        END AS is_residual_fare_increase,
        /* CHANNEL: Rounding error % */
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
        END AS is_pd_mismatch,
        IFF(
            (COALESCE(b.rr_waitingcharges, 0) + COALESCE(b.rr_vatwaitingcharges, 0)) > 0.01,
            1, 0
        ) AS is_waiting_time,
        /* Canvas scenario segment (NULL = unknown scenario) */
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

ClassifiedX AS (
    SELECT
        c.*,
        c.is_cumulative_price_shock AS is_net_shock
    FROM Classified c
),

ChannelCity AS (
    SELECT
        ride_date,
        country,
        city_bucket,
        COUNT(*) AS rides_denom,
        SUM(is_spillover_recovery) AS spillover_recovery_rides,
        SUM(is_cumulative_price_shock) AS cumulative_shock_rides,
        SUM(is_residual_fare_increase) AS residual_rides,
        SUM(is_rounding) AS rounding_rides,
        SUM(is_surcharge_mismatch) AS surcharge_mismatch_rides,
        SUM(is_pickup_mismatch) AS pickup_mismatch_rides,
        SUM(is_surge_mismatch) AS surge_mismatch_rides,
        SUM(is_pd_mismatch) AS pd_mismatch_rides
    FROM ClassifiedX
    GROUP BY 1, 2, 3
),

ChannelCountry AS (
    SELECT
        ride_date,
        country,
        'Total' AS city_bucket,
        COUNT(*) AS rides_denom,
        SUM(is_spillover_recovery) AS spillover_recovery_rides,
        SUM(is_cumulative_price_shock) AS cumulative_shock_rides,
        SUM(is_residual_fare_increase) AS residual_rides,
        SUM(is_rounding) AS rounding_rides,
        SUM(is_surcharge_mismatch) AS surcharge_mismatch_rides,
        SUM(is_pickup_mismatch) AS pickup_mismatch_rides,
        SUM(is_surge_mismatch) AS surge_mismatch_rides,
        SUM(is_pd_mismatch) AS pd_mismatch_rides
    FROM ClassifiedX
    GROUP BY 1, 2
),

ChannelBase AS (
    SELECT * FROM ChannelCity
    UNION ALL
    SELECT * FROM ChannelCountry
),

ChannelLong AS (
    SELECT ride_date, country, city_bucket, rides_denom, 'CHANNEL' AS metric_family,
           'spillover_recovery' AS metric_name, spillover_recovery_rides AS rides_flagged,
           ROUND(100.0 * spillover_recovery_rides / NULLIF(rides_denom, 0), 2) AS pct
    FROM ChannelBase
    UNION ALL
    SELECT ride_date, country, city_bucket, rides_denom, 'CHANNEL',
           'cumulative_price_shocks_net', cumulative_shock_rides,
           ROUND(100.0 * cumulative_shock_rides / NULLIF(rides_denom, 0), 2)
    FROM ChannelBase
    UNION ALL
    SELECT ride_date, country, city_bucket, rides_denom, 'CHANNEL',
           'residual_fare_increase_net', residual_rides,
           ROUND(100.0 * residual_rides / NULLIF(rides_denom, 0), 2)
    FROM ChannelBase
    UNION ALL
    SELECT ride_date, country, city_bucket, rides_denom, 'CHANNEL',
           'rounding_error', rounding_rides,
           ROUND(100.0 * rounding_rides / NULLIF(rides_denom, 0), 2)
    FROM ChannelBase
    UNION ALL
    SELECT ride_date, country, city_bucket, rides_denom, 'CHANNEL',
           'surcharge_mismatch', surcharge_mismatch_rides,
           ROUND(100.0 * surcharge_mismatch_rides / NULLIF(rides_denom, 0), 2)
    FROM ChannelBase
    UNION ALL
    SELECT ride_date, country, city_bucket, rides_denom, 'CHANNEL',
           'pickup_mismatch', pickup_mismatch_rides,
           ROUND(100.0 * pickup_mismatch_rides / NULLIF(rides_denom, 0), 2)
    FROM ChannelBase
    UNION ALL
    SELECT ride_date, country, city_bucket, rides_denom, 'CHANNEL',
           'surge_mismatch', surge_mismatch_rides,
           ROUND(100.0 * surge_mismatch_rides / NULLIF(rides_denom, 0), 2)
    FROM ChannelBase
    UNION ALL
    SELECT ride_date, country, city_bucket, rides_denom, 'CHANNEL',
           'pd_mismatch', pd_mismatch_rides,
           ROUND(100.0 * pd_mismatch_rides / NULLIF(rides_denom, 0), 2)
    FROM ChannelBase
),

SegmentList AS (
    SELECT column1 AS segment FROM VALUES
        ('withinA_at_dest'),
        ('withinA_not_dest'),
        ('withinB_at_dest'),
        ('withinB_not_dest'),
        ('beyondB')
),

ScenarioCity AS (
    SELECT
        c.ride_date,
        c.country,
        c.city_bucket,
        s.segment AS metric_name,
        COUNT(*) AS rides_denom,
        SUM(IFF(c.scenario_segment = s.segment AND c.is_net_shock = 1, 1, 0)) AS rides_flagged
    FROM ClassifiedX c
    CROSS JOIN SegmentList s
    GROUP BY 1, 2, 3, 4
),

ScenarioCountry AS (
    SELECT
        c.ride_date,
        c.country,
        'Total' AS city_bucket,
        s.segment AS metric_name,
        COUNT(*) AS rides_denom,
        SUM(IFF(c.scenario_segment = s.segment AND c.is_net_shock = 1, 1, 0)) AS rides_flagged
    FROM ClassifiedX c
    CROSS JOIN SegmentList s
    GROUP BY 1, 2, 4
),

ScenarioLong AS (
    SELECT
        ride_date,
        country,
        city_bucket,
        rides_denom,
        'SCENARIO' AS metric_family,
        metric_name,
        rides_flagged,
        ROUND(100.0 * rides_flagged / NULLIF(rides_denom, 0), 2) AS pct
    FROM (
        SELECT * FROM ScenarioCity
        UNION ALL
        SELECT * FROM ScenarioCountry
    )
),

GrossShocks AS (
    SELECT
        c.ride_date,
        c.country,
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
        END AS metric_name
    FROM ClassifiedX c
    WHERE c.fare_diff > 0.01
),

CauseMixAgg AS (
    SELECT
        g.ride_date,
        g.country,
        g.metric_name,
        COUNT(*) AS rides_flagged
    FROM GrossShocks g
    GROUP BY 1, 2, 3
),

CauseMixLong AS (
    SELECT
        a.ride_date,
        a.country,
        'Total' AS city_bucket,
        SUM(a.rides_flagged) OVER (PARTITION BY a.ride_date, a.country) AS rides_denom,
        'CAUSE_MIX' AS metric_family,
        a.metric_name,
        a.rides_flagged,
        ROUND(
            100.0 * a.rides_flagged
            / NULLIF(SUM(a.rides_flagged) OVER (PARTITION BY a.ride_date, a.country), 0),
            2
        ) AS pct
    FROM CauseMixAgg a
),

/* ==========================================================================
   DISCOUNT / GATE  (from bi_priceshocks_discount_extension.sql)
   ========================================================================== */

pe_raw AS (
    SELECT
        rd.createddate AS ride_date,
        pe.promotionid,
        ga.country_code AS country,
        COALESCE(rd.discountrr, 0) AS disc,
        COALESCE(rd.vatondiscount, 0) AS vdisc,
        IFF(ga.country_code = 'SA', 1.15, 1.00) AS vatf,
        COALESCE(rd.ridevalue, 0)
            + COALESCE(rd.ridehailingsurcharge, 0)
            + COALESCE(rd.surcharge, 0)
            + COALESCE(rd.intercitysurcharge, 0)
            + COALESCE(rd.waitingtimefee, 0) AS ride_base
    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.GENERAL.AREAS ga
        ON ga.area_code = rd.area_code
    JOIN JEENY_PROD.PASSENGERS.PROMOTIONENGINE pe
        ON pe.rideid = rd.rideid
    CROSS JOIN params p
    WHERE rd.boarded IS NOT NULL
      AND ga.country_code IN ('SA', 'JO')
      AND rd.createddate >= p.pe_cfg_start
      AND rd.createddate < p.win_end
      AND COALESCE(rd.discountrr, 0) > 0.001
),

pe_days AS (
    SELECT DISTINCT
        r.ride_date,
        r.promotionid,
        r.country
    FROM pe_raw r
    CROSS JOIN params p
    WHERE r.ride_date >= p.win_start
),

pe_max_daily AS (
    SELECT
        d.ride_date,
        d.promotionid,
        d.country,
        MAX(r.disc) AS cap_exvat
    FROM pe_days d
    JOIN pe_raw r
        ON r.promotionid = d.promotionid
       AND r.country = d.country
       AND r.ride_date BETWEEN DATEADD('day', -6, d.ride_date) AND d.ride_date
    GROUP BY 1, 2, 3
),

pe_cfg_daily AS (
    SELECT
        m.ride_date,
        m.promotionid,
        m.country,
        m.cap_exvat,
        ROUND(MEDIAN(r.disc / NULLIF(r.ride_base, 0)) * 100, 0) AS pct,
        COUNT(*) AS n_uncapped
    FROM pe_max_daily m
    JOIN pe_raw r
        ON r.promotionid = m.promotionid
       AND r.country = m.country
       AND r.ride_date BETWEEN DATEADD('day', -6, m.ride_date) AND m.ride_date
    WHERE r.disc < m.cap_exvat - 0.011
      AND r.ride_base > 0
    GROUP BY 1, 2, 3, 4
),

promo AS (
    SELECT
        pk.traceid,
        MAX(IFF(pk.isvalid, 1, 0)) AS voucher_valid,
        MAX(IFF(pk.isvalid, pk.discountvalue, NULL)) AS dv,
        MAX(IFF(pk.isvalid, pk.maximumdiscount, NULL)) AS cap,
        MAX(IFF(pk.isvalid, UPPER(pk.discounttype), NULL)) AS dtype,
        COUNT(DISTINCT IFF(pk.isvalid, UPPER(pk.vouchercode), NULL)) AS n_codes,
        COUNT(DISTINCT IFF(pk.isvalid, pk.discountvalue, NULL)) AS n_values
    FROM JEENY_PROD.PASSENGERS.PRICECHECKKAFKAWITHPROMO pk
    CROSS JOIN params p
    WHERE pk.traceid IS NOT NULL
      AND pk.eventtimestamp >= DATEADD('day', -1, p.win_start)
      AND pk.eventtimestamp < DATEADD('day', 1, p.win_end)
    GROUP BY pk.traceid
),

disc_base AS (
    SELECT
        rd.rideid,
        rd.createddate AS ride_date,
        ga.country_code AS country,
        IFF(ga.country_code = 'SA', 1.15, 1.00) AS vatf,
        COALESCE(pc.value, 0) AS pc_value,
        COALESCE(pc.vat, 0) AS pc_vat_hailing,
        ROUND(
            COALESCE(pc.surcharge, 0)
                * IFF(ga.country_code = 'SA', 1.15, 1.00),
            2
        ) AS pc_surcharge_gross,
        COALESCE(rr.totalamountwithtax, 0) AS charged_net,
        COALESCE(rr.discount, 0) AS act_disc_exvat,
        COALESCE(rr.vatondiscount, 0) AS act_disc_vat,
        COALESCE(rr.cancellationfine, 0) AS rr_cancelfine,
        po.prev_outs,
        COALESCE(rd.ridevalue, 0)
            + COALESCE(rd.ridehailingsurcharge, 0)
            + COALESCE(rd.surcharge, 0)
            + COALESCE(rd.intercitysurcharge, 0)
            + COALESCE(rd.waitingtimefee, 0) AS ride_base_exvat,
        IFF(pe.rideid IS NOT NULL, 1, 0) AS has_promo_engine,
        pe.promotionid,
        cfg.cap_exvat AS pe_cap_exvat,
        cfg.pct AS pe_pct,
        cfg.n_uncapped AS pe_n_uncapped,
        COALESCE(pr.voucher_valid, 0) AS voucher_valid,
        pr.dv,
        pr.cap,
        pr.dtype,
        COALESCE(pr.n_codes, 0) AS n_codes,
        COALESCE(pr.n_values, 0) AS n_values,
        ROUND(COALESCE(pc.value, 0)
            / IFF(ga.country_code = 'SA', 1.15, 1.00), 2)
          + ROUND(COALESCE(pc.vat, 0)
            / IFF(ga.country_code = 'SA', 1.15, 1.00), 2)
          + COALESCE(pc.surcharge, 0) AS quote_base_exvat
    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.RIDE.UPFRONT uf
        ON uf.rideid = rd.rideid
    JOIN JEENY_PROD.RIDE.RECEIPTS rr
        ON rr.rideid = rd.rideid
    JOIN JEENY_PROD.GENERAL.AREAS ga
        ON ga.area_code = rd.area_code
    JOIN JEENY_PROD.PASSENGERS.PRICECHECKS pc
        ON pc.rideid = rd.rideid
       AND LOWER(pc.servicefilter) = LOWER(rd.request_service)
    LEFT JOIN PrevOuts po
        ON po.rideid = rd.rideid
    LEFT JOIN JEENY_PROD.PASSENGERS.PROMOTIONENGINE pe
        ON pe.rideid = rd.rideid
    LEFT JOIN pe_cfg_daily cfg
        ON cfg.ride_date = rd.createddate
       AND cfg.promotionid = pe.promotionid
       AND cfg.country = ga.country_code
    LEFT JOIN promo pr
        ON pr.traceid = rd.traceid
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

disc_calc AS (
    SELECT
        b.*,
        ROUND(
            b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross,
            2
        ) AS pc_shown,
        ROUND(
            (b.charged_net + b.act_disc_exvat + b.act_disc_vat)
                - (b.pc_value + b.pc_vat_hailing + b.pc_surcharge_gross),
            2
        ) AS fare_diff,
        ROUND(b.act_disc_exvat + b.act_disc_vat, 2) AS act_disc_gross,
        IFF(
            ZEROIFNULL(b.prev_outs) > 0
            AND ABS(b.prev_outs - b.rr_cancelfine) <= 0.02,
            1, 0
        ) AS is_spillover_recovery,
        CASE
            WHEN b.voucher_valid = 1
             AND b.n_codes = 1
             AND b.n_values = 1
             AND b.dtype = 'PERCENTAGE'
                THEN ROUND(LEAST(
                    ROUND(b.cap / b.vatf, 2),
                    ROUND(b.dv / 100.0 * b.quote_base_exvat, 2)
                ), 2)
            WHEN b.voucher_valid = 1
             AND b.n_codes = 1
             AND b.n_values = 1
             AND b.dtype = 'FIXED_AMOUNT'
                THEN ROUND(LEAST(
                    ROUND(b.dv / b.vatf, 2),
                    b.quote_base_exvat
                ), 2)
            WHEN b.has_promo_engine = 1
             AND b.pe_pct IS NOT NULL
                THEN ROUND(LEAST(
                    b.pe_cap_exvat,
                    ROUND(b.pe_pct / 100.0 * b.quote_base_exvat, 2)
                ), 2)
            ELSE 0
        END AS exp_disc_exvat,
        CASE
            WHEN b.voucher_valid = 1
             AND b.n_codes = 1
             AND b.n_values = 1
             AND b.dtype = 'PERCENTAGE'
                THEN IFF(
                    ROUND(b.dv / 100.0 * b.quote_base_exvat, 2)
                        >= ROUND(b.cap / b.vatf, 2) - 0.005,
                    1, 0
                )
            WHEN b.has_promo_engine = 1
             AND b.pe_pct IS NOT NULL
                THEN IFF(
                    ROUND(b.pe_pct / 100.0 * b.quote_base_exvat, 2)
                        >= b.pe_cap_exvat - 0.005,
                    1, 0
                )
            ELSE 0
        END AS cap_bound_at_quote,
        CASE
            WHEN b.voucher_valid = 1
             AND b.n_codes = 1
             AND b.n_values = 1
             AND b.dtype = 'PERCENTAGE'
                THEN ROUND(LEAST(
                    ROUND(b.cap / b.vatf, 2),
                    ROUND(b.dv / 100.0 * b.ride_base_exvat, 2)
                ), 2)
            WHEN b.has_promo_engine = 1
             AND b.pe_pct IS NOT NULL
                THEN ROUND(LEAST(
                    b.pe_cap_exvat,
                    ROUND(b.pe_pct / 100.0 * b.ride_base_exvat, 2)
                ), 2)
            ELSE NULL
        END AS expected_applied_disc_exvat
    FROM disc_base b
),

disc_grossed AS (
    SELECT
        c.*,
        ROUND(
            c.exp_disc_exvat
                + ROUND(c.exp_disc_exvat * (c.vatf - 1), 2),
            2
        ) AS exp_disc_gross
    FROM disc_calc c
),

disc_final AS (
    SELECT
        g.*,
        ROUND(g.pc_shown - g.exp_disc_gross, 2) AS pc_net,
        ROUND(
            g.charged_net - (g.pc_shown - g.exp_disc_gross),
            2
        ) AS net_fare_diff,
        ROUND(g.exp_disc_gross - g.act_disc_gross, 2) AS d_discount,
        CASE
            WHEN g.voucher_valid = 1
             AND g.n_codes = 1
             AND g.n_values = 1
             AND g.cap_bound_at_quote = 1
                THEN 'voucher_capped'
            WHEN g.voucher_valid = 1
             AND g.n_codes = 1
             AND g.n_values = 1
                THEN 'voucher_pct_bound'
            WHEN g.has_promo_engine = 1
             AND g.cap_bound_at_quote = 1
                THEN 'promoeng_capped'
            WHEN g.has_promo_engine = 1
                THEN 'promoeng_pct_bound'
            WHEN g.act_disc_gross > 0.01
                THEN 'discount_no_source'
            ELSE 'no_discount'
        END AS discount_segment,
        IFF(
            g.voucher_valid = 1
            AND g.n_codes = 1
            AND g.n_values = 1
            AND g.act_disc_gross <= 0.01,
            1, 0
        ) AS promised_not_applied
    FROM disc_grossed g
),

country_daily AS (
    SELECT
        f.ride_date,
        f.country,
        COUNT(*) AS country_rides_total
    FROM disc_final f
    GROUP BY 1, 2
),

segment_stats AS (
    SELECT
        f.ride_date,
        f.country,
        f.discount_segment AS segment,
        COUNT(*) AS rides_total,
        SUM(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0, 1, 0
        )) AS gross_shock_rides,
        SUM(IFF(
            f.net_fare_diff > 0.01 AND f.is_spillover_recovery = 0, 1, 0
        )) AS net_shock_rides,
        ROUND(SUM(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            f.fare_diff, 0
        )), 2) AS gross_excess_amount,
        ROUND(SUM(IFF(
            f.net_fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            f.net_fare_diff, 0
        )), 2) AS net_excess_amount,
        ROUND(AVG(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            f.fare_diff, NULL
        )), 2) AS avg_gross_excess,
        ROUND(AVG(IFF(
            f.net_fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            f.net_fare_diff, NULL
        )), 2) AS avg_net_excess,
        ROUND(AVG(IFF(
            f.is_spillover_recovery = 0, f.d_discount, NULL
        )), 3) AS avg_d_discount
    FROM disc_final f
    GROUP BY 1, 2, 3
),

summary_stats AS (
    SELECT
        f.ride_date,
        f.country,
        IFF(
            f.discount_segment IN ('voucher_capped', 'promoeng_capped'),
            'cap_bound_total',
            'pct_bound_total'
        ) AS segment,
        COUNT(*) AS rides_total,
        SUM(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0, 1, 0
        )) AS gross_shock_rides,
        SUM(IFF(
            f.net_fare_diff > 0.01 AND f.is_spillover_recovery = 0, 1, 0
        )) AS net_shock_rides,
        ROUND(SUM(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            f.fare_diff, 0
        )), 2) AS gross_excess_amount,
        ROUND(SUM(IFF(
            f.net_fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            f.net_fare_diff, 0
        )), 2) AS net_excess_amount,
        ROUND(AVG(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            f.fare_diff, NULL
        )), 2) AS avg_gross_excess,
        ROUND(AVG(IFF(
            f.net_fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            f.net_fare_diff, NULL
        )), 2) AS avg_net_excess,
        ROUND(AVG(IFF(
            f.is_spillover_recovery = 0, f.d_discount, NULL
        )), 3) AS avg_d_discount
    FROM disc_final f
    WHERE f.discount_segment IN (
        'voucher_capped',
        'voucher_pct_bound',
        'promoeng_capped',
        'promoeng_pct_bound'
    )
    GROUP BY 1, 2, 3
),

promised_stats AS (
    SELECT
        f.ride_date,
        f.country,
        'promised_not_applied' AS segment,
        COUNT(*) AS rides_total,
        SUM(f.promised_not_applied) AS net_shock_rides,
        CAST(NULL AS NUMBER) AS gross_shock_rides,
        CAST(NULL AS NUMBER(18, 2)) AS gross_excess_amount,
        CAST(NULL AS NUMBER(18, 2)) AS net_excess_amount,
        CAST(NULL AS NUMBER(18, 2)) AS avg_gross_excess,
        CAST(NULL AS NUMBER(18, 2)) AS avg_net_excess,
        CAST(NULL AS NUMBER(18, 3)) AS avg_d_discount
    FROM disc_final f
    GROUP BY 1, 2, 3
),

all_segments AS (
    SELECT * FROM segment_stats
    UNION ALL
    SELECT * FROM summary_stats
    UNION ALL
    SELECT
        ride_date,
        country,
        segment,
        rides_total,
        gross_shock_rides,
        net_shock_rides,
        gross_excess_amount,
        net_excess_amount,
        avg_gross_excess,
        avg_net_excess,
        avg_d_discount
    FROM promised_stats
),

discount_long AS (
    /* Ride share of segment / country */
    SELECT
        s.ride_date,
        'DISCOUNT' AS metric_family,
        s.segment || '__ride_share' AS metric_name,
        s.country,
        'Total' AS city_bucket,
        c.country_rides_total AS rides_denom,
        s.rides_total AS rides_flagged,
        ROUND(100.0 * s.rides_total / NULLIF(c.country_rides_total, 0), 2) AS pct,
        CAST(NULL AS NUMBER(18, 2)) AS amount_value,
        CAST(NULL AS NUMBER(18, 3)) AS avg_value
    FROM all_segments s
    JOIN country_daily c
        ON c.ride_date = s.ride_date
       AND c.country = s.country
    WHERE s.segment <> 'promised_not_applied'

    UNION ALL

    /* Gross fare_diff shock rate within segment */
    SELECT
        s.ride_date,
        'DISCOUNT',
        s.segment || '__gross_shock',
        s.country,
        'Total',
        s.rides_total,
        s.gross_shock_rides,
        ROUND(100.0 * s.gross_shock_rides / NULLIF(s.rides_total, 0), 2),
        s.gross_excess_amount,
        s.avg_gross_excess
    FROM all_segments s
    WHERE s.segment <> 'promised_not_applied'
      AND s.gross_shock_rides IS NOT NULL

    UNION ALL

    /* Post-discount net_fare_diff shock rate within segment */
    SELECT
        s.ride_date,
        'DISCOUNT',
        s.segment || '__net_shock',
        s.country,
        'Total',
        s.rides_total,
        s.net_shock_rides,
        ROUND(100.0 * s.net_shock_rides / NULLIF(s.rides_total, 0), 2),
        s.net_excess_amount,
        s.avg_d_discount
    FROM all_segments s
    WHERE s.segment <> 'promised_not_applied'

    UNION ALL

    /* Absorption = (gross excess - net excess) / gross excess */
    SELECT
        s.ride_date,
        'DISCOUNT',
        s.segment || '__absorption',
        s.country,
        'Total',
        1,
        1,
        ROUND(
            100.0 * (s.gross_excess_amount - s.net_excess_amount)
                / NULLIF(s.gross_excess_amount, 0),
            2
        ),
        CAST(NULL AS NUMBER(18, 2)),
        CAST(NULL AS NUMBER(18, 3))
    FROM all_segments s
    WHERE s.segment <> 'promised_not_applied'
      AND s.gross_excess_amount IS NOT NULL

    UNION ALL

    /* Promised voucher at quote but not applied on receipt */
    SELECT
        s.ride_date,
        'DISCOUNT',
        'promised_not_applied',
        s.country,
        'Total',
        s.rides_total,
        s.net_shock_rides,
        ROUND(100.0 * s.net_shock_rides / NULLIF(s.rides_total, 0), 2),
        CAST(NULL AS NUMBER(18, 2)),
        CAST(NULL AS NUMBER(18, 3))
    FROM all_segments s
    WHERE s.segment = 'promised_not_applied'
),

gate1_voucher AS (
    SELECT
        f.ride_date,
        f.country,
        COUNT(*) AS n,
        ROUND(100.0 * SUM(IFF(
            ABS(f.act_disc_exvat - f.expected_applied_disc_exvat) <= 0.011,
            1, 0
        )) / NULLIF(COUNT(*), 0), 3) AS formula_match_pct,
        ROUND(100.0 * SUM(IFF(
            ABS(f.act_disc_vat
                - ROUND(f.act_disc_exvat * (f.vatf - 1), 2)) <= 0.011,
            1, 0
        )) / NULLIF(COUNT(*), 0), 3) AS vat_match_pct
    FROM disc_final f
    WHERE f.voucher_valid = 1
      AND f.n_codes = 1
      AND f.n_values = 1
      AND f.dtype = 'PERCENTAGE'
      AND f.has_promo_engine = 0
      AND f.act_disc_exvat > 0.001
    GROUP BY 1, 2
),

gate1_promo AS (
    /* All promotion-engine campaigns pooled to one country-day row */
    SELECT
        d.ride_date,
        d.country,
        COUNT(*) AS n,
        COUNT(DISTINCT d.promotionid) AS n_promos,
        ROUND(100.0 * SUM(IFF(
            ABS(r.disc - ROUND(LEAST(
                cfg.cap_exvat,
                ROUND(cfg.pct / 100.0 * r.ride_base, 2)
            ), 2)) <= 0.011,
            1, 0
        )) / NULLIF(COUNT(*), 0), 3) AS formula_match_pct,
        ROUND(100.0 * SUM(IFF(
            ABS(r.vdisc - ROUND(r.disc * (r.vatf - 1), 2)) <= 0.011,
            1, 0
        )) / NULLIF(COUNT(*), 0), 3) AS vat_match_pct
    FROM pe_days d
    JOIN pe_raw r
        ON r.promotionid = d.promotionid
       AND r.country = d.country
       AND r.ride_date BETWEEN DATEADD('day', -6, d.ride_date) AND d.ride_date
    LEFT JOIN pe_cfg_daily cfg
        ON cfg.ride_date = d.ride_date
       AND cfg.promotionid = d.promotionid
       AND cfg.country = d.country
    GROUP BY 1, 2
),

gate2_identity AS (
    SELECT
        f.ride_date,
        f.country,
        COUNT(*) AS n,
        SUM(IFF(
            ABS(f.net_fare_diff - (f.fare_diff + f.d_discount)) <= 0.011,
            1, 0
        )) AS identity_holds
    FROM disc_final f
    GROUP BY 1, 2
),

gate3_by_promo AS (
    SELECT
        f.ride_date,
        f.country,
        f.promotionid,
        COUNT(*) AS rides_today,
        MAX(f.pe_pct) AS derived_pct,
        MAX(f.pe_cap_exvat) AS derived_cap_exvat,
        MAX(f.pe_n_uncapped) AS n_uncapped
    FROM disc_final f
    WHERE f.has_promo_engine = 1
    GROUP BY 1, 2, 3
),

gate3_config AS (
    /* All campaigns pooled: pass only if every active promo on the day passes */
    SELECT
        ride_date,
        country,
        SUM(rides_today) AS rides_today,
        COUNT(*) AS n_promos,
        SUM(IFF(
            derived_pct IS NOT NULL
            AND derived_cap_exvat IS NOT NULL
            AND COALESCE(n_uncapped, 0) >= 50,
            1, 0
        )) AS n_promos_ok,
        ROUND(
            100.0 * SUM(IFF(
                derived_pct IS NOT NULL
                AND derived_cap_exvat IS NOT NULL
                AND COALESCE(n_uncapped, 0) >= 50,
                1, 0
            )) / NULLIF(COUNT(*), 0),
            2
        ) AS pct_promos_ok,
        ROUND(AVG(derived_pct), 2) AS avg_derived_pct,
        ROUND(AVG(derived_cap_exvat), 2) AS avg_derived_cap_exvat,
        SUM(COALESCE(n_uncapped, 0)) AS total_n_uncapped
    FROM gate3_by_promo
    GROUP BY 1, 2
),

gross_daily AS (
    SELECT
        f.ride_date,
        f.country,
        COUNT(*) AS rides_total,
        SUM(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0, 1, 0
        )) AS gross_shock_rides
    FROM disc_final f
    GROUP BY 1, 2
),

/* GATE4: reconcile vs CHANNEL cumulative_price_shocks_net Total from THIS query */
gate4_reconcile AS (
    SELECT
        g.ride_date,
        g.country,
        g.rides_total,
        g.gross_shock_rides,
        ch.rides_denom AS ps_rides_total,
        ch.rides_flagged AS ps_gross_shock_rides
    FROM gross_daily g
    LEFT JOIN ChannelLong ch
        ON ch.ride_date = g.ride_date
       AND ch.country = g.country
       AND ch.city_bucket = 'Total'
       AND ch.metric_family = 'CHANNEL'
       AND ch.metric_name = 'cumulative_price_shocks_net'
),

gate5_direction AS (
    SELECT
        s.ride_date,
        s.country,
        s.segment,
        s.rides_total,
        ROUND(100.0 * s.gross_shock_rides / NULLIF(s.rides_total, 0), 2)
            AS gross_shock_pct,
        ROUND(100.0 * s.net_shock_rides / NULLIF(s.rides_total, 0), 2)
            AS net_shock_pct,
        s.avg_d_discount
    FROM segment_stats s
    WHERE s.segment IN (
        'voucher_capped',
        'voucher_pct_bound',
        'promoeng_capped',
        'promoeng_pct_bound'
    )
),

gate_long AS (
    /* RIDES_FLAGGED = 1 PASS / 0 FAIL for gate rows */
    SELECT
        v.ride_date,
        'GATE' AS metric_family,
        'gate1_voucher_formula' AS metric_name,
        v.country,
        'Total' AS city_bucket,
        v.n AS rides_denom,
        IFF(v.formula_match_pct >= 99.9 AND v.vat_match_pct >= 99.9, 1, 0)
            AS rides_flagged,
        v.formula_match_pct AS pct,
        v.vat_match_pct AS amount_value,
        CAST(NULL AS NUMBER(18, 3)) AS avg_value
    FROM gate1_voucher v

    UNION ALL

    SELECT
        p.ride_date,
        'GATE',
        'gate1_promo_formula',
        p.country,
        'Total',
        p.n,
        IFF(p.formula_match_pct >= 99.9 AND p.vat_match_pct >= 99.9, 1, 0),
        p.formula_match_pct,
        p.vat_match_pct,
        p.n_promos
    FROM gate1_promo p

    UNION ALL

    SELECT
        i.ride_date,
        'GATE',
        'gate2_net_fare_identity',
        i.country,
        'Total',
        i.n,
        IFF(i.identity_holds / NULLIF(i.n, 0) >= 0.9999, 1, 0),
        ROUND(100.0 * i.identity_holds / NULLIF(i.n, 0), 4),
        CAST(NULL AS NUMBER(18, 2)),
        CAST(NULL AS NUMBER(18, 3))
    FROM gate2_identity i

    UNION ALL

    SELECT
        c.ride_date,
        'GATE',
        'gate3_promo_config',
        c.country,
        'Total',
        c.rides_today,
        IFF(c.n_promos_ok = c.n_promos AND c.n_promos > 0, 1, 0),
        c.pct_promos_ok,
        c.avg_derived_cap_exvat,
        c.total_n_uncapped
    FROM gate3_config c

    UNION ALL

    SELECT
        r.ride_date,
        'GATE',
        'gate4_priceshocks_reconciliation',
        r.country,
        'Total',
        r.rides_total,
        IFF(
            r.rides_total = r.ps_rides_total
            AND r.gross_shock_rides = r.ps_gross_shock_rides,
            1, 0
        ),
        ROUND(100.0 * r.gross_shock_rides / NULLIF(r.rides_total, 0), 2),
        CAST(NULL AS NUMBER(18, 2)),
        CAST(NULL AS NUMBER(18, 3))
    FROM gate4_reconcile r

    UNION ALL

    SELECT
        d.ride_date,
        'GATE',
        'gate5_segment_direction:' || d.segment,
        d.country,
        'Total',
        d.rides_total,
        IFF(
            d.segment IN ('voucher_capped', 'promoeng_capped'),
            IFF(d.net_shock_pct >= d.gross_shock_pct, 1, 0),
            IFF(d.avg_d_discount < 0, 1, 0)
        ),
        d.net_shock_pct,
        d.gross_shock_pct,
        d.avg_d_discount
    FROM gate5_direction d
),

/* ---------- Unified output ---------- */
Unified AS (
    SELECT
        ride_date,
        metric_family,
        metric_name,
        country,
        city_bucket,
        rides_denom,
        rides_flagged,
        pct,
        CAST(NULL AS NUMBER(18, 2)) AS amount_value,
        CAST(NULL AS NUMBER(18, 3)) AS avg_value
    FROM ChannelLong

    UNION ALL

    SELECT
        ride_date,
        metric_family,
        metric_name,
        country,
        city_bucket,
        rides_denom,
        rides_flagged,
        pct,
        CAST(NULL AS NUMBER(18, 2)),
        CAST(NULL AS NUMBER(18, 3))
    FROM ScenarioLong

    UNION ALL

    SELECT
        ride_date,
        metric_family,
        metric_name,
        country,
        city_bucket,
        rides_denom,
        rides_flagged,
        pct,
        CAST(NULL AS NUMBER(18, 2)),
        CAST(NULL AS NUMBER(18, 3))
    FROM CauseMixLong

    UNION ALL

    SELECT
        ride_date,
        metric_family,
        metric_name,
        country,
        city_bucket,
        rides_denom,
        rides_flagged,
        pct,
        amount_value,
        avg_value
    FROM discount_long

    UNION ALL

    SELECT
        ride_date,
        metric_family,
        metric_name,
        country,
        city_bucket,
        rides_denom,
        rides_flagged,
        pct,
        amount_value,
        avg_value
    FROM gate_long
)

SELECT
    ride_date,
    metric_family,
    metric_name,
    country,
    city_bucket,
    rides_denom,
    rides_flagged,
    pct,
    amount_value,
    avg_value,
    CURRENT_TIMESTAMP() AS computed_at
FROM Unified
ORDER BY ride_date, country, metric_family, metric_name, city_bucket;
