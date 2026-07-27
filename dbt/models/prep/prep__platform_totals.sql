{{ config(
    schema='prep',
    alias='platform_totals',
    materialized='view'
) }}

-- daily

WITH platform_raw AS (
    SELECT
        *,
        _FILE_NAME AS data_source
    FROM {{ source('raw', 'platform_daily_totals') }}
),

latest_load AS (
    SELECT *
    FROM platform_raw
    -- keep the latest load per day + platform
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY `date`, platform
        ORDER BY load_epoch DESC) = 1
),

final AS (
    SELECT
        CAST(`date` AS DATE)        AS spend_date,
        platform,
        CAST(spend_usd AS NUMERIC)  AS spend_usd,
        data_source
    FROM latest_load
)

SELECT *
FROM final
