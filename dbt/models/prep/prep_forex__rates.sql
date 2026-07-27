{{ config(
    schema='prep_forex',
    alias='rates',
    materialized='table'
) }}

-- daily

WITH forex_raw AS (
    SELECT
        *,
        _FILE_NAME AS data_source
    FROM {{ source('raw', 'forex_rates') }}
),

latest_load AS (
    SELECT *
    FROM forex_raw
    -- keep the latest load per day + currency
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY `date`, currency
        ORDER BY load_epoch DESC) = 1
),

final AS (
    SELECT
        CAST(`date` AS DATE)        AS rate_date,
        currency,
        CAST(usd_rate AS NUMERIC)   AS usd_rate,
        data_source
    FROM latest_load
)

SELECT *
FROM final
