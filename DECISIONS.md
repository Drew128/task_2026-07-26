# DECISIONS

**stack:** dbt Cloud (Core, "Latest"), BigQuery, GCS

**reporting conventions:** `America/New_York`, USD.

## layers

- **raw** (sources unchanged)
  - GCS hive partitioning → external tables defined in dbt sources
    (`dbt-external-tables`, `stage_external_sources`)
  - hive prefix scoped per source to `.../v=1/` → only `load_date` +
    `load_epoch` are partition columns (bucket-root prefix mis-infers key order)
  - test: **freshness** — daily feeds → yesterday (1d/2d); hourly & realtime
    (tiktok, events, billing) → previous hour (1h/2h)

- **prep** (one model per source · view · own dataset `prep_<source>.<feed>`)
  - named `prep` (not `stage`) to avoid ambiguity with the staging/`stage` environment
  - meta: flatten nested JSON, dedup restatements by newest `export_ts`
  - tiktok: hourly → daily, UTC→NY date; kept in native currency (FX conversion deferred to intermediate)
  - google: `cost_micros / 1e6`
  - events: strip campaign_id platform prefix (organic→NULL), UTC→NY date
  - billing: UTC→NY date
  - fx / platform: typed pass-through
  - conventions: source CTEs on top → transforms → `final`; UPPERCASE keywords;
    `_FILE_NAME AS data_source` for lineage

- **config-driven mapping** — `account_id → channel (+ platform)` lives in a
  seed (`account_channel_map`, in the `dictionary` dataset). Adding a new ad
  account = add a row; **no model or DB change**. Because it is hand-maintained,
  it carries tests (`account_id` unique/not_null, `platform` accepted_values).
  - *Alternative*: instead of a seed, back the mapping with an **external table
    over a Google Sheet**, where the sheet is filled directly or via **Google
    Forms**. That adds input-side simplification and validation (dropdowns,
    checklists, required fields) so non-engineers can onboard accounts safely,
    while dbt still consumes it as a source.

## data quirks (found in the sources)

- **Meta restatements** — same `(date, campaign)` re-pulled with a newer
  `export_ts`; dedup keeps the newest export.
- **`campaign_id` ↔ `campaign_name` not 1:1** — Meta campaign `23851204001` was
  renamed (`..._Broad` → `..._Broad_v2`). Name is treated as a per-date
  attribute (kept in a dimension, not the fact key), so a rename never splits
  or double-counts spend.
- **`event_id` not globally unique** — 680 exact-duplicate event rows; dedup by
  `event_id` (newest `received_at_utc`) collapses them.
- **attribution `campaign_id` dirty** — mixed `meta_`/`tiktok_`/`google_` prefixes
  (most bare), plus trailing whitespace (`"23851204001 "`, 1550 rows) and float
  artifacts (`"1790223344.0"`, 2218 rows). Normalized in prep: TRIM → strip
  prefix → drop trailing `.0`. Without this, ~11% of events wouldn't join to
  spend and spend/conversions would split across mismatched campaign ids.
- **Google export missing 2 days** (`2026-04-21`, `2026-04-22`, ≈ $353) — a gap
  in the raw feed, not a modelling bug; surfaced in `RECONCILIATION.md`.

## revenue & cohort ROAS

- **implemented — event-date** (`revenue_daily`): revenue booked on the
  transaction date, credited to the first-touch campaign. This is what the
  mart's `net_revenue` / `ROAS` use. It is a daily P&L view — per-day ROAS mixes
  cohorts (revenue on day D includes users acquired long ago), so it is not a
  clean efficiency of that day's spend.

- **not implemented, but the correct acquisition metric — cohort D0/D7/D30
  ROAS**. Anchor revenue to the install date and, for each window N, compute
  `ROAS_dN = net revenue from a cohort within N days of install ÷ spend that
  acquired that cohort`. Numerator and denominator must be **commensurate**:
  1. **only closed/mature cohorts** — include a cohort only if the full N-day
     window has elapsed by the as-of date (`install_date + N ≤ as_of`).
     Recent cohorts are excluded; otherwise their right-censored revenue is
     divided by full spend and ROAS_dN is understated.
  2. **same cohorts on both sides** — the denominator is the spend of exactly
     those mature cohorts, and the numerator is only revenue from users within
     their N-day window. Never mix full spend with truncated revenue.

  Parked for the take-home (the event-date mart is the deliverable). The
  building blocks are already in place: `first_touch` gives each user's install
  date, so `days_since_install` and a dynamic `as_of` (max billing date) are all
  that's needed to add it.

## ideas parked for later

- **hourly TikTok report** — `prep__tiktok_spend` is kept at the source's hourly
  grain, and attribution + billing are event/transaction-level (near real-time),
  so we could build an intraday/hourly acquisition report for TikTok. Parked for
  now; the daily mart is the deliverable.

## out of scope

- materialization: everything is a **view** for now; in production the layers
  would need tables + incremental models depending on data volume and the
  load/refresh cadence
- dev/prod environment separation
- orchestration tags/selectors (refresh only what changed)

## open

- prep dedup: prefer an in-data field over `load_epoch` where one exists

## build from scratch

```bash
# 1. upload data/ to GCS in the hive layout (see raw sources)
# 2. set gcp_project / raw_bucket in dbt_project.yml vars (or override via --vars)
dbt deps
dbt run-operation stage_external_sources   # create raw external tables
dbt source freshness                       # validate raw freshness before building
dbt build                                  # seed + build models + run tests
```
