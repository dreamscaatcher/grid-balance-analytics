-- Idempotent setup for grid-analysis-505021.
-- Run once (or safely re-run) before the staging/marts SQL below.

CREATE SCHEMA IF NOT EXISTS `grid-analysis-505021.grid_raw`
  OPTIONS (location = 'EU');

CREATE SCHEMA IF NOT EXISTS `grid-analysis-505021.grid_staging`
  OPTIONS (location = 'EU');

CREATE SCHEMA IF NOT EXISTS `grid-analysis-505021.grid_marts`
  OPTIONS (location = 'EU');
