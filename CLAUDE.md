# Project Context — Grid Balance Analytics

Claude Code reads this file automatically at the start of every session in
this repo, so context carries over without re-explaining it each time.

## What this repo is

`grid-balance-analytics` — an analytics platform on the German power grid
(DE-LU bidding zone). Real ENTSO-E Transparency Platform data (load,
generation by source, day-ahead prices, cross-border flows) and real DWD
weather data (wind, sunshine), landed in Google BigQuery, modeled into a
documented star schema with KPI views as the single source of truth, served
through a Power BI dashboard. See `README.md` for the full pitch, storyboard,
and architecture diagram.

GCP project: `grid-analysis-505021`. No git repo of its own yet — this
directory currently sits untracked inside the parent `projects/` git repo.

## Current known state (as of 2026-08-20)

- **Scaffolding built 2026-08-09/10:** full repo structure written in one
  session — layered SQL (`00_setup` → `10_raw` → `20_staging` → `30_marts`),
  ingest modules (`entsoe_grid.py`, `dwd_weather.py`), BigQuery loader, KPI
  definitions and data dictionary docs, three-page Power BI storyboard spec.
- **ENTSO-E token obtained and pipeline run end-to-end, 2026-08-10.** The
  README had said "pending Gurinder's ENTSO-E API token" but that was stale
  — `.env` was filled in with a real token at 09:24 UTC, and
  `python -m pipeline.run_pipeline` ran successfully ~14:47-14:52 UTC the
  same day. Verified via `bq query` against `grid_raw.__TABLES__` on
  2026-08-20: all 8 raw tables have real rows (`total_load` 8,640,
  `load_forecast` 8,640, `generation_actual` 146,870, `wind_solar_forecast`
  25,920, `day_ahead_prices` 17,280, `crossborder_flows` 138,240,
  `weather_wind` 65,873, `weather_sunshine` 51,718).
- **`sql/20_staging` and `sql/30_marts` also run, same session (2026-08-10),
  confirmed via `bq ls` on 2026-08-20.** `grid_staging` has 6 tables
  (`load`, `prices`, `weather`, `generation_actual`, `crossborder_flows`,
  `wind_solar_forecast`). `grid_marts` has all 3 dimension tables
  (`dim_date`, `dim_neighbour`, `dim_production_type`), 6 fact tables, and
  all 11 KPI views from `docs/kpi_definitions.md` /
  `powerbi/DASHBOARD_SPEC.md`. **Data engineering side of this project is
  fully done** — nothing left to build in SQL/BigQuery.
- **`powerbi/measures.dax` filled in, 2026-08-20** — replaced the placeholder
  with real pass-through measures (mostly `SUM`/`AVERAGE` over the `kpi_*`
  views, since the SQL layer already does the real computation) covering all
  three storyboard pages: total/mean consumption, energy mix share, forecast
  MAE/RMSE/MAPE, curtailment signal, cross-border net export, price stats +
  negative-price-hours + renewable-share-vs-price.
- **Power BI Desktop build, 2026-08-20 — Page 1 ("Exec Overview") complete:**
  - Total Consumption card (`kpi_total_consumption_summary.total_consumption_mwh`)
  - Consumption Trend line chart (`kpi_total_consumption_daily`)
  - Load Distribution histogram — **built as a standard Clustered Column
    Chart**, not the spec's originally-implied native histogram visual. Uses
    a calculated column `Load Bin (MW) = INT(actual_load_mw/2000)*2000` on
    `kpi_load_distribution_raw`, X-axis = Load Bin (MW), Y-axis = Count of
    `actual_load_mw`.
  - Mean Load / Peak Avg / Off-Peak Avg cards (`kpi_mean_load`)
  - Energy Mix stacked area chart (`kpi_energy_mix_daily`, category as legend)
  - Generation Share donut chart (`kpi_energy_mix_share`, category as legend,
    `share_of_total` as values) — the view existed since the 08-20 measures
    pass but sat unused until caught mid-session; storyboard called for
    "stacked area **+ share-of-total**" and only the area chart had been built.
- **Page 2 ("Grid Bal Ops") mostly done, 2 of 3 items built:**
  - Load Forecast vs Actual line chart + Load Forecast MAE/RMSE/MAPE cards
    (`kpi_load_forecast_accuracy`) — RMSE card had a Sum-vs-Average bug, fixed.
  - Renewable Forecast Accuracy & Curtailment Signal — a **Line and clustered
    column chart** (`kpi_renewable_forecast_accuracy`: `date` shared axis,
    `likely_curtailment_hours` as columns, `mae_mw` as line), titled with an
    explicit "(inferred)" suffix per the curtailment caveat in
    `docs/kpi_definitions.md`.
  - **Still missing:** cross-border net flow chart (`kpi_crossborder_net_flow_daily`).
  - **Known issue, not yet resolved:** a second, likely-accidental "Grid Bal
    Ops" tab appeared next to the real one. Flagged to Gurinder to check and
    delete if empty — not confirmed fixed as of this writing.
