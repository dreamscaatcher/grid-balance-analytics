-- Dimension tables. Run after 20_staging.

-- dim_date: one row per civil date in the observed load window.
-- Generated from the data, not hardcoded, so it follows whatever backfill
-- was pulled. Chart axes use [date]. [day_of_month] exists for reference
-- and is the wrong axis: it collapses the 1st of every month into one point.
--
-- is_partial_day flags the first and/or last date when that edge holds fewer
-- quarter-hours than the full Europe/Brussels civil day (92 on the spring
-- DST day, 96 on a normal day, 100 on the autumn DST day). The pipeline
-- window is cut on Europe/Brussels midnights (see pipeline/run_pipeline.py),
-- so a short edge is the partial first or last day. Interior dates stay
-- unflagged, including a full 23-hour or 25-hour DST day. No rows are removed.
--
-- is_low_renewable_weather_day is the same bottom-quartile rule the fossil
-- KPI has always used (both daily mean wind and daily mean sunshine below
-- the period's 25th percentile). It lives here so a slicer on the date
-- table can filter every daily visual. kpi_fossil_drivers_daily reads it
-- back out. There is still no barometric pressure feed.
CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.dim_date` AS
WITH bounds AS (
  SELECT MIN(DATE(mtu_start)) AS min_date, MAX(DATE(mtu_start)) AS max_date
  FROM `grid-analysis-505021.grid_staging.load`
),
load_coverage AS (
  SELECT DATE(mtu_start) AS date, COUNT(*) AS load_mtu_count
  FROM `grid-analysis-505021.grid_staging.load`
  GROUP BY date
),
weather_daily AS (
  SELECT
    DATE(observed_at) AS date,
    AVG(wind_speed_ms) AS avg_wind_speed_ms,
    AVG(sunshine_duration_min) AS avg_sunshine_min
  FROM `grid-analysis-505021.grid_staging.weather`
  GROUP BY date
),
-- Same APPROX_QUANTILES call the fossil KPI used before this column moved
-- onto the date dimension: OFFSET(1) of 4 quantiles is the 25th percentile.
weather_thresholds AS (
  SELECT
    APPROX_QUANTILES(avg_wind_speed_ms, 4)[OFFSET(1)] AS wind_p25,
    APPROX_QUANTILES(avg_sunshine_min, 4)[OFFSET(1)] AS sun_p25
  FROM weather_daily
),
days AS (
  SELECT
    d AS date,
    COALESCE(c.load_mtu_count, 0) AS load_mtu_count,
    DIV(
      TIMESTAMP_DIFF(
        TIMESTAMP(DATE_ADD(d, INTERVAL 1 DAY), 'Europe/Brussels'),
        TIMESTAMP(d, 'Europe/Brussels'),
        MINUTE
      ),
      15
    ) AS expected_mtu_count
  FROM bounds
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(min_date, max_date)) AS d
  LEFT JOIN load_coverage c
    ON c.date = d
)
SELECT
  days.date,
  EXTRACT(YEAR FROM days.date) AS year,
  EXTRACT(QUARTER FROM days.date) AS quarter,
  EXTRACT(MONTH FROM days.date) AS month,
  FORMAT_DATE('%B', days.date) AS month_name,
  DATE_TRUNC(days.date, MONTH) AS year_month,
  EXTRACT(DAY FROM days.date) AS day_of_month,
  EXTRACT(DAYOFWEEK FROM days.date) AS day_of_week,  -- 1 = Sunday .. 7 = Saturday
  FORMAT_DATE('%A', days.date) AS day_name,
  EXTRACT(DAYOFWEEK FROM days.date) IN (1, 7) AS is_weekend,
  CASE EXTRACT(MONTH FROM days.date)
    WHEN 12 THEN 'Winter' WHEN 1 THEN 'Winter' WHEN 2 THEN 'Winter'
    WHEN 3 THEN 'Spring'  WHEN 4 THEN 'Spring'  WHEN 5 THEN 'Spring'
    WHEN 6 THEN 'Summer'  WHEN 7 THEN 'Summer'  WHEN 8 THEN 'Summer'
    ELSE 'Autumn'
  END AS season,
  days.load_mtu_count,
  days.expected_mtu_count,
  (days.date = bounds.min_date OR days.date = bounds.max_date)
    AND days.load_mtu_count < days.expected_mtu_count AS is_partial_day,
  (w.avg_wind_speed_ms < t.wind_p25 AND w.avg_sunshine_min < t.sun_p25)
    AS is_low_renewable_weather_day,
  CASE
    WHEN (w.avg_wind_speed_ms < t.wind_p25 AND w.avg_sunshine_min < t.sun_p25)
      THEN 'Low-renewable day'
    WHEN (w.avg_wind_speed_ms < t.wind_p25 AND w.avg_sunshine_min < t.sun_p25) = FALSE
      THEN 'Other day'
    ELSE 'Unknown'
  END AS low_renewable_day_label
FROM days
CROSS JOIN bounds
LEFT JOIN weather_daily w
  ON w.date = days.date
CROSS JOIN weather_thresholds t;

-- dim_production_type: ENTSO-E PSR / asset-type codes B01-B20 to the official
-- titles, plus this project's category grouping for the energy-mix visuals.
--
-- Titles verified 2026-10-17 against the ENTSO-E Common Code Lists, Asset
-- Type list, code list v36r0 (B01 "Biomass" through B20 "Other"):
-- https://www.entsoe.eu/Documents/EDI/Library/Core/entso-e-code-list-v36r0.pdf
-- and against the entsoe-apy master-data PSR notes this pipeline's client
-- documents (same titles, including B11 "Hydro Run-of-river and poundage"):
-- https://entsoe-apy.berrisch.biz/ENTSOE/master_data/
-- "poundage" is the code-list spelling. Later CIM codelists retitle some of
-- these same codes (B11 becomes "Hydro Run-of-river head installation",
-- B10 "Hydro-electric pure pumped storage head installation", and so on).
-- Transparency Platform actual generation, which is what lands in this
-- warehouse, still classifies with the B01-B20 titles below.
--
-- category is not an ENTSO-E field. It is the grouping the energy-mix
-- charts use. Pumped storage (B10) is Storage, not Renewable. Germany does
-- not populate every code (B08 Fossil Peat and B13 Marine are the usual
-- gaps); unused rows simply do not join.
--
-- production_type_label is the code plus the official name ("B19 Wind
-- Onshore") for tooltips. Chart legends use production_type_name.
-- category_sort and type_sort are Power BI "Sort by column" keys.
CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.dim_production_type` AS
SELECT * FROM UNNEST([
  STRUCT('B01' AS production_type, 'Biomass' AS production_type_name, 'B01 Biomass' AS production_type_label, 'Renewable' AS category, 1 AS category_sort, 1 AS type_sort),
  ('B02', 'Fossil Brown coal/Lignite', 'B02 Fossil Brown coal/Lignite', 'Fossil', 2, 2),
  ('B03', 'Fossil Coal-derived gas', 'B03 Fossil Coal-derived gas', 'Fossil', 2, 3),
  ('B04', 'Fossil Gas', 'B04 Fossil Gas', 'Fossil', 2, 4),
  ('B05', 'Fossil Hard coal', 'B05 Fossil Hard coal', 'Fossil', 2, 5),
  ('B06', 'Fossil Oil', 'B06 Fossil Oil', 'Fossil', 2, 6),
  ('B07', 'Fossil Oil shale', 'B07 Fossil Oil shale', 'Fossil', 2, 7),
  ('B08', 'Fossil Peat', 'B08 Fossil Peat', 'Fossil', 2, 8),
  ('B09', 'Geothermal', 'B09 Geothermal', 'Renewable', 1, 9),
  ('B10', 'Hydro Pumped Storage', 'B10 Hydro Pumped Storage', 'Storage', 4, 10),
  ('B11', 'Hydro Run-of-river and poundage', 'B11 Hydro Run-of-river and poundage', 'Renewable', 1, 11),
  ('B12', 'Hydro Water Reservoir', 'B12 Hydro Water Reservoir', 'Renewable', 1, 12),
  ('B13', 'Marine', 'B13 Marine', 'Renewable', 1, 13),
  ('B14', 'Nuclear', 'B14 Nuclear', 'Nuclear', 3, 14),
  ('B15', 'Other renewable', 'B15 Other renewable', 'Renewable', 1, 15),
  ('B16', 'Solar', 'B16 Solar', 'Renewable', 1, 16),
  ('B17', 'Waste', 'B17 Waste', 'Other', 5, 17),
  ('B18', 'Wind Offshore', 'B18 Wind Offshore', 'Renewable', 1, 18),
  ('B19', 'Wind Onshore', 'B19 Wind Onshore', 'Renewable', 1, 19),
  ('B20', 'Other', 'B20 Other', 'Other', 5, 20)
]);

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.dim_neighbour` AS
SELECT * FROM UNNEST([
  STRUCT('FR' AS neighbour, 'France' AS neighbour_name, 1 AS neighbour_sort),
  ('NL', 'Netherlands', 2),
  ('BE', 'Belgium', 3),
  ('AT', 'Austria', 4),
  ('CH', 'Switzerland', 5),
  ('CZ', 'Czech Republic', 6),
  ('PL', 'Poland', 7),
  ('DK_1', 'Denmark (West)', 8)
]);
