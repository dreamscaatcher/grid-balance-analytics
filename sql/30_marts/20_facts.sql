-- Fact tables. Thin, typed pass-throughs from staging with date keys added
-- for joining to dim_date. KPI logic itself lives in 30_kpis.sql, not here.

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.fact_load` AS
SELECT
  mtu_start,
  DATE(mtu_start) AS date,
  EXTRACT(HOUR FROM mtu_start) AS hour_of_day,
  actual_load_mw,
  forecast_load_mw,
  actual_load_mw - forecast_load_mw AS forecast_error_mw
FROM `grid-analysis-505021.grid_staging.load`;

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.fact_generation` AS
SELECT
  g.mtu_start,
  DATE(g.mtu_start) AS date,
  g.production_type,
  d.production_type_name,
  d.production_type_label,
  d.category,
  d.category_sort,
  d.type_sort,
  g.generation_mw
FROM `grid-analysis-505021.grid_staging.generation_actual` g
LEFT JOIN `grid-analysis-505021.grid_marts.dim_production_type` d
  USING (production_type);

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.fact_generation_forecast` AS
SELECT
  f.mtu_start,
  DATE(f.mtu_start) AS date,
  f.production_type,
  pt.production_type_name,
  pt.production_type_label,
  pt.category,
  f.forecast_mw,
  g.generation_mw AS actual_mw,
  g.generation_mw - f.forecast_mw AS forecast_error_mw
FROM `grid-analysis-505021.grid_staging.wind_solar_forecast` f
LEFT JOIN `grid-analysis-505021.grid_staging.generation_actual` g
  USING (mtu_start, production_type)
LEFT JOIN `grid-analysis-505021.grid_marts.dim_production_type` pt
  USING (production_type);

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.fact_price` AS
SELECT
  mtu_start,
  DATE(mtu_start) AS date,
  day_ahead_price_eur_mwh
FROM `grid-analysis-505021.grid_staging.prices`;

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.fact_crossborder_flow` AS
SELECT
  cf.mtu_start,
  DATE(cf.mtu_start) AS date,
  cf.neighbour,
  n.neighbour_name,
  cf.direction,
  cf.flow_mw
FROM `grid-analysis-505021.grid_staging.crossborder_flows` cf
LEFT JOIN `grid-analysis-505021.grid_marts.dim_neighbour` n
  USING (neighbour);

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.fact_weather` AS
SELECT
  observed_at,
  DATE(observed_at) AS date,
  station_id,
  station_name,
  wind_speed_ms,
  sunshine_duration_min
FROM `grid-analysis-505021.grid_staging.weather`;
