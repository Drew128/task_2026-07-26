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
dbt seed                                   # load account_channel_map (config-driven mapping)
dbt run-operation stage_external_sources   # create raw external tables
dbt build                                  # build seeds + models + run tests
dbt source freshness                       # freshness checks
```
