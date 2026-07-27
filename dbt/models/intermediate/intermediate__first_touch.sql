{{ config(
    schema='intermediate',
    alias='first_touch',
    materialized='view'
) }}

-- first-touch attribution: each user's earliest install → campaign + platform.
-- grain: one row per user_id

WITH installs AS (
    SELECT
        *
    FROM {{ ref('prep__attribution_events') }}
    WHERE event_type = 'install'
),

final AS (
    SELECT
        user_id,
        campaign_id    AS first_touch_campaign_id,
        platform       AS first_touch_platform,
        event_at_utc   AS first_install_at_utc,
        event_at_local AS first_install_at_local,
        data_source
    FROM installs
    -- earliest install per user wins (first touch); event_id breaks ties
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY user_id
        ORDER BY event_at_utc, event_id) = 1
)

SELECT *
FROM final
