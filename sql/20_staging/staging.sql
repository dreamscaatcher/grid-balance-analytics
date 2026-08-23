-- Typed, deduplicated staging layer. Run after 10_raw is populated by the
-- Python pipeline. CREATE OR REPLACE throughout -- safe to re-run.
--
-- NOTE (2026-08-09 correction): generation_actual and wind_solar_forecast
-- arrive from pipeline/ingest/entsoe_grid.py already in LONG format --
-- one row per (mtu, production_type), with production_type as an ENTSO-E
-- PSR code (e.g. "B19" for Wind Onshore), NOT a wide table with one column
-- per type. An earlier draft of this file used UNPIVOT assuming a wide
-- shape with human-readable column names -- that was wrong (confirmed
-- against the entsoe-apy source: AssetTypeList enum values are the codes
-- themselves, e.g. `B19 = "B19"`). No UNPIVOT needed; see dim_production_type
-- in 10_dimensions.sql for the code -> category mapping.

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_staging.load` AS
SELECT
  TIMESTAMP(a.mtu_start) AS mtu_start,
  a.actual_load_mw,
  f.forecast_load_mw
FROM `grid-analysis-505021.grid_raw.total_load` a
FULL OUTER JOIN `grid-analysis-505021.grid_raw.load_forecast` f
  USING (mtu_start)
QUALIFY ROW_NUMBER() OVER (PARTITION BY mtu_start ORDER BY mtu_start) = 1;

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_staging.prices` AS
SELECT
  TIMESTAMP(mtu_start) AS mtu_start,
  day_ahead_price_eur_mwh
FROM `grid-analysis-505021.grid_raw.day_ahead_prices`
QUALIFY ROW_NUMBER() OVER (PARTITION BY mtu_start ORDER BY mtu_start) = 1;

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_staging.crossborder_flows` AS
SELECT
  TIMESTAMP(mtu_start) AS mtu_start,
  neighbour,
  direction,
  flow_mw
FROM `grid-analysis-505021.grid_raw.crossborder_flows`
QUALIFY ROW_NUMBER() OVER (PARTITION BY mtu_start, neighbour, direction ORDER BY mtu_start) = 1;

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_staging.weather` AS
SELECT
  TIMESTAMP(w.observed_at) AS observed_at,
  w.station_id,
  w.station_name,
  w.wind_speed_ms,
  s.sunshine_duration_min
FROM `grid-analysis-505021.grid_raw.weather_wind` w
FULL OUTER JOIN `grid-analysis-505021.grid_raw.weather_sunshine` s
  USING (station_id, observed_at)
QUALIFY ROW_NUMBER() OVER (PARTITION BY station_id, observed_at ORDER BY observed_at) = 1;

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_staging.generation_actual` AS
SELECT
  TIMESTAMP(mtu_start) AS mtu_start,
  production_type,  -- ENTSO-E PSR code, e.g. "B19" -- see dim_production_type
  generation_mw
FROM `grid-analysis-505021.grid_raw.generation_actual`
QUALIFY ROW_NUMBER() OVER (PARTITION BY mtu_start, production_type ORDER BY mtu_start) = 1;

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_staging.wind_solar_forecast` AS
SELECT
  TIMESTAMP(mtu_start) AS mtu_start,
  production_type,  -- PSR code, one of B16 (Solar), B18 (Wind Offshore), B19 (Wind Onshore)
  forecast_mw
FROM `grid-analysis-505021.grid_raw.wind_solar_forecast`
QUALIFY ROW_NUMBER() OVER (PARTITION BY mtu_start, production_type ORDER BY mtu_start) = 1;
