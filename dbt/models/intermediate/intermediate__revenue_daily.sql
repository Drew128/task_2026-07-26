{{ config(
    schema='intermediate',
    alias='revenue_daily',
    materialized='view'
) }}

-- grain: transaction_date × campaign_id (campaign_id is NULL for organic).
--   gross_revenue  = sum of charges
--   refund_amount  = sum of refund magnitudes
--   net_revenue    = charges + refunds

WITH billing_raw AS (
    SELECT *
    FROM {{ ref('prep__billing_transactions') }}
),

first_touch AS (
    SELECT *
    FROM {{ ref('intermediate__first_touch') }}
),

billing AS (
    SELECT
        DATE(billing_raw.created_at_local)      AS transaction_date,
        first_touch.first_touch_campaign_id     AS campaign_id,
        billing_raw.type,
        billing_raw.amount_usd
    FROM billing_raw
    INNER JOIN first_touch USING (user_id)
),

final AS (
    SELECT
        transaction_date,
        campaign_id,
        SUM(IF(type = 'charge', amount_usd, 0))  AS gross_revenue,
        SUM(IF(type = 'refund', -amount_usd, 0)) AS refund_amount,
        SUM(amount_usd)                          AS net_revenue
    FROM billing
    GROUP BY transaction_date, campaign_id
)

SELECT *
FROM final
