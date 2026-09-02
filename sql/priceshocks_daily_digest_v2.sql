-- =============================================================================
-- Daily digest v2: existing fare integrity + post-discount exposure
-- =============================================================================
-- Activate only after BI deploys JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS.
-- Existing automation remains on sql/priceshocks_daily_digest.sql until cutover.
-- One Snowflake statement returns status, existing channel/canvas facts,
-- discount exposure, and regression-gate rows.
-- =============================================================================

WITH params AS (
    SELECT
        DATEADD('day', -1, CURRENT_DATE()) AS report_date,
        DATEADD('day', -2, CURRENT_DATE()) AS dod_date,
        DATEADD('day', -8, CURRENT_DATE()) AS wow_date,
        DATEADD('day', -29, CURRENT_DATE()) AS mom_date
),

ps_freshness AS (
    SELECT
        MAX(ride_date) AS max_ride_date,
        MAX(computed_at) AS max_computed_at,
        COUNT(*) AS n_rows
    FROM JEENY_PROD.RIDE.PRICESHOCKS
),

discount_freshness AS (
    SELECT
        MAX(ride_date) AS max_discount_ride_date,
        MAX(computed_at) AS max_discount_computed_at,
        COUNT(*) AS n_discount_rows
    FROM JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS
),

gate_status AS (
    SELECT
        COUNT(*) AS gate_row_count,
        COUNT_IF(d.gate_status = 'FAIL') AS failed_gate_count,
        COUNT_IF(d.discount_segment = 'gate2_net_fare_identity')
            AS identity_gate_count,
        COUNT_IF(d.discount_segment = 'gate4_priceshocks_reconciliation')
            AS reconciliation_gate_count,
        LISTAGG(
            IFF(
                d.gate_status = 'FAIL',
                d.discount_segment
                    || COALESCE(':' || d.promotion_id, ''),
                NULL
            ),
            ', '
        ) WITHIN GROUP (ORDER BY d.discount_segment, d.promotion_id)
            AS failed_gates
    FROM JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS d
    CROSS JOIN params p
    WHERE d.ride_date = p.report_date
      AND d.row_type = 'GATE'
),

guard AS (
    SELECT
        p.report_date,
        pf.max_ride_date,
        pf.max_computed_at,
        pf.n_rows,
        df.max_discount_ride_date,
        df.max_discount_computed_at,
        df.n_discount_rows,
        gs.failed_gate_count,
        IFF(
            gs.identity_gate_count >= 2
            AND gs.reconciliation_gate_count >= 2,
            gs.failed_gates,
            COALESCE(gs.failed_gates || ', ', '')
                || 'missing_required_gate_rows'
        ) AS failed_gates,
        IFF(
            pf.max_ride_date >= p.report_date,
            1, 0
        ) AS is_ready,
        IFF(
            df.max_discount_ride_date >= p.report_date
            AND
            gs.failed_gate_count = 0
            AND gs.identity_gate_count >= 2
            AND gs.reconciliation_gate_count >= 2,
            1, 0
        ) AS discount_is_ready
    FROM params p
    CROSS JOIN ps_freshness pf
    CROSS JOIN discount_freshness df
    CROSS JOIN gate_status gs
),

ps_base AS (
    SELECT
        s.ride_date,
        s.metric_family,
        s.metric_name,
        s.country,
        s.city_bucket,
        s.rides_denom,
        s.rides_flagged,
        s.pct
    FROM JEENY_PROD.RIDE.PRICESHOCKS s
    CROSS JOIN params p
    WHERE s.ride_date IN (
        p.report_date, p.dod_date, p.wow_date, p.mom_date
    )
),

