{{ config(
    schema='prep_meta',
    alias='spend',
    materialized='table'
) }}

-- daily

WITH meta_raw AS (
    SELECT
        *,
        _FILE_NAME AS data_source
    FROM {{ source('raw', 'meta_spend_export') }}
),

meta_flat AS (
    SELECT
        CAST(`date` AS DATE)                AS spend_date,     -- account tz (NY)
        account_id,
        campaign.id                         AS campaign_id,
        campaign.name                       AS campaign_name,
        CAST(metrics.spend_usd AS NUMERIC)  AS spend_usd,      -- already USD
        TIMESTAMP(export_ts)                AS exported_at,
        data_source
    FROM meta_raw
),

final AS (
    SELECT *
    FROM meta_flat
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY spend_date, campaign_id
            ORDER BY exported_at DESC) = 1  -- newest export per (day, campaign)
)

SELECT *
FROM final
