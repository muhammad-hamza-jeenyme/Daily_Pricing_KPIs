-- =============================================================================
-- Daily digest FROM BI table JEENY_PROD.RIDE.PRICESHOCKS (thin consumer)
-- =============================================================================
-- Replaces heavy ride-level channel + canvas SQL for the daily Cloud Agent.
-- BI refreshes PRICESHOCKS before 11:00 AM PKT. Agent only:
--   1) freshness check  2) DoD/WoW/MoM joins  3) format Slack/canvas
--
-- Source grain: RIDE_DATE × METRIC_FAMILY × METRIC_NAME × COUNTRY × CITY_BUCKET
-- Families: CHANNEL | SCENARIO | CAUSE_MIX
-- Specs: docs/priceshocks-table.md | automations/DAILY_SLACK_INSTRUCTIONS.md
-- =============================================================================

WITH params AS (
    SELECT
        DATEADD('day', -1, CURRENT_DATE()) AS report_date,
        DATEADD('day', -2, CURRENT_DATE()) AS dod_date,
        DATEADD('day', -8, CURRENT_DATE()) AS wow_date,
        DATEADD('day', -29, CURRENT_DATE()) AS mom_date
),

freshness AS (
    SELECT
        MAX(ride_date) AS max_ride_date,
        MAX(computed_at) AS max_computed_at,
        COUNT(*) AS n_rows
    FROM JEENY_PROD.RIDE.PRICESHOCKS
),

/* Fail the run clearly if yesterday is missing (ETL lag). */
guard AS (
    SELECT
        f.max_ride_date,
        f.max_computed_at,
        f.n_rows,
        p.report_date,
        IFF(f.max_ride_date >= p.report_date, 1, 0) AS is_ready
    FROM freshness f
    CROSS JOIN params p
),

base AS (
    SELECT
        ride_date,
        metric_family,
        metric_name,
        country,
        city_bucket,
        rides_denom,
        rides_flagged,
        pct
    FROM JEENY_PROD.RIDE.PRICESHOCKS
    CROSS JOIN params p
    WHERE ride_date IN (p.report_date, p.dod_date, p.wow_date, p.mom_date)
),

/* ---------- CHANNEL + SCENARIO: report day with DoD/WoW/MoM pp deltas ---------- */
channel_scenario AS (
    SELECT
        'digest' AS output_kind,
        y.metric_family,
        y.metric_name,
        y.country,
        y.city_bucket,
        y.rides_denom,
        y.rides_flagged,
        y.pct AS pct,
        ROUND(y.pct - d.pct, 2) AS dod_pp,
        ROUND(y.pct - w.pct, 2) AS wow_pp,
        ROUND(y.pct - m.pct, 2) AS mom_pp,
        g.is_ready,
        g.max_ride_date,
        g.max_computed_at
    FROM base y
    CROSS JOIN params p
    CROSS JOIN guard g
    LEFT JOIN base d
        ON d.ride_date = p.dod_date
       AND d.metric_family = y.metric_family
       AND d.metric_name = y.metric_name
       AND d.country = y.country
       AND d.city_bucket = y.city_bucket
    LEFT JOIN base w
        ON w.ride_date = p.wow_date
       AND w.metric_family = y.metric_family
       AND w.metric_name = y.metric_name
       AND w.country = y.country
       AND w.city_bucket = y.city_bucket
    LEFT JOIN base m
        ON m.ride_date = p.mom_date
       AND m.metric_family = y.metric_family
       AND m.metric_name = y.metric_name
       AND m.country = y.country
       AND m.city_bucket = y.city_bucket
    WHERE y.ride_date = p.report_date
      AND y.metric_family IN ('CHANNEL', 'SCENARIO')
),

/* ---------- CAUSE_MIX: report day only (already ~100% exclusive) ---------- */
cause_mix AS (
    SELECT
        'digest' AS output_kind,
        y.metric_family,
        y.metric_name,
        y.country,
        y.city_bucket,
        y.rides_denom,
        y.rides_flagged,
        y.pct AS pct,
        CAST(NULL AS FLOAT) AS dod_pp,
        CAST(NULL AS FLOAT) AS wow_pp,
        CAST(NULL AS FLOAT) AS mom_pp,
        g.is_ready,
        g.max_ride_date,
        g.max_computed_at
    FROM base y
    CROSS JOIN params p
    CROSS JOIN guard g
    WHERE y.ride_date = p.report_date
      AND y.metric_family = 'CAUSE_MIX'
),

/* Always return a readiness row so agent can fail cleanly if empty digest. */
status_row AS (
    SELECT
        'status' AS output_kind,
        CAST(NULL AS VARCHAR) AS metric_family,
        CAST(NULL AS VARCHAR) AS metric_name,
        CAST(NULL AS VARCHAR) AS country,
        CAST(NULL AS VARCHAR) AS city_bucket,
        g.n_rows AS rides_denom,
        CAST(NULL AS NUMBER) AS rides_flagged,
        CAST(NULL AS FLOAT) AS pct,
        CAST(NULL AS FLOAT) AS dod_pp,
        CAST(NULL AS FLOAT) AS wow_pp,
        CAST(NULL AS FLOAT) AS mom_pp,
        g.is_ready,
        g.max_ride_date,
        g.max_computed_at
    FROM guard g
)

SELECT * FROM status_row
UNION ALL
SELECT * FROM channel_scenario
UNION ALL
SELECT * FROM cause_mix
ORDER BY
    output_kind DESC,
    metric_family,
    country,
    metric_name,
    CASE city_bucket
        WHEN 'RUH' THEN 1 WHEN 'JED' THEN 2 WHEN 'MAD' THEN 3
        WHEN 'DMM' THEN 4 WHEN 'MEC' THEN 5
        WHEN 'AMM' THEN 1 WHEN 'IRB' THEN 2 WHEN 'ZRQ' THEN 3
        WHEN 'Others' THEN 90 WHEN 'Total' THEN 99
        ELSE 50
    END;
