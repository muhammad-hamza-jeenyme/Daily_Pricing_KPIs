-- =============================================================================
-- BI HANDOFF: discount-aware price-shock daily facts
-- =============================================================================
-- Proposed target: JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS
-- Companion table: JEENY_PROD.RIDE.PRICESHOCKS (existing fare-integrity facts)
--
-- This query ADDS passenger-experienced, post-discount analysis. It does not
-- replace or alter the existing fare_diff PriceShocks metrics.
--
-- Fact window: last 60 complete CREATEDDATE days.
-- Spillover lookback: 30 days BEFORE fact-window start (do not shrink).
-- Promotion-engine config: derived per PROMOTIONID from each ride day's
-- trailing 7 days (do not hardcode rate/cap).
--
-- Specs:
--   docs/price-shock-discounts-implementation-spec.md
--   docs/price-shock-discounts-bi-handoff.md
-- =============================================================================

WITH params AS (
    SELECT
        DATEADD('day', -60, CURRENT_DATE()) AS win_start,
        CURRENT_DATE() AS win_end,
        DATEADD('day', -30, DATEADD('day', -60, CURRENT_DATE())) AS lookback_start,
        DATEADD('day', -6, DATEADD('day', -60, CURRENT_DATE())) AS pe_cfg_start
),

/* 30-day pre-window history is load-bearing for spillover recovery detection. */
lookback_rides AS (
    SELECT
        rd.rideid,
        rd.passengerid,
        rd.created,
        rd.outstandingbalance AS outs
    FROM JEENY_PROD.RIDE.DETAILS rd
    JOIN JEENY_PROD.GENERAL.AREAS ga
        ON ga.area_code = rd.area_code
    CROSS JOIN params p
    WHERE rd.createddate >= p.lookback_start
      AND rd.createddate < p.win_end
      AND ga.country_code IN ('SA', 'JO')
),

prev_outs AS (
    SELECT
        rideid,
        LAG(outs) OVER (
            PARTITION BY passengerid
            ORDER BY created
        ) AS prev_outs
    FROM lookback_rides
),

/* Promotion-engine observed behaviour; include six pre-window days so the
   first fact day also has a complete trailing-seven-day config window. */
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

/* Rate is inferred only from strictly below-cap rides. */
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

/* Quote-time voucher: aggregate to ONE ROW PER TRACEID before joining.
   PRICECHECKKAFKAWITHPROMO is natively TRACEID × SERVICES. */
promo AS (
    SELECT
        pk.traceid,
        MAX(IFF(pk.isvalid, 1, 0)) AS voucher_valid,
        MAX(IFF(pk.isvalid, pk.discountvalue, NULL)) AS dv,
        MAX(IFF(pk.isvalid, pk.maximumdiscount, NULL)) AS cap,
        MAX(IFF(pk.isvalid, UPPER(pk.discounttype), NULL)) AS dtype,
        MAX(IFF(pk.isvalid, UPPER(pk.vouchercode), NULL)) AS voucher_code,
        COUNT(DISTINCT IFF(pk.isvalid, UPPER(pk.vouchercode), NULL)) AS n_codes,
        COUNT(DISTINCT IFF(pk.isvalid, pk.discountvalue, NULL)) AS n_values,
        MAX(IFF(
            NOT pk.isvalid,
            NULLIF(pk.failurereason, ''),
            NULL
        )) AS failure_reason
    FROM JEENY_PROD.PASSENGERS.PRICECHECKKAFKAWITHPROMO pk
    CROSS JOIN params p
    WHERE pk.traceid IS NOT NULL
      AND pk.eventtimestamp >= DATEADD('day', -1, p.win_start)
      AND pk.eventtimestamp < DATEADD('day', 1, p.win_end)
    GROUP BY pk.traceid
),

