# DECISIONS

Assumptions, trade-offs, and things intentionally left out. Grows as the
project is built.

## Tooling / environment

**dbt engine — must use dbt Core, not Fusion.**
The project targets BigQuery via dbt Cloud. The `dbt-external-tables` package
(used to create the raw external tables) is **not compatible with the dbt
Fusion engine** (preview). On both *Fusion Stable* and *Fusion Nightly* the run
panics at parse time:

```
panic: panicked at fs/sa/crates/dbt-schemas/src/state.rs:1056:22:
Dependency not resolved in correct order
```

Fusion crashes while parsing sources that carry the package's `external:`
blocks. Fix: set the dbt Cloud environment **dbt version = "Latest"**
(formerly Versionless — the dbt Core engine). `dbt deps` +
`dbt run-operation stage_external_sources` then run cleanly. "Compatible"
(pinned dbt Core) also works.

**Project name cannot be `dbt`.**
`name: 'dbt'` in `dbt_project.yml` collides with a reserved package name
(`dbt found more than one package with the name "dbt"`). Renamed the project to
`acquisition`. The folder stays `dbt/` (folder name ≠ project name); the dbt
Cloud **Project subdirectory** is set to `dbt`.

**Credentials never in the repo.**
The dbt Cloud IDE offered to commit a `profiles.yml` containing the BigQuery
service-account private key. That must not be committed — dbt Cloud stores the
key on the connection (encrypted). `profiles.yml` and key files are in
`.gitignore`. Raw data (`data/`) is also gitignored — it lives in GCS.

## Raw / ingestion layer

**GCS landing zone is Hive-partitioned.** Layout:

```
gs://<bucket>/source=<name>/feed=<feed>/type=<grain>/v=<n>/load_date=<YYYY-MM-DD>/load_epoch=<sec>/<file>
```

BigQuery external tables auto-detect both the file schema and the partition
columns (`source, feed, type, v, load_date, load_epoch`). Rationale:
- `v` = feed **schema/contract version** (bump on schema change).
- `load_date` (DATE) = ingestion batch date; native partition pruning + used to
  pick the latest load per source (idempotent re-runs).
- `load_epoch` (INT, seconds) = same instant with sub-day precision, colon-free
  so it never breaks GCS object naming while still typing/pruning cleanly.

Config-driven: adding a new feed = add a source block; a new load = drop a new
`load_date=/load_epoch=` folder. External tables are created with
`dbt run-operation stage_external_sources` (see `dbt/README.md`).

**Gotcha — scope the hive prefix per source, not to the bucket root.**
With `hive_partition_uri_prefix` set to the bucket root, BigQuery mis-inferred
the partition-key order across the 7 heterogeneous `source=/feed=/type=`
branches and failed at query time with *"Partition keys should be invariant...
expected [type, source, feed, ...], encountered [source, feed, type, ...]"* —
even though every object path was consistent. Fix: scope each table's prefix
down to its own `.../v=1/`, so `source/feed/type/v` are constants in the prefix
and only `load_date` + `load_epoch` remain partition columns. Verified: all 7
tables then read with exact expected row counts.
