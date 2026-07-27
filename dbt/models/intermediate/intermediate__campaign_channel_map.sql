{{ config(
    schema='intermediate',
    alias='campaign_channel_map',
    materialized='view'
) }}

-- grain: campaign_id

WITH spend AS (
    SELECT
        campaign_id,
        channel,
        platform,
        campaign_name
    FROM {{ ref('intermediate__spend_daily') }}
    WHERE campaign_id IS NOT NULL
    -- one row per campaign; newest name wins if the campaign was renamed
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY campaign_id
        ORDER BY spend_date DESC) = 1
),

final AS (
    SELECT campaign_id, channel, platform, campaign_name
    FROM spend

    UNION ALL
    -- sentinel key '(organic)' to the Organic channel via this same join
    SELECT
        '(organic)'             AS campaign_id,
        'Organic'               AS channel,
        CAST(NULL AS STRING)    AS platform,
        CAST(NULL AS STRING)    AS campaign_name
)

SELECT *
FROM final