base AS (
    SELECT
        rd.rideid,
        rd.createddate AS ride_date,
        ga.country_code AS country,
        IFF(ga.country_code = 'SA', 1.15, 1.00) AS vatf,
        IFF(ga.country_code = 'SA', 'SAR', 'JOD') AS currency,
        COALESCE(pc.value, 0) AS pc_value,
        COALESCE(pc.vat, 0) AS pc_vat_hailing,
        COALESCE(pc.surcharge, 0) AS pc_surcharge_exvat,
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
        pr.voucher_code,
        COALESCE(pr.n_codes, 0) AS n_codes,
        COALESCE(pr.n_values, 0) AS n_values,
        pr.failure_reason,
        UPPER(rd.paymentvouchercode) AS applied_voucher_code,
        /* Build quote discountable base component-wise. */
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
    LEFT JOIN prev_outs po
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

calc AS (
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
            /* Voucher takes precedence if both programs occur. */
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
        /* Gate 1 expected APPLIED discount, evaluated on final ride base. */
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
    FROM base b
),

grossed AS (
    SELECT
        c.*,
        ROUND(
            c.exp_disc_exvat
                + ROUND(c.exp_disc_exvat * (c.vatf - 1), 2),
            2
        ) AS exp_disc_gross
    FROM calc c
),

final AS (
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
    FROM grossed g
),

country_daily AS (
    SELECT
        f.ride_date,
        f.country,
        COUNT(*) AS country_rides_total
    FROM final f
    GROUP BY 1, 2
),

/* Six required discount segments. All shock metrics exclude spillover recovery. */
segment_agg AS (
    SELECT
        f.ride_date,
        f.discount_segment,
        f.country,
        COUNT(*) AS rides_total,
        SUM(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            1, 0
        )) AS gross_shock_rides,
        SUM(IFF(
            f.net_fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            1, 0
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
            f.is_spillover_recovery = 0,
            f.d_discount, NULL
        )), 3) AS avg_d_discount,
        SUM(f.promised_not_applied) AS promised_not_applied_rides,
        MAX(f.currency) AS currency
    FROM final f
    GROUP BY 1, 2, 3
),

segment_daily AS (
    SELECT
        a.ride_date,
        'SEGMENT' AS row_type,
        a.discount_segment,
        a.country,
        'Total' AS city_bucket,
        c.country_rides_total,
        ROUND(100.0 * a.rides_total / NULLIF(c.country_rides_total, 0), 2)
            AS ride_share_pct,
        a.rides_total,
        a.gross_shock_rides,
        a.net_shock_rides,
        ROUND(100.0 * a.gross_shock_rides / NULLIF(a.rides_total, 0), 2)
            AS gross_shock_pct,
        ROUND(100.0 * a.net_shock_rides / NULLIF(a.rides_total, 0), 2)
            AS net_shock_pct,
        a.gross_excess_amount,
        a.net_excess_amount,
        a.avg_gross_excess,
        a.avg_net_excess,
        a.avg_d_discount,
        ROUND(
            100.0 * (a.gross_excess_amount - a.net_excess_amount)
                / NULLIF(a.gross_excess_amount, 0),
            2
        ) AS absorption_pct,
        IFF(a.discount_segment IN (
            'voucher_capped', 'promoeng_capped'
        ), 1, 0) AS cap_bound_at_quote,
        a.promised_not_applied_rides,
        a.currency
    FROM segment_agg a
    JOIN country_daily c
        ON c.ride_date = a.ride_date
       AND c.country = a.country
),

summary_agg AS (
    SELECT
        f.ride_date,
        IFF(
            f.discount_segment IN ('voucher_capped', 'promoeng_capped'),
            'cap_bound_total',
            'pct_bound_total'
        ) AS discount_segment,
        f.country,
        COUNT(*) AS rides_total,
        SUM(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            1, 0
        )) AS gross_shock_rides,
        SUM(IFF(
            f.net_fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            1, 0
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
            f.is_spillover_recovery = 0,
            f.d_discount, NULL
        )), 3) AS avg_d_discount,
        SUM(f.promised_not_applied) AS promised_not_applied_rides,
        MAX(f.currency) AS currency
    FROM final f
    WHERE f.discount_segment IN (
        'voucher_capped',
        'voucher_pct_bound',
        'promoeng_capped',
        'promoeng_pct_bound'
    )
    GROUP BY 1, 2, 3
),

