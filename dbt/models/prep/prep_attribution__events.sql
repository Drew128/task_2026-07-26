{{ config(
    schema='prep_attribution',
    alias='events',
    materialized='table'
) }}

-- event-level

WITH events_raw AS (
    SELECT
        *,
        _FILE_NAME AS data_source
    FROM {{ source('raw', 'attribution_events') }}
),

latest_load AS (
    SELECT *
    FROM events_raw
    -- keep the latest load per event
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY event_id
        ORDER BY load_epoch DESC) = 1
),

final AS (
    SELECT
        event_id,
        user_id,
        event_type,
        platform,
        CAST(event_time_utc AS TIMESTAMP)   AS event_time_utc,
        CAST(received_at_utc AS TIMESTAMP)  AS received_at_utc,
        NULLIF(REGEXP_REPLACE(campaign_id, r'^(meta_|tiktok_|google_)', ''), '') AS campaign_id,
        country,
        data_source
    FROM latest_load
)

SELECT *
FROM final
