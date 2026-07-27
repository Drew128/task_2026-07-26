# Reconciliation

Goal: modelled spend must match the platform UI ground truth
(`platform_daily_totals`) to within **0.5% per platform-day**.

## Method

`intermediate__spend_reconciliation` aggregates the modelled spend
(`intermediate__spend_daily`) to `spend_date × platform` and `FULL OUTER JOIN`s
it to `prep__platform_totals`. The full outer join is deliberate — an inner
join would silently hide any platform-day missing from either side, which is
exactly the class of problem reconciliation exists to catch. The test
`assert_spend_reconciles_within_0_5pct` fails on any platform-day where
`|ours − truth| / truth > 0.5%`.

## Result

| platform | modelled | truth | diff | days > 0.5% |
|---|---:|---:|---:|---:|
| meta   | 32,606.28 | 32,606.28 | +0.00 | 0 |
| tiktok | 16,667.60 | 16,667.60 | +0.00 | 0 |
| google | 16,638.59 | 16,991.71 | −353.12 | 2 |

Meta and TikTok reconcile to **0.000% on every one of the 91 days**. Google
reconciles to **0.000% on 89 of 91 days**; the only exceptions are the two days
below.

## The one exception — Google, 2026-04-21 and 2026-04-22

| date | day | modelled | truth |
|---|---|---:|---:|
| 2026-04-21 | Tue | 0.00 | 177.39 |
| 2026-04-22 | Wed | 0.00 | 175.73 |

These two days are **entirely absent from the raw Google export**
(`google_ads_spend.csv` has zero rows for them), so the model has nothing to
sum. This is a gap in the source feed, not a modelling error:

- the missing days are **two consecutive weekdays** (Tue/Wed) — not a weekend
  pattern;
- the **adjacent days are intact** (2026-04-20 and 2026-04-23 each have the
  normal 3 rows and match truth exactly), so the spend did not shift into
  neighbouring days — our 20th + 23rd sum to 358.07 while truth for 20th–23rd
  is 711.19, i.e. exactly the ~$353 that is missing;
- Meta and TikTok are unaffected on the same two days.

The signature — a clean two-weekday hole with perfect neighbours — points to a
**failed / skipped Google Ads pull for those dates that was never retried or
backfilled**. The money was really spent (the platform UI shows it); only our
extract missed it. Remediation in production: re-pull / backfill Google Ads for
2026-04-21…22, after which reconciliation returns to 0%.

## Why the raw data didn't reconcile at first

Straight off the raw files the numbers did **not** match; three normalizations
were required to get to 0%:

- **Meta — de-duplication.** The fetcher re-pulls restated days, so
  `(date, campaign)` appears more than once (404 raw rows vs 364 unique). Summing
  raw rows double-counts and inflates Meta spend. Keeping only the newest
  `export_ts` per `(date, campaign)` fixes it.
- **TikTok — timezone and currency.** Spend arrives **hourly in UTC** and in the
  **account currency** (the EU account is EUR). Bucketing by UTC date misplaces
  the hours around midnight, and leaving EUR unconverted understates spend.
  Converting each hour to the `America/New_York` date and EUR→USD via the daily
  FX rate is what brings TikTok to 0.000%.
- **Google — micros.** Cost is reported in micros (`1 USD = 1,000,000 micros`);
  dividing by 1e6 is required.

Meta and TikTok landing at exactly 0.000% is the evidence these fixes are
correct; the only residual is the Google source gap above.

## Reproduce

See the build commands in `DECISIONS.md`. The reconciliation is available as
`intermediate__spend_reconciliation`; the gate runs with `dbt build` (or
`dbt test --select assert_spend_reconciles_within_0_5pct`) and is expected to
fail on the two Google days until the source is backfilled.
