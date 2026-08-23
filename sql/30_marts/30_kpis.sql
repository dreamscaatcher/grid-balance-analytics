-- KPI views. These are what Power BI reads from -- no aggregation logic
-- should live in the dashboard itself. MW -> MWh conversion assumes 15-min
-- MTU (multiply by 0.25); ENTSO-E confirmed 15-min granularity for DE-LU.

-- === Page 1: Executive overview ===

-- 1. Total consumption
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_total_consumption_daily` AS
SELECT
  date,
  SUM(actual_load_mw) * 0.25 AS total_consumption_mwh
FROM `grid-analysis-505021.grid_marts.fact_load`
GROUP BY date;

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_total_consumption_summary` AS
SELECT
  MIN(date) AS period_start,
  MAX(date) AS period_end,
  SUM(actual_load_mw) * 0.25 AS total_consumption_mwh
FROM `grid-analysis-505021.grid_marts.fact_load`;

-- 2. Distribution of consumption -- raw enough for Power BI's histogram/box
-- visual to bucket itself; grouped view for a "typical day" profile shape.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_load_distribution_raw` AS
SELECT date, hour_of_day, actual_load_mw
FROM `grid-analysis-505021.grid_marts.fact_load`;

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
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_mean_load` AS
SELECT
  AVG(f.actual_load_mw) AS mean_load_mw,
  AVG(IF(NOT d.is_weekend AND f.hour_of_day BETWEEN 8 AND 19, f.actual_load_mw, NULL)) AS mean_peak_load_mw,
  AVG(IF(d.is_weekend OR f.hour_of_day NOT BETWEEN 8 AND 19, f.actual_load_mw, NULL)) AS mean_offpeak_load_mw
FROM `grid-analysis-505021.grid_marts.fact_load` f
LEFT JOIN `grid-analysis-505021.grid_marts.dim_date` d USING (date);

-- 4. Energy mix -- generation share by type/category.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_energy_mix_daily` AS
SELECT
  date,
  category,
  production_type,
  SUM(generation_mw) * 0.25 AS generation_mwh
FROM `grid-analysis-505021.grid_marts.fact_generation`
GROUP BY date, category, production_type;

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
  date,
  AVG(ABS(forecast_error_mw)) AS mae_mw,
  SQRT(AVG(POW(forecast_error_mw, 2))) AS rmse_mw,
  AVG(ABS(forecast_error_mw) / NULLIF(actual_load_mw, 0)) * 100 AS mape_pct
FROM `grid-analysis-505021.grid_marts.fact_load`
GROUP BY date;

-- Renewable forecast accuracy + a rough curtailment signal: actual well
-- below forecast while the day-ahead price is at or below zero suggests
-- output was throttled rather than simply mis-forecast.
CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_renewable_forecast_accuracy` AS
SELECT
  f.date,
  f.production_type,
  AVG(ABS(f.forecast_error_mw)) AS mae_mw,
  COUNTIF(f.actual_mw < f.forecast_mw * 0.8 AND p.day_ahead_price_eur_mwh <= 0) AS likely_curtailment_hours
FROM `grid-analysis-505021.grid_marts.fact_generation_forecast` f
LEFT JOIN `grid-analysis-505021.grid_marts.fact_price` p USING (mtu_start)
GROUP BY f.date, f.production_type;

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_crossborder_net_flow_daily` AS
SELECT
  date,
  neighbour_name,
  SUM(IF(direction = 'export', flow_mw, -flow_mw)) * 0.25 AS net_export_mwh
FROM `grid-analysis-505021.grid_marts.fact_crossborder_flow`
GROUP BY date, neighbour_name;

-- === Page 3: Commercial / price view ===

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_price_stats_daily` AS
SELECT
  date,
  AVG(day_ahead_price_eur_mwh) AS avg_price_eur_mwh,
  MIN(day_ahead_price_eur_mwh) AS min_price_eur_mwh,
  MAX(day_ahead_price_eur_mwh) AS max_price_eur_mwh,
  STDDEV(day_ahead_price_eur_mwh) AS price_volatility,
  COUNTIF(day_ahead_price_eur_mwh < 0) AS negative_price_hours
FROM `grid-analysis-505021.grid_marts.fact_price`
GROUP BY date;

CREATE OR REPLACE VIEW `grid-analysis-505021.grid_marts.kpi_price_vs_renewable_share` AS
SELECT
  p.date,
  p.avg_price_eur_mwh,
  SAFE_DIVIDE(
    SUM(IF(g.category = 'Renewable', g.generation_mwh, 0)),
    SUM(g.generation_mwh)
  ) AS renewable_share_pct
FROM `grid-analysis-505021.grid_marts.kpi_price_stats_daily` p
LEFT JOIN `grid-analysis-505021.grid_marts.kpi_energy_mix_daily` g USING (date)
GROUP BY p.date, p.avg_price_eur_mwh;

-- === Page 4: Fossil fuel drivers (night / weather / price) ===

-- Fossil share of generation split Day (weekday+weekend 08:00-19:59) vs
-- Night (everything else), with same-day weather and price alongside so
-- Power BI can build this whole page off one table without relationships.
--
-- Note on "low pressure days": this pipeline's DWD pull is wind speed +
-- sunshine duration only -- there's no barometric pressure feed. A
-- low-wind, low-sunshine day is used as the proxy instead, since that's
-- the actual mechanism that forces fossil generation up (renewables have
-- less to give, something has to fill the gap), and it's what "bad
-- weather" would show up as in this data anyway.
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
-- Bottom-quartile wind AND bottom-quartile sunshine, across the whole
-- period, flags a "bad weather for renewables" day.
weather_thresholds AS (
  SELECT
    APPROX_QUANTILES(avg_wind_speed_ms, 4)[OFFSET(1)] AS wind_p25,
    APPROX_QUANTILES(avg_sunshine_min, 4)[OFFSET(1)] AS sun_p25
  FROM weather_daily
),
price_daily AS (
  SELECT date, AVG(day_ahead_price_eur_mwh) AS avg_price_eur_mwh
  FROM `grid-analysis-505021.grid_marts.fact_price`
  GROUP BY date
)
SELECT
  gd.date,
  gd.day_night,
  gd.fossil_generation_mwh,
  gd.total_generation_mwh,
  gd.fossil_share_pct,
  w.avg_wind_speed_ms,
  w.avg_sunshine_min,
  (w.avg_wind_speed_ms < t.wind_p25 AND w.avg_sunshine_min < t.sun_p25)
    AS is_low_renewable_weather_day,
  p.avg_price_eur_mwh
FROM gen_daynight gd
LEFT JOIN weather_daily w USING (date)
CROSS JOIN weather_thresholds t
LEFT JOIN price_daily p USING (date);
