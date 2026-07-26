# dbt acquisition — setup

## Environment variables

The project is config-driven: GCP project, raw dataset and GCS bucket are all
read from environment variables (with sensible defaults). Nothing is hardcoded
to a single environment.

| Variable | What it sets | Default | Where used |
|---|---|---|---|
| `DBT_GCP_PROJECT` | GCP / BigQuery project id | `zeely-takehome` | `source.database` in `models/raw/raw.yml` |
| `DBT_RAW_DATASET` | BQ dataset that holds the external tables | `raw` | `source.schema` in `models/raw/raw.yml` |
| `DBT_RAW_BUCKET` | GCS bucket of the raw landing zone | `zeely-takehome-raw` | external table `location` / `hive_partition_uri_prefix` |

Notes:
- In **dbt Cloud**, custom environment variables **must start with `DBT_`** —
  that is why every variable above is prefixed. Set them under
  *Project settings → Environment variables*.
- Locally (dbt Core), export them in your shell before running, e.g.
  `export DBT_GCP_PROJECT=zeely-takehome`.
- The **output dataset** for dbt models (staging/marts) is set on the dbt Cloud
  **connection** (or in `profiles.yml` locally), not here.

## Raw landing zone (GCS layout)

Hive-partitioned, so BigQuery auto-detects schema **and** partition columns:

```
gs://$DBT_RAW_BUCKET/
  source=<name>/feed=<feed>/type=<grain>/v=<n>/load_date=<YYYY-MM-DD>/load_epoch=<sec>/<file>
```

Partition columns exposed to BQ: `source, feed, type, v, load_date, load_epoch`.
Adding a new load = drop a new `load_date=/load_epoch=` folder; staging keeps
only the latest load per source (idempotent).

## Step 1 — create the external (raw) tables

Prerequisites: files uploaded to the bucket, the `raw` dataset exists, and the
service account has `roles/storage.objectViewer` + `roles/bigquery.dataEditor`
+ `roles/bigquery.jobUser`.

```bash
dbt deps                              # install dbt_external_tables + dbt_utils
dbt run-operation stage_external_sources
```

This creates the 7 external tables in the `raw` dataset over the GCS files.
Verify with e.g. `select count(*) from raw.meta_spend_export`.
