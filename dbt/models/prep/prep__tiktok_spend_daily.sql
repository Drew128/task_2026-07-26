{{ config(
    schema='prep',
    alias='tiktok_spend_daily',
    materialized='view'
) }}

-- daily (rollup of the hourly model)

WITH tiktok_hourly AS (
    SELECT *
    FROM {{ ref('prep__tiktok_spend') }}
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
