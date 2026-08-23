"""Shared configuration for the grid-balance-analytics pipeline.

Loads secrets/config from .env (see .env.example). Nothing in this file
should be hardcoded per-environment except the domain constants below,
which describe *what* we pull, not *how* to authenticate.
"""
import os

from dotenv import load_dotenv
from entsoe.config import set_config

load_dotenv()

# --- ENTSO-E (entsoe-apy package) ---
# entsoe-apy reads the ENTSOE_API env var itself on import; we also expose
# it here so other modules (and tests) can check whether it's set.
ENTSOE_API_KEY = os.environ.get("ENTSOE_API", "")

# entsoe-apy's default read timeout is 20s (see entsoe/config/config.py's
# set_config()). Confirmed 2026-08-20: fetch_generation_actual (DE_LU, all
# psr_types) hit httpx.ReadTimeout at ~20s on every one of 5 retries, even
# after chunking the request down to a 90-day window that had worked fine
# on 2026-08-10 -- so this is a slow-response day for that endpoint, not a
# payload-size problem. Widening to 90s here (leaving security_token unset
# so it still falls back to the ENTSOE_API env var, per set_config's own
# docstring) so a slow-but-alive response doesn't get killed prematurely.
set_config(timeout=90)

# Bidding zone under study: Germany-Luxembourg.
# EIC code confirmed against entsoe-apy's own mappings dict (2026-08-09):
# entsoe.utils.mappings["10Y1001A1001A82H"] == {"DE-LU": ["BZN", "IPA", "MBA", "SCA"]}
BZN_DE_LU = "DE_LU"
BZN_DE_LU_EIC = "10Y1001A1001A82H"

# Direct physical/market neighbours of DE-LU, as EIC codes -- confirmed
# against entsoe-apy's mappings dict.
NEIGHBOURS_EIC = {
    "FR": "10YFR-RTE------C",
    "NL": "10YNL----------L",
    "BE": "10YBE----------2",
    "AT": "10YAT-APG------L",
    "CH": "10YCH-SWISSGRIDZ",
    "CZ": "10YCZ-CEPS-----N",
    "PL": "10YPL-AREA-----S",
    "DK_1": "10YDK-1--------W",
}

# --- Google BigQuery ---
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "grid-analysis-505021")
BQ_LOCATION = os.environ.get("BQ_LOCATION", "EU")

BQ_DATASET_RAW = "grid_raw"
BQ_DATASET_STAGING = "grid_staging"
BQ_DATASET_MARTS = "grid_marts"

# --- DWD ---
# Representative stations covering different regions of Germany, chosen for
# long, complete "recent" hourly history. Station IDs per DWD's station
# catalogue (VALIDATE before first run -- station availability changes).
DWD_STATIONS = {
    "00691": "Berlin-Tempelhof",
    "01048": "Dresden-Klotzsche",
    "05906": "Muenchen-Stadt",
    "04177": "Hamburg-Fuhlsbuettel",
    "01443": "Essen-Bredeney",
}

# --- Pull window ---
# Default backfill window in days when running the pipeline without explicit
# --days arg. ENTSO-E enforces a one-year range limit per request for most
# endpoints; entsoe-apy automatically splits large requests, but keep this
# modest for the first runs.
DEFAULT_BACKFILL_DAYS = 90