/* Existing fare-integrity figures are intentionally unchanged. */
fare_integrity AS (
    SELECT
        'digest' AS output_kind,
        y.metric_family,
        y.metric_name,
        y.country,
        y.city_bucket,
        y.rides_denom,
        y.rides_flagged,
        y.pct,
        IFF(
            y.metric_family IN ('CHANNEL', 'SCENARIO'),
            ROUND(y.pct - d.pct, 2),
            NULL
        ) AS dod_pp,
        IFF(
            y.metric_family IN ('CHANNEL', 'SCENARIO'),
            ROUND(y.pct - w.pct, 2),
            NULL
        ) AS wow_pp,
        IFF(
            y.metric_family IN ('CHANNEL', 'SCENARIO'),
            ROUND(y.pct - m.pct, 2),
            NULL
        ) AS mom_pp
    FROM ps_base y
    CROSS JOIN params p
    LEFT JOIN ps_base d
        ON d.ride_date = p.dod_date
       AND d.metric_family = y.metric_family
       AND d.metric_name = y.metric_name
       AND d.country = y.country
       AND d.city_bucket = y.city_bucket
    LEFT JOIN ps_base w
        ON w.ride_date = p.wow_date
       AND w.metric_family = y.metric_family
       AND w.metric_name = y.metric_name
       AND w.country = y.country
       AND w.city_bucket = y.city_bucket
    LEFT JOIN ps_base m
        ON m.ride_date = p.mom_date
       AND m.metric_family = y.metric_family
       AND m.metric_name = y.metric_name
       AND m.country = y.country
       AND m.city_bucket = y.city_bucket
    WHERE y.ride_date = p.report_date
),

discount_base AS (
    SELECT d.*
    FROM JEENY_PROD.RIDE.PRICESHOCKDISCOUNTS d
    CROSS JOIN params p
    WHERE d.ride_date IN (
        p.report_date, p.dod_date, p.wow_date, p.mom_date
    )
),

discount_digest AS (
    SELECT
        'discount' AS output_kind,
        'DISCOUNT' AS metric_family,
        y.discount_segment AS metric_name,
        y.country,
        y.city_bucket,
        y.row_type,
        y.country_rides_total,
        y.ride_share_pct,
        ROUND(y.ride_share_pct - d.ride_share_pct, 2) AS ride_share_dod_pp,
        ROUND(y.ride_share_pct - w.ride_share_pct, 2) AS ride_share_wow_pp,
        ROUND(y.ride_share_pct - m.ride_share_pct, 2) AS ride_share_mom_pp,
        y.rides_total,
        y.gross_shock_rides,
        y.net_shock_rides,
        y.gross_shock_pct,
        y.net_shock_pct,
        ROUND(y.net_shock_pct - d.net_shock_pct, 2) AS net_shock_dod_pp,
        ROUND(y.net_shock_pct - w.net_shock_pct, 2) AS net_shock_wow_pp,
        ROUND(y.net_shock_pct - m.net_shock_pct, 2) AS net_shock_mom_pp,
        y.gross_excess_amount,
        y.net_excess_amount,
        y.avg_gross_excess,
        y.avg_net_excess,
        y.avg_d_discount,
        ROUND(y.avg_d_discount - d.avg_d_discount, 3) AS avg_d_discount_dod,
        ROUND(y.avg_d_discount - w.avg_d_discount, 3) AS avg_d_discount_wow,
        ROUND(y.avg_d_discount - m.avg_d_discount, 3) AS avg_d_discount_mom,
        y.absorption_pct,
        y.cap_bound_at_quote,
        y.promised_not_applied_rides,
        y.currency
    FROM discount_base y
    CROSS JOIN params p
    LEFT JOIN discount_base d
        ON d.ride_date = p.dod_date
       AND d.row_type = y.row_type
       AND d.discount_segment = y.discount_segment
       AND d.country = y.country
    LEFT JOIN discount_base w
        ON w.ride_date = p.wow_date
       AND w.row_type = y.row_type
       AND w.discount_segment = y.discount_segment
       AND w.country = y.country
    LEFT JOIN discount_base m
        ON m.ride_date = p.mom_date
       AND m.row_type = y.row_type
       AND m.discount_segment = y.discount_segment
       AND m.country = y.country
    WHERE y.ride_date = p.report_date
      AND y.row_type IN ('SEGMENT', 'SUMMARY')
),

regression_gates AS (
    SELECT
        'gate' AS output_kind,
        'REGRESSION' AS metric_family,
        d.discount_segment AS metric_name,
        d.country,
        d.city_bucket,
        d.promotion_id,
        d.derived_pct,
        d.derived_cap_exvat,
        d.n_uncapped,
        d.gate_name,
        d.gate_value,
        d.gate_threshold,
        d.gate_status,
        d.gross_shock_pct AS formula_match_pct,
        d.net_shock_pct AS vat_match_pct
    FROM discount_base d
    CROSS JOIN params p
    WHERE d.ride_date = p.report_date
      AND d.row_type = 'GATE'
),

