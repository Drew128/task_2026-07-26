{{ config(
    schema='intermediate',
    alias='campaign_channel_map',
    materialized='view'
) }}

-- grain: campaign_id

WITH spend AS (
    SELECT DISTINCT
        campaign_id,
        channel,
        platform
    FROM {{ ref('intermediate__spend_daily') }}
    WHERE campaign_id IS NOT NULL
)

SELECT *
FROM spend
