{{ config(
    schema='intermediate',
    alias='spend_reconciliation',
    materialized='view'
) }}

-- Reconcile modelled spend against the platform UI ground truth.
-- grain: spend_date × platform. Target: |diff| / truth ≤ 0.5% per platform-day.

WITH ours AS (
    SELECT
        spend_date,
        platform,
        SUM(spend_usd) AS spend_ours
    FROM {{ ref('intermediate__spend_daily') }}
    GROUP BY spend_date, platform
),

truth AS (
    SELECT
        spend_date,
        platform,
        spend_usd AS spend_truth
    FROM {{ ref('prep__platform_totals') }}
),

final AS (
    SELECT
        COALESCE(ours.spend_date, truth.spend_date) AS spend_date,
        COALESCE(ours.platform,   truth.platform)   AS platform,
        COALESCE(ours.spend_ours,  0)               AS spend_ours,
        COALESCE(truth.spend_truth, 0)              AS spend_truth,
        COALESCE(ours.spend_ours, 0) - COALESCE(truth.spend_truth, 0)
                                                    AS diff,
        SAFE_DIVIDE(
            ABS(COALESCE(ours.spend_ours, 0) - COALESCE(truth.spend_truth, 0)),
            NULLIF(truth.spend_truth, 0)
        )                                           AS diff_pct
    FROM ours
    FULL OUTER JOIN truth
                 ON ours.spend_date = truth.spend_date
                AND ours.platform   = truth.platform
)

SELECT *
FROM final
