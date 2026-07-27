{{ config(
    schema='mart',
    alias='marketing_performance_daily',
    materialized='view'
) }}

-- grain: date × channel × campaign_id

WITH spend AS (
    SELECT
        spend_date                         AS date,
        campaign_id                        AS campaign_key,
        spend_usd
    FROM {{ ref('intermediate__spend_daily') }}
),

events AS (
    SELECT
        event_date                         AS date,
        COALESCE(campaign_id, '(organic)') AS campaign_key,
        installs,
        trials,
        purchases
    FROM {{ ref('intermediate__events_daily') }}
),

revenue AS (
    SELECT
        transaction_date                   AS date,
        COALESCE(campaign_id, '(organic)') AS campaign_key,
        gross_revenue,
        refund_amount,
        net_revenue
    FROM {{ ref('intermediate__revenue_daily') }}
),

campaign_channel_map AS (
    SELECT *
    FROM {{ ref('intermediate__campaign_channel_map') }}
),

metrics AS (
    SELECT
        date,
        campaign_key,
        COALESCE(spend_usd,      0) AS spend_usd,
        COALESCE(installs,       0) AS installs,
        COALESCE(trials,         0) AS trials,
        COALESCE(purchases,      0) AS purchases,
        COALESCE(gross_revenue,  0) AS gross_revenue,
        COALESCE(refund_amount,  0) AS refund_amount,
        COALESCE(net_revenue,    0) AS net_revenue
    FROM spend
    FULL JOIN events  USING (date, campaign_key)
    FULL JOIN revenue USING (date, campaign_key)
),

final AS (
    SELECT
        metrics.date,
        campaign_channel_map.channel,
        campaign_channel_map.platform,
        NULLIF(metrics.campaign_key, '(organic)') AS campaign_id,
        campaign_channel_map.campaign_name,
        metrics.spend_usd,
        metrics.installs,
        metrics.trials,
        metrics.purchases,
        metrics.gross_revenue,
        metrics.refund_amount,
        metrics.net_revenue,
        SAFE_DIVIDE(metrics.spend_usd,   NULLIF(metrics.purchases, 0)) AS cac,
        SAFE_DIVIDE(metrics.net_revenue, NULLIF(metrics.spend_usd, 0)) AS roas
    FROM metrics
    LEFT JOIN campaign_channel_map
           ON metrics.campaign_key = campaign_channel_map.campaign_id
)

SELECT *
FROM final
