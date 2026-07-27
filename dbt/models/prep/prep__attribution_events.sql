{{ config(
    schema='prep',
    alias='attribution_events',
    materialized='view'
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
        ORDER BY received_at_utc DESC) = 1
),

final AS (
    SELECT
        event_id,
        user_id,
        event_type,
        platform,
        CAST(event_time_utc AS TIMESTAMP)                      AS event_at_utc,
        DATETIME(CAST(event_time_utc AS TIMESTAMP), '{{ var("report_timezone") }}')
                                                               AS event_at_local,
        CAST(received_at_utc AS TIMESTAMP)                     AS received_at_utc,
        NULLIF(                                                  -- organic ('') → NULL
            REGEXP_REPLACE(                                       -- drop float artifact "…​.0"
                REGEXP_REPLACE(                                   -- strip platform prefix
                    TRIM(campaign_id),                           -- trim whitespace
                    r'^(meta_|tiktok_|google_)', ''
                ),
                r'\.0$', ''
            ),
            ''
        )                                                        AS campaign_id,
        country,
        data_source
    FROM latest_load
)

SELECT *
FROM final
