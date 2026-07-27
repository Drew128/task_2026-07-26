{{ config(
    schema='intermediate',
    alias='spend_daily',
    materialized='view'
) }}

-- daily spend unified across channels (USD), mapped to channel + platform.
-- grain: spend_date × campaign_id

WITH meta AS (
    SELECT spend_date, account_id, campaign_id, campaign_name, spend_usd, data_source
    FROM {{ ref('prep__meta_spend') }}
),

google AS (
    SELECT spend_date, account_id, campaign_id, campaign_name, spend_usd, data_source
    FROM {{ ref('prep__google_spend') }}
),

tiktok AS (
    SELECT spend_date, account_id, campaign_id, campaign_name, spend_usd, data_source
    FROM {{ ref('intermediate__tiktok_spend') }}
),

account_channel_map AS (
    SELECT account_id, channel, platform
    FROM {{ ref('account_channel_map') }}
),

spend AS (
    SELECT * FROM meta
    UNION ALL
    SELECT * FROM google
    UNION ALL
    SELECT * FROM tiktok
),

final AS (
    SELECT
        spend.spend_date,
        account_channel_map.channel,
        account_channel_map.platform,
        spend.campaign_id,
        spend.campaign_name,
        spend.spend_usd,
        spend.data_source
    FROM spend
    LEFT JOIN account_channel_map
           ON spend.account_id = account_channel_map.account_id
)

SELECT *
FROM final
