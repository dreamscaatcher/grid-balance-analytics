"""Entry point: pull ENTSO-E + DWD data and land it in BigQuery raw tables.

Usage:
    python -m pipeline.run_pipeline [--days N]

SQL in sql/ (00_setup onward) then builds staging/marts on top of these raw
tables -- run that separately (e.g. via `bq query` or a BigQuery Studio
notebook) once the raw load is verified.
"""
from __future__ import annotations

import argparse
import logging

import pandas as pd

from pipeline.config import DEFAULT_BACKFILL_DAYS
from pipeline.ingest import dwd_weather, entsoe_grid
from pipeline.load.bigquery_loader import load_dataframe

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger(__name__)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=DEFAULT_BACKFILL_DAYS)
    args = parser.parse_args()

    end = pd.Timestamp.now(tz="Europe/Brussels").normalize()
    start = end - pd.Timedelta(days=args.days)

    log.info("pulling ENTSO-E data: %s -> %s", start, end)
    load_dataframe(entsoe_grid.fetch_total_load(start, end), "total_load")
    load_dataframe(entsoe_grid.fetch_day_ahead_load_forecast(start, end), "load_forecast")
    load_dataframe(entsoe_grid.fetch_generation_actual(start, end), "generation_actual")
    load_dataframe(entsoe_grid.fetch_wind_solar_forecast(start, end), "wind_solar_forecast")
    load_dataframe(entsoe_grid.fetch_day_ahead_prices(start, end), "day_ahead_prices")
    load_dataframe(entsoe_grid.fetch_crossborder_flows(start, end), "crossborder_flows")

    log.info("pulling DWD data (recent window)")
    load_dataframe(dwd_weather.fetch_wind(), "weather_wind")
    load_dataframe(dwd_weather.fetch_sunshine(), "weather_sunshine")

    log.info("raw load complete. Next: run sql/00_setup through sql/30_marts.")


if __name__ == "__main__":
    main()
