-- Reconciliation gate: fail if any platform-day is off from the platform UI
-- ground truth by more than 0.5%. Currently fails on Google 2026-04-21/22,
-- where the Google export is missing those two days (~$353) — a real gap in the
-- raw feed, explained in RECONCILIATION.md.

SELECT
    spend_date,
    platform,
    spend_ours,
    spend_truth,
    diff,
    diff_pct
FROM {{ ref('intermediate__spend_reconciliation') }}
WHERE diff_pct > 0.005
