# Power BI Dashboard Spec

Connect Power BI Desktop to BigQuery (`grid-analysis-505021`), import mode, reading only from the `grid_marts` KPI views listed in `docs/kpi_definitions.md`. No DAX should recompute anything the SQL already computes -- Power BI aggregates and visualizes, it doesn't derive.

## Page 1 -- Executive Overview

1. **Total consumption** -- KPI card, `kpi_total_consumption_summary.total_consumption_mwh`. Secondary card or sparkline from `kpi_total_consumption_daily` for the trend.
2. **Distribution of consumption** -- histogram or box plot from `kpi_load_distribution_raw.actual_load_mw`, sliceable by season/hour-of-day using `kpi_load_profile_by_hour`.
3. **Mean consumption** -- KPI card for `kpi_mean_load.mean_load_mw`, with peak/off-peak split shown as two smaller cards or a clustered bar.
4. **Energy mix** -- stacked area chart over time from `kpi_energy_mix_daily` (category on color), plus a donut/bar from `kpi_energy_mix_share` for the period-total share.

## Page 2 -- Grid Balance Operations Deep-Dive

- Line chart: day-ahead load forecast vs. actual, with MAE/RMSE as a card (`kpi_load_forecast_accuracy`).
- Line chart: wind/solar forecast vs. actual by production type, with likely-curtailment-hours flagged (`kpi_renewable_forecast_accuracy`) -- label explicitly as "inferred" per the data dictionary caveat.
- Map or bar chart: net cross-border flow by neighbour (`kpi_crossborder_net_flow_daily`) -- does Germany export more on high-renewable days, import more on low-renewable ones?

## Page 3 -- Commercial / Price View

- Line/area chart: day-ahead price over time, with negative-price periods highlighted (`kpi_price_stats_daily`).
- Scatter plot: daily avg price vs. renewable share (`kpi_price_vs_renewable_share`) -- the volatility-vs-renewables story.
- Card: count/percentage of negative-price hours over the period.

## Build notes

- All three pages share a date-range slicer against `dim_date`.
- Once the first Power BI Service publish is attempted, follow the same fallback used on rail-ops-analytics if the personal-account publish path is blocked: use a public "Publish to web" link if available, or fall back to a .pbix + screenshots in the repo (gitignored, not committed, per that project's precedent).
- Screenshots for the case study should be taken once the first real data pull is in and the "so what" finding (curtailment, forecast error pattern, or negative-price frequency) is identified -- pick the strongest one as the dashboard's headline, the way the FlixTrain join bug became that project's centerpiece.
