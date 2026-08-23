-- Documentation of the raw table shapes landed by pipeline/load/bigquery_loader.py.
-- The Python loader creates these automatically (schema inferred from the
-- pandas DataFrame) -- this file is a reference/fallback, not a required
-- step. If a load ever needs to be done manually (e.g. via `bq load`),
-- these CREATE TABLE statements describe the expected shape.

CREATE TABLE IF NOT EXISTS `grid-analysis-505021.grid_raw.total_load` (
  mtu_start TIMESTAMP,
  actual_load_mw FLOAT64
);

CREATE TABLE IF NOT EXISTS `grid-analysis-505021.grid_raw.load_forecast` (
  mtu_start TIMESTAMP,
  forecast_load_mw FLOAT64
);

CREATE TABLE IF NOT EXISTS `grid-analysis-505021.grid_raw.generation_actual` (
  mtu_start TIMESTAMP,
  production_type STRING,  -- ENTSO-E PSR code, e.g. "B19" -- see docs/data_dictionary.md
  generation_mw FLOAT64
);

CREATE TABLE IF NOT EXISTS `grid-analysis-505021.grid_raw.wind_solar_forecast` (
  mtu_start TIMESTAMP,
  production_type STRING,  -- one of B16 (Solar), B18 (Wind Offshore), B19 (Wind Onshore)
  forecast_mw FLOAT64
);

CREATE TABLE IF NOT EXISTS `grid-analysis-505021.grid_raw.day_ahead_prices` (
  mtu_start TIMESTAMP,
  day_ahead_price_eur_mwh FLOAT64
);

CREATE TABLE IF NOT EXISTS `grid-analysis-505021.grid_raw.crossborder_flows` (
  mtu_start TIMESTAMP,
  flow_mw FLOAT64,
  neighbour STRING,
  direction STRING
);

CREATE TABLE IF NOT EXISTS `grid-analysis-505021.grid_raw.weather_wind` (
  station_id STRING,
  observed_at TIMESTAMP,
  wind_speed_ms FLOAT64,
  station_name STRING
);

CREATE TABLE IF NOT EXISTS `grid-analysis-505021.grid_raw.weather_sunshine` (
  station_id STRING,
  observed_at TIMESTAMP,
  sunshine_duration_min FLOAT64,
  station_name STRING
);
