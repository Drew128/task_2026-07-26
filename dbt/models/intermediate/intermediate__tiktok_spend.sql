{{ config(
    schema='intermediate',
    alias='tiktok_spend',
    materialized='view'
) }}

-- TikTok daily spend converted to USD (native currency → USD via daily FX)

WITH tiktok_spend AS (
    SELECT *
    FROM {{ ref('prep__tiktok_spend_daily') }}
),

forex AS (
    SELECT *
    FROM {{ ref('prep__forex_rates') }}
),

final AS (
    SELECT
        tiktok_spend.spend_date,
        tiktok_spend.account_id,
        tiktok_spend.campaign_id,
        tiktok_spend.campaign_name,
        CASE
            WHEN tiktok_spend.currency = '{{ var("reporting_currency") }}'
                THEN tiktok_spend.spend_native
            ELSE tiktok_spend.spend_native * forex.usd_rate
        END AS spend_usd,
        tiktok_spend.data_source || COALESCE('|' || forex.data_source, '') AS data_source
    FROM tiktok_spend
    LEFT JOIN forex
           ON forex.currency  = tiktok_spend.currency
          AND forex.rate_date = tiktok_spend.spend_date
)

SELECT *
FROM final
