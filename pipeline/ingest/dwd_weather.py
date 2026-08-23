"""DWD (Deutscher Wetterdienst) open data ingestion.

Pulls hourly wind speed and sunshine duration for a handful of stations
spread across Germany, to pair against ENTSO-E generation data and test
whether wind/solar output actually tracks the weather driving it.

No authentication -- opendata.dwd.de is a public file server. Historical
data is delivered as zipped, semicolon-delimited text files
("produkt_<param>_stunde_..."). Actually test-run against the live server
(2026-08-09, station 00691) to confirm real column names rather than
guessing -- one bug found and fixed: the wind speed column is `F`, not
`FF` (the `FF` in the URL/filename is the DWD *product* code, not the data
column name). Confirmed working: all 5 configured stations exist for both
elements, `MESS_DATUM` parses as expected, and `SD_SO` (sunshine) was
correct on the first guess.

Reference: https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/hourly/
"""
from __future__ import annotations

import io
import logging
import re
import zipfile

import pandas as pd
import requests

from pipeline.config import DWD_STATIONS

log = logging.getLogger(__name__)

BASE = "https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/hourly"

# DWD element folder name -> (URL/filename product code, real data column
# name, output column name). URL code and data column are NOT the same
# string for either element -- confirmed by downloading real files
# (2026-08-09): wind's URL code is "FF" but its data column is "F"; sun's
# URL code is "SD" but its data column is "SD_SO".
_ELEMENTS = {
    "wind": ("FF", "F", "wind_speed_ms"),
    "sun": ("SD", "SD_SO", "sunshine_duration_min"),
}


def _list_dir(url: str) -> list[str]:
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    return re.findall(r'href="([^"]+\.zip)"', resp.text)


def _download_product(zip_url: str) -> pd.DataFrame:
    resp = requests.get(zip_url, timeout=60)
    resp.raise_for_status()
    with zipfile.ZipFile(io.BytesIO(resp.content)) as zf:
        product_files = [n for n in zf.namelist() if n.startswith("produkt_")]
        if not product_files:
            raise RuntimeError(f"no produkt_* file found in {zip_url}")
        with zf.open(product_files[0]) as fh:
            df = pd.read_csv(fh, sep=";", encoding="latin1")
    df.columns = [c.strip() for c in df.columns]
    return df


def _fetch_element(element: str, period: str, station_id: str) -> pd.DataFrame:
    """period: 'recent' (rolling ~500 days) or 'historical' (full record, slower)."""
    url_code, data_col, out_col = _ELEMENTS[element]
    dir_url = f"{BASE}/{element}/{period}/"

    if period == "recent":
        zip_name = f"stundenwerte_{url_code}_{station_id}_akt.zip"
    else:
        candidates = _list_dir(dir_url)
        matches = [c for c in candidates if f"_{station_id}_" in c]
        if not matches:
            raise RuntimeError(f"no historical {element} file found for station {station_id}")
        zip_name = matches[0]

    df = _download_product(dir_url + zip_name)

    if data_col not in df.columns:
        raise RuntimeError(
            f"expected column '{data_col}' not found for {element}/{station_id}. "
            f"Real columns: {list(df.columns)}. DWD may have changed the format -- update _ELEMENTS."
        )

    out = pd.DataFrame(
        {
            "station_id": station_id,
            "observed_at": pd.to_datetime(df["MESS_DATUM"], format="%Y%m%d%H"),
            out_col: pd.to_numeric(df[data_col], errors="coerce"),
        }
    )
    return out


def fetch_wind(period: str = "recent") -> pd.DataFrame:
    frames = []
    for station_id, name in DWD_STATIONS.items():
        try:
            df = _fetch_element("wind", period, station_id)
            df["station_name"] = name
            frames.append(df)
        except Exception as exc:  # noqa: BLE001
            log.warning("wind fetch failed for station %s (%s): %s", station_id, name, exc)
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()


def fetch_sunshine(period: str = "recent") -> pd.DataFrame:
    frames = []
    for station_id, name in DWD_STATIONS.items():
        try:
            df = _fetch_element("sun", period, station_id)
            df["station_name"] = name
            frames.append(df)
        except Exception as exc:  # noqa: BLE001
            log.warning("sunshine fetch failed for station %s (%s): %s", station_id, name, exc)
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