summary_daily AS (
    SELECT
        a.ride_date,
        'SUMMARY' AS row_type,
        a.discount_segment,
        a.country,
        'Total' AS city_bucket,
        c.country_rides_total,
        ROUND(100.0 * a.rides_total / NULLIF(c.country_rides_total, 0), 2)
            AS ride_share_pct,
        a.rides_total,
        a.gross_shock_rides,
        a.net_shock_rides,
        ROUND(100.0 * a.gross_shock_rides / NULLIF(a.rides_total, 0), 2)
            AS gross_shock_pct,
        ROUND(100.0 * a.net_shock_rides / NULLIF(a.rides_total, 0), 2)
            AS net_shock_pct,
        a.gross_excess_amount,
        a.net_excess_amount,
        a.avg_gross_excess,
        a.avg_net_excess,
        a.avg_d_discount,
        ROUND(
            100.0 * (a.gross_excess_amount - a.net_excess_amount)
                / NULLIF(a.gross_excess_amount, 0),
            2
        ) AS absorption_pct,
        IFF(a.discount_segment = 'cap_bound_total', 1, 0)
            AS cap_bound_at_quote,
        a.promised_not_applied_rides,
        a.currency
    FROM summary_agg a
    JOIN country_daily c
        ON c.ride_date = a.ride_date
       AND c.country = a.country
),

promised_daily AS (
    SELECT
        f.ride_date,
        'SUMMARY' AS row_type,
        'promised_not_applied' AS discount_segment,
        f.country,
        'Total' AS city_bucket,
        COUNT(*) AS country_rides_total,
        ROUND(100.0 * SUM(f.promised_not_applied) / NULLIF(COUNT(*), 0), 2)
            AS ride_share_pct,
        COUNT(*) AS rides_total,
        CAST(NULL AS NUMBER) AS gross_shock_rides,
        SUM(f.promised_not_applied) AS net_shock_rides,
        CAST(NULL AS NUMBER(12, 2)) AS gross_shock_pct,
        ROUND(100.0 * SUM(f.promised_not_applied) / NULLIF(COUNT(*), 0), 2)
            AS net_shock_pct,
        CAST(NULL AS NUMBER(18, 2)) AS gross_excess_amount,
        CAST(NULL AS NUMBER(18, 2)) AS net_excess_amount,
        CAST(NULL AS NUMBER(18, 2)) AS avg_gross_excess,
        CAST(NULL AS NUMBER(18, 2)) AS avg_net_excess,
        CAST(NULL AS NUMBER(18, 3)) AS avg_d_discount,
        CAST(NULL AS NUMBER(12, 2)) AS absorption_pct,
        0 AS cap_bound_at_quote,
        SUM(f.promised_not_applied) AS promised_not_applied_rides,
        MAX(f.currency) AS currency
    FROM final f
    GROUP BY 1, 2, 3, 4, 5
),

/* Gate 1A: voucher formula and discount-VAT rule, daily by country. */
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
    FROM final f
    WHERE f.voucher_valid = 1
      AND f.n_codes = 1
      AND f.n_values = 1
      AND f.dtype = 'PERCENTAGE'
      AND f.has_promo_engine = 0
      AND f.act_disc_exvat > 0.001
    GROUP BY 1, 2
),

/* Gate 1B: promotion-engine formula and VAT rule, daily by promotion. */
gate1_promo AS (
    SELECT
        d.ride_date,
        d.country,
        d.promotionid,
        COUNT(*) AS n,
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
        )) / NULLIF(COUNT(*), 0), 3) AS vat_match_pct,
        MAX(cfg.pct) AS derived_pct,
        MAX(cfg.cap_exvat) AS derived_cap_exvat,
        MAX(cfg.n_uncapped) AS n_uncapped
    FROM pe_days d
    JOIN pe_raw r
        ON r.promotionid = d.promotionid
       AND r.country = d.country
       AND r.ride_date BETWEEN DATEADD('day', -6, d.ride_date) AND d.ride_date
    LEFT JOIN pe_cfg_daily cfg
        ON cfg.ride_date = d.ride_date
       AND cfg.promotionid = d.promotionid
       AND cfg.country = d.country
    GROUP BY 1, 2, 3
),

