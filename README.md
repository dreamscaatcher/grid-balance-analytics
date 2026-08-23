# Grid Balance Analytics

Analytics platform on the German power grid (DE-LU bidding zone): is it under strain, and where? A Python pipeline ingests **real ENTSO-E Transparency Platform data** (load, generation by source, day-ahead prices, cross-border flows) and **real DWD weather data** (wind, sunshine), lands both in **Google BigQuery**, models them into a documented star schema with **KPI views as the single source of truth**, and serves a **Power BI** dashboard.

Built to mirror the day-to-day work of a grid/energy data analyst: total consumption, its distribution and mean, the generation mix, forecast accuracy, and where negative prices or likely curtailment show up.

## The question

As renewable share grows, where do load/generation mismatches, forecast misses, and price volatility actually show up in the German grid -- not in theory, in the real data?

## Storyboard (v1)

**Page 1 -- Executive overview**
- Total consumption (sum of Actual Total Load over the period)
- Distribution of consumption (histogram / box plot by hour-of-day and season)
- Mean consumption (average load, with peak vs. off-peak split)
- Energy mix (generation by source, stacked area + share-of-total)

**Page 2 -- Grid balance operations deep-dive**
- Day-ahead load forecast vs. actual (forecast error over time)
- Day-ahead wind/solar generation forecast vs. actual (forecast error, possible curtailment signal)
- Cross-border physical flows vs. renewable output (where the slack goes)

**Page 3 -- Commercial / price view**
- Day-ahead price vs. renewable share (volatility, negative-price hours)
- Price distribution and negative-price frequency

## Data sources

