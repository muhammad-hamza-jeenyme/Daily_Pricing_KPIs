-- Thin daily digest over BI pre-agg RIDE.PRICESHOCKS
-- One statement for the 11:00 AM PKT Pulsar job.
-- Does NOT recompute ride-level fare logic.
-- Spec: docs/priceshocks-table.md
--
-- Returns:
--   output_kind=status  → is_ready, max_ride_date, max_computed_at
--   output_kind=digest  → metric_family CHANNEL|SCENARIO|CAUSE_MIX
--     with pct + DoD/WoW/MoM pp deltas (MoM = vs 28 days before)

WITH bounds AS (
    SELECT
        MAX(ride_date)     AS max_ride_date,
        MAX(computed_at)   AS max_computed_at
    FROM RIDE.PRICESHOCKS
),
params AS (
    SELECT
        b.max_ride_date,
        b.max_computed_at,
        DATEADD('day', -1, CURRENT_DATE()) AS expected_report_date,
        IFF(
            b.max_ride_date IS NOT NULL
            AND b.max_ride_date >= DATEADD('day', -1, CURRENT_DATE()),
            1,
            0
        ) AS is_ready,
        /* Report on yesterday when ready; else still emit status only */
        DATEADD('day', -1, CURRENT_DATE()) AS report_date
    FROM bounds b
),
status_row AS (
    SELECT
        'status'              AS output_kind,
        CAST(NULL AS VARCHAR) AS metric_family,
        CAST(NULL AS VARCHAR) AS metric_name,
        CAST(NULL AS VARCHAR) AS country,
        CAST(NULL AS VARCHAR) AS city_bucket,
        CAST(NULL AS FLOAT)   AS pct,
        CAST(NULL AS FLOAT)   AS dod_pp,
        CAST(NULL AS FLOAT)   AS wow_pp,
        CAST(NULL AS FLOAT)   AS mom_pp,
        p.is_ready,
        p.max_ride_date,
        p.max_computed_at
    FROM params p
),
windowed AS (
    SELECT
        ps.ride_date,
        ps.metric_family,
        ps.metric_name,
        ps.country,
        ps.city_bucket,
        ps.pct
    FROM RIDE.PRICESHOCKS ps
    CROSS JOIN params p
    WHERE p.is_ready = 1
      AND ps.ride_date IN (
          p.report_date,
          DATEADD('day', -1,  p.report_date),
          DATEADD('day', -7,  p.report_date),
          DATEADD('day', -28, p.report_date)
      )
),
digest_rows AS (
    SELECT
        'digest' AS output_kind,
        w.metric_family,
        w.metric_name,
        w.country,
        w.city_bucket,
        MAX(IFF(w.ride_date = p.report_date, w.pct, NULL)) AS pct,
        ROUND(
            MAX(IFF(w.ride_date = p.report_date, w.pct, NULL))
          - MAX(IFF(w.ride_date = DATEADD('day', -1,  p.report_date), w.pct, NULL)),
            2
        ) AS dod_pp,
        ROUND(
            MAX(IFF(w.ride_date = p.report_date, w.pct, NULL))
          - MAX(IFF(w.ride_date = DATEADD('day', -7,  p.report_date), w.pct, NULL)),
            2
        ) AS wow_pp,
        ROUND(
            MAX(IFF(w.ride_date = p.report_date, w.pct, NULL))
          - MAX(IFF(w.ride_date = DATEADD('day', -28, p.report_date), w.pct, NULL)),
            2
        ) AS mom_pp,
        CAST(NULL AS NUMBER)           AS is_ready,
        CAST(NULL AS DATE)             AS max_ride_date,
        CAST(NULL AS TIMESTAMP_LTZ)    AS max_computed_at
    FROM windowed w
    CROSS JOIN params p
    GROUP BY
        w.metric_family,
        w.metric_name,
        w.country,
        w.city_bucket
    HAVING MAX(IFF(w.ride_date = p.report_date, w.pct, NULL)) IS NOT NULL
)
SELECT * FROM status_row
UNION ALL
SELECT * FROM digest_rows
ORDER BY
    CASE output_kind WHEN 'status' THEN 0 ELSE 1 END,
    metric_family,
    metric_name,
    country,
    city_bucket
;
