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

unioned AS (
    SELECT * FROM meta
    UNION ALL
    SELECT * FROM google
    UNION ALL
    SELECT * FROM tiktok
),

final AS (
    SELECT
        unioned.spend_date,
        account_channel_map.channel,
        account_channel_map.platform,
        unioned.campaign_id,
        unioned.campaign_name,
        unioned.spend_usd,
        unioned.data_source
    FROM unioned
    LEFT JOIN account_channel_map
        ON account_channel_map.account_id = unioned.account_id
)

SELECT *
FROM final