/* Gate 2: net_fare_diff = fare_diff + d_discount. */
gate2_identity AS (
    SELECT
        f.ride_date,
        f.country,
        COUNT(*) AS n,
        SUM(IFF(
            ABS(f.net_fare_diff - (f.fare_diff + f.d_discount)) <= 0.011,
            1, 0
        )) AS identity_holds
    FROM final f
    GROUP BY 1, 2
),

gate2_identity_rate AS (
    SELECT
        i.*,
        ROUND(i.identity_holds / NULLIF(i.n, 0), 6) AS identity_ratio
    FROM gate2_identity i
),

/* Gate 3: each promotion seen today must have >=50 uncapped observations. */
gate3_config AS (
    SELECT
        f.ride_date,
        f.country,
        f.promotionid,
        COUNT(*) AS rides_today,
        MAX(f.pe_pct) AS derived_pct,
        MAX(f.pe_cap_exvat) AS derived_cap_exvat,
        MAX(f.pe_n_uncapped) AS n_uncapped
    FROM final f
    WHERE f.has_promo_engine = 1
    GROUP BY 1, 2, 3
),

/* Additional exact reconciliation: the recomputed gross population must
   equal the existing PriceShocks country Total numerator and denominator. */
gross_daily AS (
    SELECT
        f.ride_date,
        f.country,
        COUNT(*) AS rides_total,
        SUM(IFF(
            f.fare_diff > 0.01 AND f.is_spillover_recovery = 0,
            1, 0
        )) AS gross_shock_rides
    FROM final f
    GROUP BY 1, 2
),

gate_reconciliation AS (
    SELECT
        g.ride_date,
        g.country,
        g.rides_total,
        g.gross_shock_rides,
        ps.rides_denom AS ps_rides_total,
        ps.rides_flagged AS ps_gross_shock_rides,
        ROUND(
            100.0 * g.gross_shock_rides / NULLIF(g.rides_total, 0),
            2
        ) AS recomputed_gross_pct,
        ps.pct AS priceshocks_gross_pct
    FROM gross_daily g
    LEFT JOIN JEENY_PROD.RIDE.PRICESHOCKS ps
        ON ps.ride_date = g.ride_date
       AND ps.country = g.country
       AND ps.city_bucket = 'Total'
       AND ps.metric_family = 'CHANNEL'
       AND ps.metric_name = 'cumulative_price_shocks_net'
),

/* §7.2 direction invariants. No invented approximation threshold is applied
   to capped avg d_discount; its value remains visible in the segment output. */
gate_segment_direction AS (
    SELECT
        s.*,
        CASE
            WHEN s.discount_segment IN (
                'voucher_capped', 'promoeng_capped'
            )
                THEN s.net_shock_pct - s.gross_shock_pct
            ELSE -s.avg_d_discount
        END AS direction_value,
        CASE
            WHEN s.discount_segment IN (
                'voucher_capped', 'promoeng_capped'
            )
                THEN IFF(s.net_shock_pct >= s.gross_shock_pct, 'PASS', 'FAIL')
            ELSE IFF(s.avg_d_discount < 0, 'PASS', 'FAIL')
        END AS direction_status
    FROM segment_daily s
    WHERE s.discount_segment IN (
        'voucher_capped',
        'voucher_pct_bound',
        'promoeng_capped',
        'promoeng_pct_bound'
    )
),

