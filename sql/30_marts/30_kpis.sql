-- KPI views. These are what Power BI reads from. The aggregates below
-- (MAE, RMSE, MAPE, MWh conversion, fossil share, renewable share,
-- curtailment count) are unchanged. Added columns are names, sort keys,
-- and is_partial_day so the report can label and filter without
-- recomputing those figures or deleting the partial edge days.
--
-- MW -> MWh conversion assumes 15-min MTU (multiply by 0.25); ENTSO-E
-- confirmed 15-min granularity for DE-LU.
--
-- Share columns named *_pct on these views (renewable_share_pct,
-- fossil_share_pct) are ratios in [0, 1]. mape_pct is already x100.
-- Power BI percent formats belong on the ratios only. See measures.dax.

-- === Page 1: Executive overview ===

-- 1. Total consumption
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_total_consumption_daily` AS
SELECT
  f.date,
  d.is_partial_day,
  SUM(f.actual_load_mw) * 0.25 AS total_consumption_mwh
FROM `grid-analysis-505021.grid_marts.fact_load` f
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON f.date = d.date
GROUP BY f.date, d.is_partial_day;

-- Period total across every landed MTU, partial edge days included.
-- The dashboard card sums kpi_total_consumption_daily under the
-- is_partial_day filter instead of reading this view.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_total_consumption_summary` AS
SELECT
  MIN(date) AS period_start,
  MAX(date) AS period_end,
  SUM(actual_load_mw) * 0.25 AS total_consumption_mwh
FROM `grid-analysis-505021.grid_marts.fact_load`;

-- 2. Distribution of consumption -- raw enough for Power BI's column
-- chart to bucket itself. is_peak / is_offpeak repeat the EPEX rule in
-- kpi_mean_load (weekday 08:00-19:59 vs everything else) so a measure can
-- average the quarter-hours without hard-coding the hours in DAX.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_load_distribution_raw` AS
SELECT
  f.date,
  f.hour_of_day,
  f.actual_load_mw,
  d.is_partial_day,
  (NOT d.is_weekend AND f.hour_of_day BETWEEN 8 AND 19) AS is_peak,
  (d.is_weekend OR f.hour_of_day NOT BETWEEN 8 AND 19) AS is_offpeak
FROM `grid-analysis-505021.grid_marts.fact_load` f
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON f.date = d.date;

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_load_profile_by_hour` AS
SELECT
  f.hour_of_day,
  d.season,
  AVG(f.actual_load_mw) AS avg_load_mw,
  MIN(f.actual_load_mw) AS min_load_mw,
  MAX(f.actual_load_mw) AS max_load_mw,
  STDDEV(f.actual_load_mw) AS stddev_load_mw
FROM `grid-analysis-505021.grid_marts.fact_load` f
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d USING (date)
GROUP BY f.hour_of_day, d.season;

-- 3. Mean consumption -- overall, and peak (weekday 08:00-19:59) vs off-peak.
-- Includes every MTU. Dashboard cards average kpi_load_distribution_raw
-- so the date slicer and the partial-day filter apply to the same rule.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_mean_load` AS
SELECT
  AVG(f.actual_load_mw) AS mean_load_mw,
  AVG(IF(NOT d.is_weekend AND f.hour_of_day BETWEEN 8 AND 19, f.actual_load_mw, NULL)) AS mean_peak_load_mw,
  AVG(IF(d.is_weekend OR f.hour_of_day NOT BETWEEN 8 AND 19, f.actual_load_mw, NULL)) AS mean_offpeak_load_mw
FROM `grid-analysis-505021.grid_marts.fact_load` f
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d USING (date);

-- 4. Energy mix -- generation by type/category. Names come from
-- dim_production_type; the code stays on the row as the relationship key.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_energy_mix_daily` AS
SELECT
  g.date,
  d.is_partial_day,
  COALESCE(pt.category, g.category) AS category,
  pt.category_sort,
  g.production_type,
  COALESCE(pt.production_type_name, g.production_type) AS production_type_name,
  COALESCE(pt.production_type_label, g.production_type) AS production_type_label,
  pt.type_sort,
  SUM(g.generation_mw) * 0.25 AS generation_mwh
FROM `grid-analysis-505021.grid_marts.fact_generation` g
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON g.date = d.date
LEFT JOIN `grid-analysis-505021.grid_marts.dim_production_type` pt
  ON g.production_type = pt.production_type
GROUP BY
  g.date,
  d.is_partial_day,
  COALESCE(pt.category, g.category),
  pt.category_sort,
  g.production_type,
  COALESCE(pt.production_type_name, g.production_type),
  COALESCE(pt.production_type_label, g.production_type),
  pt.type_sort;

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_energy_mix_share` AS
SELECT
  category,
  SUM(generation_mwh) AS generation_mwh,
  SUM(generation_mwh) / SUM(SUM(generation_mwh)) OVER () AS share_of_total
FROM `grid-analysis-505021.grid_marts.kpi_energy_mix_daily`
GROUP BY category;

-- === Page 2: Grid balance operations deep-dive ===

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_load_forecast_accuracy` AS
SELECT
  f.date,
  d.is_partial_day,
  AVG(f.actual_load_mw) AS avg_actual_load_mw,
  AVG(f.forecast_load_mw) AS avg_forecast_load_mw,
  AVG(ABS(f.forecast_error_mw)) AS mae_mw,
  SQRT(AVG(POW(f.forecast_error_mw, 2))) AS rmse_mw,
  AVG(ABS(f.forecast_error_mw) / NULLIF(f.actual_load_mw, 0)) * 100 AS mape_pct
FROM `grid-analysis-505021.grid_marts.fact_load` f
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON f.date = d.date
GROUP BY f.date, d.is_partial_day;

