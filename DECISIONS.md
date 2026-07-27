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
  renamed (`..._Broad` → `..._Broad_v2`). We decided to keep only the newest 
  name (`ORDER BY spend_date DESC`) as a single mapping per ID. It is unknown 
  if stakeholders prefer to see renames as separate reporting rows; if they do, 
  a different approach (e.g., treating name changes as new entities or SCD2) would be needed.
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

- **semantic layer** — add a semantic layer (e.g. dbt Semantic Layer / MetricFlow)
  over the intermediate models, or promote them into the mart, so metrics
  (CAC, ROAS, installs, net revenue) are defined once and served consistently.
  This lets BI tools and LLM agents that consume a semantic layer query
  governed, self-describing metrics instead of re-deriving them from raw SQL.

- **hourly TikTok report** — `prep__tiktok_spend` is kept at the source's hourly
  grain, and attribution + billing are event/transaction-level (near real-time),
  so we could build an intraday/hourly acquisition report for TikTok. Parked for
  now; the daily mart is the deliverable.

## if this ran in production

- **Orchestration & scheduling.** A single orchestrator (e.g. Airflow) owns the
  daily run: wait until every spend feed has landed, then trigger the pipeline —
  or, on a timeout, run a partial pipeline (proceed without a late source rather
  than block everything). Real refreshes often need to run in pieces, which maps
  cleanly onto **dbt tags** — tag models by layer / source / domain and run a
  subset (`dbt build --select tag:...`) instead of the whole DAG.
- **Alerting.** The orchestrator notifies on load failures, source-freshness
  breaches, and test failures.
- **Environments & CI/CD.** Separate dev/test environments so model developers
  don't step on each other, plus a safe promotion path to prod. The exact CI/CD
  wiring depends on whether we're on dbt Cloud or Core.
- **Incrementality.** Views are fine at this scale but get slow/expensive on real
  volume, so the refresh pattern would be analysed and models made incremental.
  The idempotency building block is already here — the latest load overwrites
  older ones, so a model can be re-run N times without old data clobbering new.
  Incremental runs take a **start/end date range as vars from the orchestrator**,
  so we process a single day or backfill a specific gap; the model should **fail
  fast if the range vars are missing**, to prevent an accidental full rebuild.
  Late / restated data is absorbed by a **lookback window owned by the model** —
  it subtracts N days from the incremental start bound (the orchestrator only
  passes the processing range; the lookback is the model's own concern), so
  restated attribution/spend and late refunds settle.
- **Refresh cadence & dead-model cleanup.** Refresh views and external tables on
  a schedule, at least weekly; flag anything not refreshed in > 1 week as a
  likely abandoned model cluttering the warehouse, and prune it.
- **Historized mappings (SCD2).** Snapshot the mapping tables
  (`account → channel`, `campaign → channel`) as slowly-changing dimensions, so
  past facts keep the channel/name as it was on that date rather than being
  rewritten by the current mapping.
- **Roadmap models.** Cohort **D0 / D7 / D30 ROAS** (see "revenue & cohort ROAS")
  and an **hourly TikTok report** (TikTok prep already keeps the hourly grain)
  are the first models to add.
- **Performance & storage.** Partition tables by date and cluster by the join
  keys (campaign_id / user_id). For sparse data, BigQuery physical (compressed)
  billing storage can be cheaper.
- **Data contracts.** Enforce a schema contract on sources/models (column names,
  types, nullability, allowed values), tied to the feed `v=` version. A change
  then fails the build loudly instead of silently breaking downstream — exactly
  the `.0` / whitespace / dtype drift we had to catch by hand would be caught
  automatically.
- **Observability & SLAs.** Beyond pass/fail tests: monitor row-count deltas and
  metric anomalies, and track reconciliation / freshness results over time
  against SLAs.
- **PII & governance.** `user_id` is personal data — access controls, retention
  policy, and propagation of GDPR deletions.
- **Cost controls.** Monitor query cost, prefer reservation vs on-demand as
  appropriate, and lean on partition pruning to avoid full scans.
- **Governance.** A semantic layer (see "ideas parked") to serve metrics
  consistently to BI tools and agents; plus a code-style + agent ruleset so SQL
  authored by different people/agents stays simple, consistent and correct.
- **Quality gates before deploy.** Unit tests asserting the core metric
  calculations (CAC, ROAS, revenue) haven't silently changed; duplicate checks;
  and a data-diff of model output (before vs after the change) reviewed before
  promotion. Plus an **aggregate-integrity test** that the mart's key totals
  (spend, installs, net revenue) equal the same totals in the intermediate
  models — catching join fan-out or dropped rows during mart assembly.

## out of scope

- materialization: everything is a **view** for now; in production the layers
  would need tables + incremental models depending on data volume and the
  load/refresh cadence
- dev/prod environment separation
- orchestration tags/selectors (refresh only what changed)

## testing

Lean and purpose-driven — each test guards a specific failure mode; no blanket
not_null / range noise.

- **freshness** (raw sources) — daily feeds must be no older than yesterday,
  hourly & realtime feeds no older than the previous hour. Catches a stalled or
  stopped feed. Run with `dbt source freshness`.
- **referential integrity** — every conversion (`attribution_events`) and
  billing `user_id` must exist in `first_touch` (relationship tests). Guards the
  inner joins from silently dropping orphan conversions/revenue.
- **manual-input validation** — the hand-maintained `account_channel_map` seed:
  `account_id` unique + not_null, `platform` accepted_values. Catches typos or
  duplicates when a human onboards a new account.
- **reconciliation vs source-of-truth** — modelled spend must match
  `platform_daily_totals` (the platform UI SSOT) within 0.5% per platform-day
  (`assert_spend_reconciles_within_0_5pct`). Currently, and by design, flags the
  Google 2-day source gap.

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