gate_rows AS (
    SELECT
        v.ride_date,
        'GATE' AS row_type,
        'gate1_voucher_applied_formula' AS discount_segment,
        v.country,
        'Total' AS city_bucket,
        CAST(NULL AS NUMBER) AS country_rides_total,
        CAST(NULL AS NUMBER(12, 2)) AS ride_share_pct,
        v.n AS rides_total,
        CAST(NULL AS NUMBER) AS gross_shock_rides,
        CAST(NULL AS NUMBER) AS net_shock_rides,
        v.formula_match_pct AS gross_shock_pct,
        v.vat_match_pct AS net_shock_pct,
        CAST(NULL AS NUMBER(18, 2)) AS gross_excess_amount,
        CAST(NULL AS NUMBER(18, 2)) AS net_excess_amount,
        CAST(NULL AS NUMBER(18, 2)) AS avg_gross_excess,
        CAST(NULL AS NUMBER(18, 2)) AS avg_net_excess,
        CAST(NULL AS NUMBER(18, 3)) AS avg_d_discount,
        CAST(NULL AS NUMBER(12, 2)) AS absorption_pct,
        CAST(NULL AS NUMBER) AS cap_bound_at_quote,
        CAST(NULL AS NUMBER) AS promised_not_applied_rides,
        IFF(v.country = 'SA', 'SAR', 'JOD') AS currency,
        CAST(NULL AS VARCHAR) AS promotion_id,
        CAST(NULL AS NUMBER) AS derived_pct,
        CAST(NULL AS NUMBER) AS derived_cap_exvat,
        CAST(NULL AS NUMBER) AS n_uncapped,
        'applied_formula_and_vat' AS gate_name,
        LEAST(v.formula_match_pct, v.vat_match_pct) AS gate_value,
        99.9 AS gate_threshold,
        IFF(
            v.formula_match_pct >= 99.9 AND v.vat_match_pct >= 99.9,
            'PASS', 'FAIL'
        ) AS gate_status
    FROM gate1_voucher v

    UNION ALL

    SELECT
        p.ride_date,
        'GATE',
        'gate1_promo_applied_formula',
        p.country,
        'Total',
        NULL,
        NULL,
        p.n,
        NULL,
        NULL,
        p.formula_match_pct,
        p.vat_match_pct,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
        IFF(p.country = 'SA', 'SAR', 'JOD'),
        p.promotionid,
        p.derived_pct,
        p.derived_cap_exvat,
        p.n_uncapped,
        'applied_formula_and_vat',
        LEAST(p.formula_match_pct, p.vat_match_pct),
        99.9,
        IFF(
            p.formula_match_pct >= 99.9 AND p.vat_match_pct >= 99.9,
            'PASS', 'FAIL'
        )
    FROM gate1_promo p

    UNION ALL

    SELECT
        i.ride_date,
        'GATE',
        'gate2_net_fare_identity',
        i.country,
        'Total',
        NULL,
        NULL,
        i.n,
        NULL,
        i.identity_holds,
        NULL,
        ROUND(i.identity_ratio * 100, 4),
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
        IFF(i.country = 'SA', 'SAR', 'JOD'),
        NULL, NULL, NULL, NULL,
        'net_fare_diff_identity',
        i.identity_ratio,
        0.9999,
        IFF(i.identity_ratio >= 0.9999, 'PASS', 'FAIL')
    FROM gate2_identity_rate i

    UNION ALL

    SELECT
        c.ride_date,
        'GATE',
        'gate3_promo_config_coverage',
        c.country,
        'Total',
        NULL,
        NULL,
        c.rides_today,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
        IFF(c.country = 'SA', 'SAR', 'JOD'),
        c.promotionid,
        c.derived_pct,
        c.derived_cap_exvat,
        c.n_uncapped,
        'promo_config_uncapped_coverage',
        COALESCE(c.n_uncapped, 0),
        50,
        IFF(
            c.derived_pct IS NOT NULL
            AND c.derived_cap_exvat IS NOT NULL
            AND COALESCE(c.n_uncapped, 0) >= 50,
            'PASS', 'FAIL'
        )
    FROM gate3_config c

    UNION ALL

    SELECT
        r.ride_date,
        'GATE',
        'gate4_priceshocks_reconciliation',
        r.country,
        'Total',
        NULL,
        NULL,
        r.rides_total,
        r.gross_shock_rides,
        r.ps_gross_shock_rides,
        r.recomputed_gross_pct,
        r.priceshocks_gross_pct,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
        IFF(r.country = 'SA', 'SAR', 'JOD'),
        NULL, NULL, NULL, NULL,
        'priceshocks_exact_counts',
        ABS(r.rides_total - r.ps_rides_total)
            + ABS(r.gross_shock_rides - r.ps_gross_shock_rides),
        0,
        IFF(
            r.rides_total = r.ps_rides_total
            AND r.gross_shock_rides = r.ps_gross_shock_rides,
            'PASS', 'FAIL'
        )
    FROM gate_reconciliation r

    UNION ALL

    SELECT
        s.ride_date,
        'GATE',
        'gate5_segment_direction:' || s.discount_segment,
        s.country,
        'Total',
        s.country_rides_total,
        s.ride_share_pct,
        s.rides_total,
        s.gross_shock_rides,
        s.net_shock_rides,
        s.gross_shock_pct,
        s.net_shock_pct,
        NULL,
        NULL,
        s.avg_gross_excess,
        s.avg_net_excess,
        s.avg_d_discount,
        s.absorption_pct,
        s.cap_bound_at_quote,
        s.promised_not_applied_rides,
        s.currency,
        NULL, NULL, NULL, NULL,
        'segment_direction',
        s.direction_value,
        0,
        s.direction_status
    FROM gate_segment_direction s
),

