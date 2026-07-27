{{ config(
    schema='prep_tiktok',
    alias='spend_daily',
    materialized='view'
) }}

-- daily (rollup of the hourly model)

WITH tiktok_hourly AS (
    SELECT *
    FROM {{ ref('prep_tiktok__spend') }}
),

final AS (
    SELECT
        DATE(stat_hour_local)   AS spend_date,
        account_id,
        campaign_id,
        MAX(campaign_name)      AS campaign_name,
        currency,
        SUM(spend_native)       AS spend_native,
        MAX(data_source)        AS data_source
    FROM tiktok_hourly
    GROUP BY spend_date, account_id, campaign_id, currency
)

SELECT *
FROM final
