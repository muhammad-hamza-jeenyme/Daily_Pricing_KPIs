-- =============================================================================
-- Daily digest v2: fare integrity + post-discount exposure from PRICESHOCKS
-- =============================================================================
-- Activate only after BI MERGEs DISCOUNT + GATE rows into
-- JEENY_PROD.RIDE.PRICESHOCKS (see sql/bi_priceshocks_discount_extension.sql).
-- Existing automation remains on sql/priceshocks_daily_digest.sql until cutover.
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
        COUNT(*) AS n_rows,
        COUNT_IF(metric_family = 'DISCOUNT') AS n_discount_rows,
        MAX(IFF(metric_family = 'DISCOUNT', ride_date, NULL))
            AS max_discount_ride_date
    FROM JEENY_PROD.RIDE.PRICESHOCKS
),

gate_status AS (
    SELECT
        COUNT(*) AS gate_row_count,
        COUNT_IF(g.rides_flagged = 0) AS failed_gate_count,
        COUNT_IF(g.metric_name = 'gate2_net_fare_identity')
            AS identity_gate_count,
        COUNT_IF(g.metric_name = 'gate4_priceshocks_reconciliation')
            AS reconciliation_gate_count,
        LISTAGG(
            IFF(g.rides_flagged = 0, g.metric_name, NULL),
            ', '
        ) WITHIN GROUP (ORDER BY g.metric_name) AS failed_gates
    FROM JEENY_PROD.RIDE.PRICESHOCKS g
    CROSS JOIN params p
    WHERE g.ride_date = p.report_date
      AND g.metric_family = 'GATE'
),

guard AS (
    SELECT
        p.report_date,
        pf.max_ride_date,
        pf.max_computed_at,
        pf.n_rows,
        pf.max_discount_ride_date,
        pf.n_discount_rows,
        gs.failed_gate_count,
        IFF(
            gs.identity_gate_count >= 2
            AND gs.reconciliation_gate_count >= 2,
            gs.failed_gates,
            COALESCE(gs.failed_gates || ', ', '')
                || 'missing_required_gate_rows'
        ) AS failed_gates,
        IFF(pf.max_ride_date >= p.report_date, 1, 0) AS is_ready,
        IFF(
            pf.max_discount_ride_date >= p.report_date
            AND gs.failed_gate_count = 0
            AND gs.identity_gate_count >= 2
            AND gs.reconciliation_gate_count >= 2,
            1, 0
        ) AS discount_is_ready
    FROM params p
    CROSS JOIN ps_freshness pf
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
        s.pct,
        s.amount_value,
        s.avg_value
    FROM JEENY_PROD.RIDE.PRICESHOCKS s
    CROSS JOIN params p
    WHERE s.ride_date IN (
        p.report_date, p.dod_date, p.wow_date, p.mom_date
    )
),

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
      AND y.metric_family IN ('CHANNEL', 'SCENARIO', 'CAUSE_MIX')
),

discount_digest AS (
    SELECT
        'discount' AS output_kind,
        y.metric_family,
        y.metric_name,
        y.country,
        y.city_bucket,
        y.rides_denom,
        y.rides_flagged,
        y.pct,
        ROUND(y.pct - d.pct, 2) AS dod_pp,
        ROUND(y.pct - w.pct, 2) AS wow_pp,
        ROUND(y.pct - m.pct, 2) AS mom_pp,
        y.amount_value,
        ROUND(y.amount_value - d.amount_value, 2) AS amount_dod,
        y.avg_value,
        ROUND(y.avg_value - d.avg_value, 3) AS avg_dod
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
      AND y.metric_family = 'DISCOUNT'
),

regression_gates AS (
    SELECT
        'gate' AS output_kind,
        y.metric_family,
        y.metric_name,
        y.country,
        y.city_bucket,
        y.rides_denom,
        y.rides_flagged,
        y.pct,
        y.amount_value,
        y.avg_value,
        IFF(y.rides_flagged = 1, 'PASS', 'FAIL') AS gate_status
    FROM ps_base y
    CROSS JOIN params p
    WHERE y.ride_date = p.report_date
      AND y.metric_family = 'GATE'
),

status_row AS (
    SELECT
        'status' AS output_kind,
        g.is_ready,
        g.report_date,
        g.max_ride_date,
        g.max_computed_at,
        g.max_discount_ride_date,
        g.n_rows,
        g.n_discount_rows,
        g.failed_gate_count,
        g.failed_gates,
        g.discount_is_ready
    FROM guard g
)

SELECT
    s.output_kind,
    OBJECT_CONSTRUCT_KEEP_NULL(
        'is_ready', s.is_ready,
        'report_date', s.report_date,
        'max_ride_date', s.max_ride_date,
        'max_computed_at', s.max_computed_at,
        'max_discount_ride_date', s.max_discount_ride_date,
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
        'rides_denom', d.rides_denom,
        'rides_flagged', d.rides_flagged,
        'pct', d.pct,
        'dod_pp', d.dod_pp,
        'wow_pp', d.wow_pp,
        'mom_pp', d.mom_pp,
        'amount_value', d.amount_value,
        'amount_dod', d.amount_dod,
        'avg_value', d.avg_value,
        'avg_dod', d.avg_dod
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
        'rides_denom', r.rides_denom,
        'rides_flagged', r.rides_flagged,
        'pct', r.pct,
        'amount_value', r.amount_value,
        'avg_value', r.avg_value,
        'gate_status', r.gate_status
    )
FROM regression_gates r

ORDER BY output_kind DESC, payload:country, payload:metric_family,
         payload:metric_name, payload:city_bucket;
