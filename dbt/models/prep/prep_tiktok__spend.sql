{{ config(
    schema='prep_tiktok',
    alias='spend',
    materialized='table'
) }}

-- hourly

WITH tiktok_raw AS (
    SELECT
        *,
        _FILE_NAME AS data_source
    FROM {{ source('raw', 'tiktok_spend_hourly') }}
),

forex AS (
    SELECT rate_date, currency, usd_rate, data_source
    FROM {{ ref('prep_forex__rates') }}
),

latest_load AS (
    SELECT *
    FROM tiktok_raw
    -- keep the latest load per hour + campaign
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY stat_hour_utc, campaign_id
        ORDER BY load_epoch DESC) = 1
),

localized AS (
    SELECT
        DATE(CAST(stat_hour_utc AS TIMESTAMP), '{{ var("report_timezone") }}') AS spend_date,
        account_id,
        CAST(campaign_id AS STRING) AS campaign_id,
        campaign_name,
        currency,
        CAST(spend AS NUMERIC)      AS spend_native,
        data_source
    FROM latest_load
),

converted AS (
    SELECT
        localized.spend_date,
        localized.account_id,
        localized.campaign_id,
        localized.campaign_name,
        CASE
            WHEN localized.currency = 'USD' THEN localized.spend_native
            ELSE localized.spend_native * forex.usd_rate
        END AS spend_usd,
        -- lineage from both sources, concatenated with |
        localized.data_source || COALESCE('|' || forex.data_source, '') AS data_source
    FROM localized
    LEFT JOIN forex
        ON forex.currency  = localized.currency
       AND forex.rate_date = localized.spend_date
),

final AS (
    SELECT
        spend_date,
        account_id,
        campaign_id,
        MAX(campaign_name)  AS campaign_name,
        SUM(spend_usd)      AS spend_usd,
        MAX(data_source)    AS data_source
    FROM converted
    GROUP BY spend_date, account_id, campaign_id
)

SELECT *
FROM final
