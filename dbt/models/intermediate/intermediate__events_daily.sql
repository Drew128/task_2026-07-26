{{ config(
    schema='intermediate',
    alias='events_daily',
    materialized='view'
) }}

-- installs / trials / purchases per (date, campaign), all credited to the
-- user's first-touch campaign. grain: event_date × campaign_id
-- (campaign_id is NULL for organic).

WITH 
first_touch AS (
    SELECT *
    FROM {{ ref('intermediate__first_touch') }}
),

events AS (
    SELECT *
    FROM {{ ref('prep__attribution_events') }}
),

metrics AS (
    -- installs: the first-touch install itself (one per user), on its date
    SELECT
        DATE(first_install_at_local) AS event_date,
        first_touch_campaign_id      AS campaign_id,
        'install'                    AS metric
    FROM first_touch

    UNION ALL

    -- trials + purchases: credited to the user's first-touch campaign
    SELECT
        DATE(events.event_at_local)             AS event_date,
        first_touch.first_touch_campaign_id     AS campaign_id,
        events.event_type                       AS metric
    FROM events
    INNER JOIN first_touch USING (user_id)
    WHERE events.event_type IN ('trial_start', 'purchase')
),

final AS (
    SELECT
        event_date,
        campaign_id,
        COUNTIF(metric = 'install')     AS installs,
        COUNTIF(metric = 'trial_start') AS trials,
        COUNTIF(metric = 'purchase')    AS purchases
    FROM metrics
    GROUP BY event_date, campaign_id
)

SELECT *
FROM final
