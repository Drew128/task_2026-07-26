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

- **prep** (one model per source · table · own dataset `prep_<source>.<feed>`)
  - meta: flatten nested JSON, dedup restatements by newest `export_ts`
  - tiktok: hourly UTC→NY date, account currency→USD via FX, roll up to daily
  - google: `cost_micros / 1e6`
  - events: strip campaign_id platform prefix (organic→NULL), UTC→NY date
  - billing: UTC→NY date
  - fx / platform: typed pass-through
  - conventions: source CTEs on top → transforms → `final`; UPPERCASE keywords;
    `_FILE_NAME AS data_source` for lineage

## out of scope

- incrementality (models are full-refresh tables)
- dev/prod environment separation
- orchestration tags/selectors (refresh only what changed)

## open

- prep dedup: prefer an in-data field over `load_epoch` where one exists

## build from scratch

```bash
# 1. upload data/ to GCS in the hive layout (see raw sources)
# 2. set env vars: DBT_GCP_PROJECT, DBT_RAW_DATASET, DBT_RAW_BUCKET
dbt deps
dbt run-operation stage_external_sources   # create raw external tables
dbt build                                  # build models + run tests
dbt source freshness                       # freshness checks
```