| Data | Source | Status |
|---|---|---|
| Total load (actual + day-ahead forecast) | [ENTSO-E Transparency Platform](https://transparency.entsoe.eu/) | Real |
| Generation per production type (actual) | ENTSO-E Transparency Platform | Real |
| Wind/solar generation forecast | ENTSO-E Transparency Platform | Real |
| Day-ahead prices | ENTSO-E Transparency Platform | Real |
| Cross-border physical flows | ENTSO-E Transparency Platform | Real |
| Wind speed, sunshine duration | [DWD Open Data (CDC)](https://opendata.dwd.de/climate_environment/CDC/) | Real |

Bidding zone: **DE-LU** (Germany-Luxembourg), EIC code `10Y1001A1001A82H`.

## Architecture

```
ENTSO-E API ---\
                 >-- Python (pipeline/ingest) --> BigQuery raw --> staging --> marts (star schema + KPI views) --> Power BI
DWD Open Data --/
```

Layered ELT: `grid_raw` (landed as-is) -> `grid_staging` (typed, deduplicated) -> `grid_marts` (star schema + KPI views). BI tools read **only** from marts.

GCP project: `grid-analysis-505021`.

## Quickstart

0. **Python >=3.11 required** -- `entsoe-apy` won't install on 3.10 or older (confirmed 2026-08-09: pip refuses on Python 3.10 with no compatible version found). Check `python3 --version` before `pip install -r requirements.txt`.
1. **ENTSO-E API token** (free): register at [transparency.entsoe.eu](https://transparency.entsoe.eu/); if the token option isn't visible under *My Account Settings*, email transparency@entsoe.eu with subject "Restful API access" first (approval takes up to 3 business days). Set `ENTSOE_API` in `.env` (this exact variable name -- the `entsoe-apy` package reads it automatically). **Done (2026-08-10).**
2. **BigQuery**: `gcloud auth application-default login`, set `GCP_PROJECT_ID=grid-analysis-505021` in `.env`. The pipeline creates all datasets and objects itself -- `sql/00_setup/setup.sql`.
3. **DWD**: no auth needed, public file server.
4. Run the pipeline: `python -m pipeline.run_pipeline`. **Done (2026-08-10, ~14:47-14:52 UTC)** -- all 8 raw tables landed with real data, verified via `bq` on 2026-08-20.
5. Run `sql/00_setup` through `sql/30_marts` in order (e.g. via `bq query` or BigQuery Studio). **Done (2026-08-10)** -- staging and marts, including all KPI views, are live in BigQuery.
6. Build the dashboard: `powerbi/DASHBOARD_SPEC.md` (measures in `powerbi/measures.dax`). **In progress (2026-08-20)** -- Pages 1 and 3 complete, Page 2 missing one chart, Page 4 (new, not in the original storyboard) planned but blocked on step 7.
7. New KPI view for a 4th page (fossil fuel use at night / bad weather / price effect): `kpi_fossil_drivers_daily` in `sql/30_marts/30_kpis.sql`. **Done (2026-08-20)** -- live on the 180-day window (2026-02-20 to 2026-08-19), ready for Power BI.

Ingestion uses [`entsoe-apy`](https://entsoe-apy.berrisch.biz/) (not the older `entsoe-py`) -- its classes mirror the official ENTSO-E API doc sections one-to-one.

## Repo layout

```
pipeline/            Python ingestion + BigQuery load
  ingest/             entsoe_grid.py, dwd_weather.py
  load/               bigquery_loader.py
sql/                 Warehouse models, executed in order: 00_setup / 10_raw / 20_staging / 30_marts
tests/               pytest suite
powerbi/             Dashboard build spec + DAX measures
docs/                KPI definitions, data dictionary
```

## Data honesty

Everything in this project is real, measured data -- no synthetic overlay (unlike the FlixTrain project, this dataset doesn't have a commercial-confidentiality gap to work around). Where a figure is inferred rather than directly reported (e.g. approximate curtailment from forecast-vs-actual generation gaps), that will be labelled explicitly in the data dictionary.

## Status

Data engineering is done. `sql/00_setup` through `sql/30_marts` have all run against real data: raw ingestion landed 8 tables in `grid_raw` (~460K rows total across load, generation, prices, cross-border flows, and weather -- confirmed via `bq query` against `__TABLES__` on 2026-08-20), `grid_staging` has 6 cleaned tables, and `grid_marts` has all 3 dimension tables, 6 fact tables, and all 11 KPI views from `docs/kpi_definitions.md` / `powerbi/DASHBOARD_SPEC.md`.

Power BI build is in progress, as of 2026-08-20. Page 1 ("Exec Overview") is complete -- 6 visuals built and connected to the `kpi_*` views: Total Consumption card, Consumption Trend line, Load Distribution histogram, Mean Load card (+ peak/off-peak split), Energy Mix stacked area, and a Generation Share donut chart. Page 3 ("Price view") is also complete -- Day-ahead Price line with a zero reference line, Negative-Price Hours card, and a Price vs. Renewable Share scatter chart showing a clear negative correlation. Page 2 ("Grid Bal Ops") is missing one chart -- cross-border net flow -- everything else on it is built.

A 4th page was requested mid-build, not part of the original 3-page storyboard: fossil fuel use increasing at night, on bad-weather days, and its effect on price. This pipeline has no barometric pressure feed (DWD pull is wind speed + sunshine duration only), so "low pressure day" is approximated as a bottom-quartile low-wind, low-sunshine day instead of silently faking pressure data -- see the caveat in `docs/kpi_definitions.md`. The KPI view, `kpi_fossil_drivers_daily`, is live in BigQuery as of 2026-08-20 -- Page 4 is unblocked and ready to build.

The pipeline was also widened from a 90-day to a 180-day trailing window on 2026-08-20 (2026-02-20 to 2026-08-19). Doing so surfaced a real bug: `fetch_generation_actual` hit `httpx.ReadTimeout` on every attempt at the wider range -- not because of payload size (a single 90-day chunk failed identically), but because `entsoe-apy` defaults to a 20-second read timeout that was too tight for how slowly ENTSO-E was responding that day. Fixed by setting `entsoe.config.set_config(timeout=90)` in `pipeline/config.py`. All raw, staging, and marts tables have been rebuilt on the wider window.

`powerbi/measures.dax` has been filled in with real pass-through measures for all four pages (see file). One measure in there, `Load Distribution HTML`, is unused leftover from an abandoned attempt to build the histogram with the custom "HTML Content" AppSource visual (it rendered unreliably -- blank canvas, CSS sizing issues inside the visual's sandbox) -- safe to delete, or ignore. A second custom visual, "Histogram Chart", was also tried and abandoned (rendered fully blank). The Load Distribution visual that's actually live uses a standard Clustered Column Chart against a `Load Bin (MW)` calculated column (`INT(actual_load_mw/2000)*2000`) with Count aggregation, which is what worked -- along with every other visual built since, all native Power BI chart types.