-- Renewable forecast accuracy + a rough curtailment signal: actual well
-- below forecast while the day-ahead price is at or below zero suggests
-- output was throttled rather than simply mis-forecast.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_renewable_forecast_accuracy` AS
SELECT
  f.date,
  d.is_partial_day,
  f.production_type,
  COALESCE(pt.production_type_name, f.production_type) AS production_type_name,
  COALESCE(pt.production_type_label, f.production_type) AS production_type_label,
  pt.category,
  pt.category_sort,
  pt.type_sort,
  AVG(ABS(f.forecast_error_mw)) AS mae_mw,
  COUNTIF(f.actual_mw < f.forecast_mw * 0.8 AND p.day_ahead_price_eur_mwh <= 0) AS likely_curtailment_hours
FROM `grid-analysis-505021.grid_marts.fact_generation_forecast` f
LEFT JOIN `grid-analysis-505021.grid_marts.fact_price` p
  ON f.mtu_start = p.mtu_start
LEFT JOIN `grid-analysis-505021.grid_marts.dim_production_type` pt
  ON f.production_type = pt.production_type
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON f.date = d.date
GROUP BY
  f.date,
  d.is_partial_day,
  f.production_type,
  COALESCE(pt.production_type_name, f.production_type),
  COALESCE(pt.production_type_label, f.production_type),
  pt.category,
  pt.category_sort,
  pt.type_sort;

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_crossborder_net_flow_daily` AS
SELECT
  f.date,
  d.is_partial_day,
  f.neighbour,
  f.neighbour_name,
  SUM(IF(f.direction = 'export', f.flow_mw, -f.flow_mw)) * 0.25 AS net_export_mwh
FROM `grid-analysis-505021.grid_marts.fact_crossborder_flow` f
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON f.date = d.date
GROUP BY f.date, d.is_partial_day, f.neighbour, f.neighbour_name;

-- === Page 3: Commercial / price view ===

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_price_stats_daily` AS
SELECT
  p.date,
  d.is_partial_day,
  AVG(p.day_ahead_price_eur_mwh) AS avg_price_eur_mwh,
  MIN(p.day_ahead_price_eur_mwh) AS min_price_eur_mwh,
  MAX(p.day_ahead_price_eur_mwh) AS max_price_eur_mwh,
  STDDEV(p.day_ahead_price_eur_mwh) AS price_volatility,
  COUNTIF(p.day_ahead_price_eur_mwh < 0) AS negative_price_hours
FROM `grid-analysis-505021.grid_marts.fact_price` p
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON p.date = d.date
GROUP BY p.date, d.is_partial_day;

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_price_vs_renewable_share` AS
SELECT
  p.date,
  d.is_partial_day,
  p.avg_price_eur_mwh,
  SAFE_DIVIDE(
    SUM(IF(g.category = 'Renewable', g.generation_mwh, 0)),
    SUM(g.generation_mwh)
  ) AS renewable_share_pct
FROM `grid-analysis-505021.grid_marts.kpi_price_stats_daily` p
LEFT JOIN `grid-analysis-505021.grid_marts.kpi_energy_mix_daily` g USING (date)
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON p.date = d.date
GROUP BY p.date, d.is_partial_day, p.avg_price_eur_mwh;

-- === Page 4: Fossil fuel drivers (night / weather / price) ===

-- Fossil share of generation split Day (weekday+weekend 08:00-19:59) vs
-- Night (everything else), with same-day weather and price alongside so
-- Power BI can build this whole page off one table without relationships.
--
-- The low-renewable-weather flag is defined once on dim_date (bottom
-- quartile of daily average wind AND daily average sunshine). This view
-- only carries that column forward, plus a short label for the table.
-- There is no barometric pressure feed in the DWD pull.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_fossil_drivers_daily` AS
WITH gen_hourly AS (
  SELECT
    DATE(mtu_start) AS date,
    EXTRACT(HOUR FROM mtu_start) AS hour_of_day,
    SUM(IF(category = 'Fossil', generation_mw, 0)) AS fossil_mw,
    SUM(generation_mw) AS total_mw
  FROM `grid-analysis-505021.grid_marts.fact_generation`
  GROUP BY date, hour_of_day
),
gen_daynight AS (
  SELECT
    date,
    IF(hour_of_day BETWEEN 8 AND 19, 'Day', 'Night') AS day_night,
    SUM(fossil_mw) * 0.25 AS fossil_generation_mwh,
    SUM(total_mw) * 0.25 AS total_generation_mwh,
    SAFE_DIVIDE(SUM(fossil_mw), SUM(total_mw)) AS fossil_share_pct
  FROM gen_hourly
  GROUP BY date, day_night
),
weather_daily AS (
  SELECT
    date,
    AVG(wind_speed_ms) AS avg_wind_speed_ms,
    AVG(sunshine_duration_min) AS avg_sunshine_min
  FROM `grid-analysis-505021.grid_marts.fact_weather`
  GROUP BY date
),
price_daily AS (
  SELECT date, AVG(day_ahead_price_eur_mwh) AS avg_price_eur_mwh
  FROM `grid-analysis-505021.grid_marts.fact_price`
  GROUP BY date
)
SELECT
  gd.date,
  d.is_partial_day,
  gd.day_night,
  gd.fossil_generation_mwh,
  gd.total_generation_mwh,
  gd.fossil_share_pct,
  w.avg_wind_speed_ms,
  w.avg_sunshine_min,
  d.is_low_renewable_weather_day,
  d.low_renewable_day_label,
  p.avg_price_eur_mwh
FROM gen_daynight gd
LEFT JOIN weather_daily w USING (date)
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d
  ON gd.date = d.date
LEFT JOIN price_daily p USING (date);
