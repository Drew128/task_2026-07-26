{{ config(
    schema='prep_billing',
    alias='transactions',
    materialized='table'
) }}

-- transaction-level

WITH billing_raw AS (
    SELECT
        *,
        _FILE_NAME AS data_source
    FROM {{ source('raw', 'billing_transactions') }}
),

latest_load AS (
    SELECT *
    FROM billing_raw
    -- keep the latest load per transaction
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY transaction_id
        ORDER BY load_epoch DESC) = 1
),

final AS (
    SELECT
        transaction_id,
        user_id,
        type,
        CAST(amount_usd AS NUMERIC)         AS amount_usd,
        CAST(created_at_utc AS TIMESTAMP)   AS created_at_utc,
        DATETIME(CAST(created_at_utc AS TIMESTAMP), '{{ var("report_timezone") }}')  
                                            AS created_at_local,
        original_transaction_id,
        data_source
    FROM latest_load
)

SELECT *
FROM final
