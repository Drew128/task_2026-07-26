{{ config(
    schema='prep',
    alias='google_spend',
    materialized='view'
) }}

-- daily

WITH google_raw AS (
    SELECT
        *,
        _FILE_NAME AS data_source
    FROM {{ source('raw', 'google_ads_spend') }}
),

latest_load AS (
    SELECT *
    FROM google_raw
    -- keep the latest load per day + campaign
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY `date`, campaign_id
        ORDER BY load_epoch DESC) = 1
),

final AS (
    SELECT
        CAST(`date` AS DATE)                    AS spend_date,
        CAST(customer_id AS STRING)             AS account_id,
        CAST(campaign_id AS STRING)             AS campaign_id,
        campaign_name,
        CAST(cost_micros AS NUMERIC) / 1000000  AS spend_usd,
        data_source
    FROM latest_load
)

SELECT *
FROM final