metric_rows AS (
    SELECT
        s.*,
        CAST(NULL AS VARCHAR) AS promotion_id,
        CAST(NULL AS NUMBER) AS derived_pct,
        CAST(NULL AS NUMBER) AS derived_cap_exvat,
        CAST(NULL AS NUMBER) AS n_uncapped,
        CAST(NULL AS VARCHAR) AS gate_name,
        CAST(NULL AS NUMBER) AS gate_value,
        CAST(NULL AS NUMBER) AS gate_threshold,
        CAST(NULL AS VARCHAR) AS gate_status
    FROM segment_daily s

    UNION ALL

    SELECT
        s.*,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM summary_daily s

    UNION ALL

    SELECT
        p.*,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM promised_daily p
)

SELECT
    ride_date,
    row_type,
    discount_segment,
    country,
    city_bucket,
    country_rides_total,
    ride_share_pct,
    rides_total,
    gross_shock_rides,
    net_shock_rides,
    gross_shock_pct,
    net_shock_pct,
    gross_excess_amount,
    net_excess_amount,
    avg_gross_excess,
    avg_net_excess,
    avg_d_discount,
    absorption_pct,
    cap_bound_at_quote,
    promised_not_applied_rides,
    currency,
    promotion_id,
    derived_pct,
    derived_cap_exvat,
    n_uncapped,
    gate_name,
    gate_value,
    gate_threshold,
    gate_status,
    CURRENT_TIMESTAMP() AS computed_at
FROM metric_rows

UNION ALL

SELECT
    ride_date,
    row_type,
    discount_segment,
    country,
    city_bucket,
    country_rides_total,
    ride_share_pct,
    rides_total,
    gross_shock_rides,
    net_shock_rides,
    gross_shock_pct,
    net_shock_pct,
    gross_excess_amount,
    net_excess_amount,
    avg_gross_excess,
    avg_net_excess,
    avg_d_discount,
    absorption_pct,
    cap_bound_at_quote,
    promised_not_applied_rides,
    currency,
    promotion_id,
    derived_pct,
    derived_cap_exvat,
    n_uncapped,
    gate_name,
    gate_value,
    gate_threshold,
    gate_status,
    CURRENT_TIMESTAMP()
FROM gate_rows

ORDER BY ride_date, country, row_type, discount_segment, promotion_id;
