# Changelog

## 2026-10-17

Presentation and filter pass for the public Power BI report. KPI formulas are unchanged, and no landed rows are deleted. The owner applies the visual changes in Power BI from `powerbi/DASHBOARD_SPEC.md`.

### Warehouse

- `dim_production_type` remains the B01–B20 lookup. Titles were checked against the ENTSO-E Common Code Lists v36r0 Asset Type list and the entsoe-apy PSR notes (B01 Biomass, B02 Fossil Brown coal/Lignite, B11 Hydro Run-of-river and poundage, B19 Wind Onshore, B20 Other, and the rest of that list). Added `production_type_label` (`B19 Wind Onshore`), `category_sort`, and `type_sort`. Category grouping is unchanged: Renewable, Fossil, Nuclear, Storage, Other.
- Official names, labels, and sort keys are now on `fact_generation`, `fact_generation_forecast`, `kpi_energy_mix_daily`, and `kpi_renewable_forecast_accuracy`, so a visual can show "Wind Onshore" instead of `B19`.
- `dim_neighbour` gained `neighbour_sort`. `kpi_crossborder_net_flow_daily` now includes the `neighbour` code for the relationship.
- `dim_date` is the axis for every daily visual. Added `month_name`, `year_month`, `day_of_month`, `day_name`, `load_mtu_count`, `expected_mtu_count` (92 / 96 / 100 quarter-hours for a Europe/Brussels civil day), and `is_partial_day`. The flag is true only on the first or last load date when that edge is short of a full civil day. Interior dates, including a full DST day, stay unflagged. Partial-day rows stay in every table.
- The low-renewable-weather rule (bottom quartile of daily mean wind and of daily mean sunshine) now lives on `dim_date` as `is_low_renewable_weather_day` and `low_renewable_day_label`, and is carried on `kpi_fossil_drivers_daily`. Same rule as before; still not a pressure measurement.
- Daily KPI views gained `is_partial_day`. `kpi_load_forecast_accuracy` also exposes `avg_actual_load_mw` and `avg_forecast_load_mw` at the same grain as the existing MAE / RMSE / MAPE. `kpi_load_distribution_raw` gained `is_peak` and `is_offpeak` using the existing EPEX peak rule.

### Power BI source of truth

- `powerbi/measures.dax` now has explicit averages for mean load, peak, off-peak, and fossil share; a donut measure `Generation Mix Share %` formatted as a percent; format strings for MWh, MW, and EUR/MWh; and `Actual Load (MW)` / `Forecast Load (MW)`. `Generation Share of Total` and `Total Consumption Trend (MWh)` are replaced by `Generation Mix Share %` and `Total Consumption (MWh)`.
- `powerbi/DASHBOARD_SPEC.md` is a page-by-page build checklist: exact titles with closing brackets, fields, axis titles, formats, a 1280×720 layout with no empty regions, and slicers for date, production category, production type, neighbour, and the low-renewable-day flag. Daily charts use `dim_date[date]` (continuous), which is the correction for day-of-month totals and the false drop on the 31st. An all-pages filter on `is_partial_day` = false takes the partial edge off the canvas without dropping it from the model.

Re-run `sql/30_marts/10_dimensions.sql`, `sql/30_marts/20_facts.sql`, and `sql/30_marts/30_kpis.sql` in that order (`--location=EU`) before refreshing the model. Raw and staging tables do not need a reload.
