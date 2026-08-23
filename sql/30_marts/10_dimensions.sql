-- Dimension tables. Run after 20_staging.

-- dim_date: spans the observed range of load data, generated rather than
-- hardcoded so it always covers whatever backfill window was pulled.
CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.dim_date` AS
WITH bounds AS (
  SELECT MIN(DATE(mtu_start)) AS min_date, MAX(DATE(mtu_start)) AS max_date
  FROM `grid-analysis-505021.grid_staging.load`
)
SELECT
  d AS date,
  EXTRACT(YEAR FROM d) AS year,
  EXTRACT(MONTH FROM d) AS month,
  EXTRACT(QUARTER FROM d) AS quarter,
  EXTRACT(DAYOFWEEK FROM d) AS day_of_week,   -- 1 = Sunday .. 7 = Saturday
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS is_weekend,
  CASE EXTRACT(MONTH FROM d)
    WHEN 12 THEN 'Winter' WHEN 1 THEN 'Winter' WHEN 2 THEN 'Winter'
    WHEN 3 THEN 'Spring'  WHEN 4 THEN 'Spring'  WHEN 5 THEN 'Spring'
    WHEN 6 THEN 'Summer'  WHEN 7 THEN 'Summer'  WHEN 8 THEN 'Summer'
    ELSE 'Autumn'
  END AS season
FROM bounds, UNNEST(GENERATE_DATE_ARRAY(min_date, max_date)) AS d;

-- dim_production_type: maps ENTSO-E PSR type codes (the values actually
-- returned by entsoe-apy -- confirmed by reading its AssetTypeList enum
-- source, e.g. `B19 = "B19"`, NOT the human-readable name) to a
-- renewable/fossil/nuclear/storage category for the energy-mix visual.
-- Full standard code list confirmed 2026-08-09 against entsoe-apy's
-- urn_entsoe_eu_wgedi_codelists.py. Germany won't populate every one of
-- these (e.g. B08 Fossil Peat, B13 Marine are not present in DE) -- that's
-- fine, unused rows just won't join to anything.
CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.dim_production_type` AS
SELECT * FROM UNNEST([
  STRUCT('B01' AS production_type, 'Biomass' AS production_type_name, 'Renewable' AS category),
  ('B02', 'Fossil Brown coal/Lignite', 'Fossil'),
  ('B03', 'Fossil Coal-derived gas', 'Fossil'),
  ('B04', 'Fossil Gas', 'Fossil'),
  ('B05', 'Fossil Hard coal', 'Fossil'),
  ('B06', 'Fossil Oil', 'Fossil'),
  ('B07', 'Fossil Oil shale', 'Fossil'),
  ('B08', 'Fossil Peat', 'Fossil'),
  ('B09', 'Geothermal', 'Renewable'),
  ('B10', 'Hydro Pumped Storage', 'Storage'),
  ('B11', 'Hydro Run-of-river and poundage', 'Renewable'),
  ('B12', 'Hydro Water Reservoir', 'Renewable'),
  ('B13', 'Marine', 'Renewable'),
  ('B14', 'Nuclear', 'Nuclear'),
  ('B15', 'Other renewable', 'Renewable'),
  ('B16', 'Solar', 'Renewable'),
  ('B17', 'Waste', 'Other'),
  ('B18', 'Wind Offshore', 'Renewable'),
  ('B19', 'Wind Onshore', 'Renewable'),
  ('B20', 'Other', 'Other')
]);

CREATE OR REPLACE TABLE `grid-analysis-505021.grid_marts.dim_neighbour` AS
SELECT * FROM UNNEST([
  STRUCT('FR' AS neighbour, 'France' AS neighbour_name),
  ('NL', 'Netherlands'),
  ('BE', 'Belgium'),
  ('AT', 'Austria'),
  ('CH', 'Switzerland'),
  ('CZ', 'Czech Republic'),
  ('PL', 'Poland'),
  ('DK_1', 'Denmark (West)')
]);