- **Page 3 ("Price view") complete, all 3 items built:**
  - Day-ahead Price line chart with a zero constant reference line
    (`kpi_price_stats_daily`).
  - Negative-Price Hours card — had a Count-vs-Sum bug (showed 24, the row
    count, instead of the real 581 quarter-hour MTUs); fixed to Sum.
  - Price vs. Renewable Share scatter chart (`kpi_price_vs_renewable_share`:
    `avg_price_eur_mwh` x-axis, `renewable_share_pct` y-axis, `date` in
    tooltips not legend) — shows a clear negative correlation, the strongest
    chart in the dashboard so far.
- **Abandoned approach, worth knowing about:** tried building the Load
  Distribution chart with the custom "HTML Content" AppSource visual (a DAX
  measure generating an inline-styled HTML/CSS bar chart via
  `CONCATENATEX`+`SUMMARIZE`). Got as far as a working bar chart, but hit
  repeated, unresolvable CSS sizing issues inside the visual's sandbox
  (`height:100%` collapsed to zero — no sized ancestor; `height:100vh`
  rendered relative to the wrong viewport and produced a blank canvas).
  A second custom visual, the native/AppSource "Histogram Chart", was also
  tried for the same chart and rendered as a fully blank canvas with no error.
  Both abandoned in favor of native built-in visuals (Clustered Column Chart,
  Line and clustered column chart, Donut chart, Scatter chart), which have
  worked reliably every time since. The DAX measure from the first attempt,
  **`Load Distribution HTML`**, and the **`Load Bin (MW)` column it depends
  on are still in the model** — the column is reused by the working chart,
  but the measure itself is dead code. Safe to delete `Load Distribution
  HTML` if you want a cleaner model; it's unused by any visual.
- **Page 4 planned, 2026-08-20 — "fossil fuel use increases at night, bad
  weather, and low pressure days, and its effect on price."** No barometric
  pressure feed exists in this pipeline (the DWD pull is wind speed +
  sunshine duration only) — substituted an honest low-wind+low-sunshine
  bottom-quartile proxy (`is_low_renewable_weather_day`) rather than
  fabricating pressure data. Added a new KPI view,
  `kpi_fossil_drivers_daily` (`sql/30_marts/30_kpis.sql`), joining hourly
  fossil share (Day 08:00-19:59 vs. Night split), daily weather, the weather
  flag, and daily price into **one self-contained table** so the page needs
  no Power BI relationships. Matching measures added to `powerbi/measures.dax`
  (`Fossil Generation (MWh)`, `Fossil Share %`, `Avg Wind Speed (m/s)`,
  `Avg Sunshine (min)`, `Fossil Driver Avg Price (EUR/MWh)`), and
  `docs/kpi_definitions.md` updated with the view + the proxy caveat.
- **Pipeline widened 90d->180d, 2026-08-20 (later same day).** Gurinder
  asked for more data; re-running the pipeline at 180 days hit
  `httpx.ReadTimeout` on `fetch_generation_actual` every time, even at a
  single 90-day chunk (ruling out payload size) -- root cause was
  `entsoe-apy`'s hardcoded 20s default read timeout, fixed via
  `entsoe.config.set_config(timeout=90)` added to `pipeline/config.py`.
  Also added 90-day chunking to `fetch_generation_actual` in
  `pipeline/ingest/entsoe_grid.py` as cheap insurance (not the actual fix,
  but harmless to keep). Full pipeline run then succeeded end-to-end
  (~22.6 min, mostly ENTSO-E latency -- 2 of 16 crossborder legs needed a
  few retries but all landed). Ran via `bq`/`gcloud` directly on Gurinder's
  machine (Windows-MCP PowerShell) -- the sandboxed Linux `device_bash` has
  no network/gcloud and cannot run this. Rebuilt `sql/00_setup` through
  `sql/30_marts` afterward (`--location=EU` required explicitly, since `bq`
  CLI defaults to US region). **`kpi_fossil_drivers_daily` is now live on
  the 180-day window**: 2026-02-20 to 2026-08-19, 361 rows, 4
  low-renewable-weather-flagged days (up from 2 on the old 90-day window).
  Page 4 is fully unblocked -- ready to build in Power BI.
- **.pbix file not yet saved/named** — still "Untitled - Power BI Desktop"
  as of 2026-08-20. Save it into the repo (or wherever the rail-ops-analytics
  precedent puts it — gitignored, per `powerbi/DASHBOARD_SPEC.md`'s build
  notes) before closing Power BI Desktop.

## Conventions specific to this repo

- BI tools read **only** from `grid_marts` KPI views — never from `grid_raw`
  or `grid_staging` directly, and DAX measures should be thin pass-throughs
  (`SUM`/`AVERAGE`/`MIN`/`MAX`), not re-derivations. The SQL layer is the
  single source of truth for computation (MAE/RMSE/MAPE, shares, MW→MWh
  conversion, forecast error).
- 15-minute MTU granularity throughout (confirmed for DE-LU) — 96
  quarter-hours/day. Anything counting "hours" (e.g. negative-price hours)
  is really counting quarter-hour MTUs; the project's own docs use "hours"
  loosely, kept for consistency with `docs/kpi_definitions.md`.
- Inferred figures (e.g. curtailment from forecast-vs-actual gaps) must be
  labelled explicitly as inferred wherever they're surfaced — see "Data
  honesty" section in `README.md`.
- Once the first Power BI Service publish is attempted, follow the same
  fallback used on `rail-ops-analytics`: public "Publish to web" link if
  available, else `.pbix` + screenshots in the repo (gitignored, not
  committed).
