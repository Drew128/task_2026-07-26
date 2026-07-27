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
    SELECT *
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
        CAST(stat_hour_utc AS TIMESTAMP) AS stat_hour_utc,
        DATETIME(CAST(stat_hour_utc AS TIMESTAMP), '{{ var("report_timezone") }}') AS stat_hour_local,
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
        localized.stat_hour_utc,
        localized.stat_hour_local,
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
        stat_hour_utc,
        stat_hour_local,
        spend_date,
        account_id,
        campaign_id,
        campaign_name,
        spend_usd,
        data_source
    FROM converted
)

SELECT *
FROM final