status_row AS (
    SELECT
        'status' AS output_kind,
        g.is_ready,
        g.report_date,
        g.max_ride_date,
        g.max_computed_at,
        g.max_discount_ride_date,
        g.max_discount_computed_at,
        g.n_rows,
        g.n_discount_rows,
        g.failed_gate_count,
        g.failed_gates,
        g.discount_is_ready
    FROM guard g
)

/* VARIANT payload keeps one-statement output stable across row families. */
SELECT
    s.output_kind,
    OBJECT_CONSTRUCT_KEEP_NULL(
        'is_ready', s.is_ready,
        'report_date', s.report_date,
        'max_ride_date', s.max_ride_date,
        'max_computed_at', s.max_computed_at,
        'max_discount_ride_date', s.max_discount_ride_date,
        'max_discount_computed_at', s.max_discount_computed_at,
        'price_shock_rows', s.n_rows,
        'discount_rows', s.n_discount_rows,
        'failed_gate_count', s.failed_gate_count,
        'failed_gates', s.failed_gates,
        'discount_is_ready', s.discount_is_ready
    ) AS payload
FROM status_row s

UNION ALL

SELECT
    f.output_kind,
    OBJECT_CONSTRUCT_KEEP_NULL(
        'metric_family', f.metric_family,
        'metric_name', f.metric_name,
        'country', f.country,
        'city_bucket', f.city_bucket,
        'rides_denom', f.rides_denom,
        'rides_flagged', f.rides_flagged,
        'pct', f.pct,
        'dod_pp', f.dod_pp,
        'wow_pp', f.wow_pp,
        'mom_pp', f.mom_pp
    )
FROM fare_integrity f

UNION ALL

SELECT
    d.output_kind,
    OBJECT_CONSTRUCT_KEEP_NULL(
        'metric_family', d.metric_family,
        'metric_name', d.metric_name,
        'country', d.country,
        'city_bucket', d.city_bucket,
        'row_type', d.row_type,
        'country_rides_total', d.country_rides_total,
        'ride_share_pct', d.ride_share_pct,
        'ride_share_dod_pp', d.ride_share_dod_pp,
        'ride_share_wow_pp', d.ride_share_wow_pp,
        'ride_share_mom_pp', d.ride_share_mom_pp,
        'rides_total', d.rides_total,
        'gross_shock_rides', d.gross_shock_rides,
        'net_shock_rides', d.net_shock_rides,
        'gross_shock_pct', d.gross_shock_pct,
        'net_shock_pct', d.net_shock_pct,
        'net_shock_dod_pp', d.net_shock_dod_pp,
        'net_shock_wow_pp', d.net_shock_wow_pp,
        'net_shock_mom_pp', d.net_shock_mom_pp,
        'gross_excess_amount', d.gross_excess_amount,
        'net_excess_amount', d.net_excess_amount,
        'avg_gross_excess', d.avg_gross_excess,
        'avg_net_excess', d.avg_net_excess,
        'avg_d_discount', d.avg_d_discount,
        'avg_d_discount_dod', d.avg_d_discount_dod,
        'avg_d_discount_wow', d.avg_d_discount_wow,
        'avg_d_discount_mom', d.avg_d_discount_mom,
        'absorption_pct', d.absorption_pct,
        'cap_bound_at_quote', d.cap_bound_at_quote,
        'promised_not_applied_rides', d.promised_not_applied_rides,
        'currency', d.currency
    )
FROM discount_digest d
CROSS JOIN guard g
WHERE g.discount_is_ready = 1

UNION ALL

SELECT
    r.output_kind,
    OBJECT_CONSTRUCT_KEEP_NULL(
        'metric_family', r.metric_family,
        'metric_name', r.metric_name,
        'country', r.country,
        'city_bucket', r.city_bucket,
        'promotion_id', r.promotion_id,
        'derived_pct', r.derived_pct,
        'derived_cap_exvat', r.derived_cap_exvat,
        'n_uncapped', r.n_uncapped,
        'gate_name', r.gate_name,
        'gate_value', r.gate_value,
        'gate_threshold', r.gate_threshold,
        'gate_status', r.gate_status,
        'formula_match_pct', r.formula_match_pct,
        'vat_match_pct', r.vat_match_pct
    )
FROM regression_gates r

ORDER BY output_kind DESC, payload:country, payload:metric_family,
         payload:metric_name, payload:city_bucket;
