# KPI Definitions

All KPIs are computed once in `sql/30_marts/30_kpis.sql`; Power BI only visualizes them.

| KPI | View | Definition |
|---|---|---|
| Total consumption | `kpi_total_consumption_daily`, `kpi_total_consumption_summary` | SUM(actual load MW) x 0.25 (15-min MTU -> MWh), daily and period totals |
| Load distribution | `kpi_load_distribution_raw`, `kpi_load_profile_by_hour` | Raw load values for histogram/box-plot visuals; hourly avg/min/max/stddev for a "typical day" shape, split by season |
| Mean load | `kpi_mean_load` | Overall average load; peak (weekday 08:00-19:59) vs. off-peak average |
| Energy mix | `kpi_energy_mix_daily`, `kpi_energy_mix_share` | Generation MWh by production type/category, and each category's share of total generation |
| Load forecast accuracy | `kpi_load_forecast_accuracy` | MAE, RMSE, MAPE of day-ahead load forecast vs. actual, daily |
| Renewable forecast accuracy / curtailment | `kpi_renewable_forecast_accuracy` | MAE of wind/solar forecast vs. actual; count of hours where actual < 80% of forecast while price <= 0 (inferred curtailment signal -- see data_dictionary.md caveat) |
| Cross-border net flow | `kpi_crossborder_net_flow_daily` | Net export (export - import) MWh per neighbour per day |
| Price stats | `kpi_price_stats_daily` | Avg/min/max/stddev day-ahead price, count of negative-price hours, daily |
| Price vs. renewable share | `kpi_price_vs_renewable_share` | Daily avg price paired with that day's renewable share of generation, for volatility-vs-renewables analysis |
| Fossil fuel drivers | `kpi_fossil_drivers_daily` | Fossil share of generation split Day (08:00-19:59) vs. Night, per date, with same-day avg wind speed, avg sunshine, a low-wind+low-sunshine "bad weather" flag, and avg price -- all in one table so the page needs no relationships |

## Definitions worth being explicit about

**Peak / off-peak** follows the standard EPEX convention: peak = weekdays, 08:00-19:59 local time. Off-peak = everything else (nights, weekends).

**Renewable share** = renewable generation MWh / total generation MWh for the day (wind onshore + offshore, solar, run-of-river hydro, reservoir hydro, biomass, other renewable). Pumped storage hydro is categorized separately as "Storage," not "Renewable," since it's net energy-consuming overall (pumps water uphill using grid power, then releases it) -- counting it as generation-only renewable would overstate the renewable share.

**Negative price hours** counts MTUs where the day-ahead price cleared below EUR 0/MWh -- a real, published phenomenon in Germany during high-renewable, low-demand periods (generators effectively pay to keep running rather than shut down, often due to must-run constraints or subsidy structures).

**"Low renewable weather" day** (`kpi_fossil_drivers_daily.is_low_renewable_weather_day`) is an inferred proxy, not a directly reported condition -- there's no barometric pressure feed in this pipeline (the DWD pull covers wind speed and sunshine duration only). A day flags as "low renewable weather" when its avg wind speed AND avg sunshine duration both fall in the bottom quartile for the period. This is the actual mechanism worth showing (less wind/sun -> less renewable output -> fossil fills the gap), it's just not literally "low pressure."
