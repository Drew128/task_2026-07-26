{{ config(
    schema='prep',
    alias='tiktok_spend',
    materialized='view'
) }}

-- hourly

WITH tiktok_raw AS (
    SELECT
        *,
        _FILE_NAME AS data_source
    FROM {{ source('raw', 'tiktok_spend_hourly') }}
),

latest_load AS (
    SELECT *
    FROM tiktok_raw
    -- keep the latest load per hour + campaign
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY stat_hour_utc, campaign_id
        ORDER BY load_epoch DESC) = 1
),

final AS (
    SELECT
        CAST(stat_hour_utc AS TIMESTAMP)                         AS stat_hour_utc,
        DATETIME(CAST(stat_hour_utc AS TIMESTAMP), '{{ var("report_timezone") }}')  
                                                                 AS stat_hour_local,
        CAST(account_id AS STRING)                               AS account_id,
        CAST(campaign_id AS STRING)                              AS campaign_id,
        campaign_name,
        currency,
        CAST(spend AS NUMERIC)                                   AS spend_native,
        data_source
    FROM latest_load
)

SELECT *
FROM final
