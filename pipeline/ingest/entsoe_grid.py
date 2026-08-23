"""ENTSO-E Transparency Platform ingestion, via the `entsoe-apy` package
(https://entsoe-apy.berrisch.biz/), NOT the older `entsoe-py`.

entsoe-apy's classes mirror the official ENTSO-E API doc sections exactly
(one class per data view) and return Pydantic models. `extract_records()`
flattens those into dotted-key dicts; `add_timestamps()` computes a real
timestamp from the period/position fields. Docs pulled and verified
2026-08-09 against entsoe-apy.berrisch.biz -- class names, parameter names,
and the DE-LU / neighbour EIC codes are all confirmed against that source.

Field names below were confirmed by cloning BerriJ/entsoe-apy and reading
the generated XML/pydantic models directly (2026-08-09), not guessed:
- Load & Generation & CrossBorderPhysicalFlows all parse into the
  `generationloaddocument` schema: value is `Point.quantity`, reached via
  `time_series.period.point.quantity`.
- Generation additionally carries `TimeSeries.mkt_psrtype.psr_type` --
  note the field is `mkt_psrtype` (no underscore before "type"), NOT
  `mkt_psr_type` as the naming convention elsewhere would suggest. Reached
  via `time_series.mkt_psrtype.psr_type`.
- EnergyPrices parses into the `publicationdocument` schema: value is
  `Point.price_amount`, reached via `time_series.period.point.price_amount`.

`_pick_column()` still matches by suffix rather than a hardcoded full path
(schema versions/response shape can still shift these), but now does exact
final-segment matching so e.g. "quantity" can't accidentally match
"secondary_quantity" (a real sibling field on the same Point model). If the
real API response doesn't match, it raises with the full column list rather
than silently picking the wrong one.
"""
from __future__ import annotations

import logging

import pandas as pd
from entsoe.Generation import ActualGenerationPerProductionType, GenerationForecastWindAndSolar
from entsoe.Load import ActualTotalLoad, DayAheadTotalLoadForecast
from entsoe.Market import EnergyPrices
from entsoe.Transmission import CrossBorderPhysicalFlows
from entsoe.utils import add_timestamps, extract_records, format_entsoe_datetime

from pipeline.config import BZN_DE_LU_EIC, NEIGHBOURS_EIC

log = logging.getLogger(__name__)


def _to_records(result) -> list[dict]:
    records = extract_records(result)
    records = add_timestamps(records)
    return records


def _pick_column(df: pd.DataFrame, suffixes: list[str]) -> str:
    """Match a column by exact final path segment(s), e.g. suffix
    "quantity" matches "time_series.period.point.quantity" but NOT
    "time_series.period.point.secondary_quantity" -- endswith() alone would
    wrongly match the latter too.
    """
    for suffix in suffixes:
        matches = [c for c in df.columns if c == suffix or c.endswith("." + suffix)]
        if matches:
            return matches[0]
    raise RuntimeError(
        f"none of the expected column suffixes {suffixes} found. "
        f"Real columns returned by the API: {list(df.columns)}. "
        "Update the suffix list in entsoe_grid.py to match."
    )


def _period(start: pd.Timestamp, end: pd.Timestamp) -> tuple[int, int]:
    return format_entsoe_datetime(start), format_entsoe_datetime(end)


def fetch_total_load(start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    """6.1.A Actual Total Load, MW, per MTU."""
    p_start, p_end = _period(start, end)
    result = ActualTotalLoad(
        out_bidding_zone_domain=BZN_DE_LU_EIC, period_start=p_start, period_end=p_end
    ).query_api()
    df = pd.DataFrame(_to_records(result))
    if df.empty:
        return pd.DataFrame(columns=["mtu_start", "actual_load_mw"])
    value_col = _pick_column(df, ["quantity", "period.point.quantity"])
    return pd.DataFrame({"mtu_start": df["timestamp"], "actual_load_mw": pd.to_numeric(df[value_col], errors="coerce")})


def fetch_day_ahead_load_forecast(start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    """6.1.B Day-Ahead Total Load Forecast, MW, per MTU."""
    p_start, p_end = _period(start, end)
    result = DayAheadTotalLoadForecast(
        out_bidding_zone_domain=BZN_DE_LU_EIC, period_start=p_start, period_end=p_end
    ).query_api()
    df = pd.DataFrame(_to_records(result))
    if df.empty:
        return pd.DataFrame(columns=["mtu_start", "forecast_load_mw"])
    value_col = _pick_column(df, ["quantity", "period.point.quantity"])
    return pd.DataFrame({"mtu_start": df["timestamp"], "forecast_load_mw": pd.to_numeric(df[value_col], errors="coerce")})


def fetch_generation_actual(start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    """16.1.B&C Actual Generation per Production Type. psr_type left unset
    to pull all types in one call -- long format: one row per (mtu, type).

    Chunked into <=90-day windows: a single 180-day request against this
    endpoint (all production types, no psr_type filter) reliably hit
    httpx.ReadTimeout after all 5 of entsoe-apy's built-in retries
    (confirmed 2026-08-20, widening from the original 90-day pull that had
    worked fine). 90 days is the largest window confirmed to succeed, so
    that's the chunk size -- not a documented ENTSO-E limit, just the
    largest known-good size for this specific endpoint's response volume.
    """
    frames = []
    chunk = pd.Timedelta(days=90)
    cur = start
    while cur < end:
        nxt = min(cur + chunk, end)
        p_start, p_end = _period(cur, nxt)
        result = ActualGenerationPerProductionType(
            period_start=p_start, period_end=p_end, in_domain=BZN_DE_LU_EIC
        ).query_api()
        df = pd.DataFrame(_to_records(result))
        if not df.empty:
            value_col = _pick_column(df, ["quantity"])
            type_col = _pick_column(df, ["mkt_psrtype.psr_type", "psr_type"])
            frames.append(
                pd.DataFrame(
                    {
                        "mtu_start": df["timestamp"],
                        "production_type": df[type_col],
                        "generation_mw": pd.to_numeric(df[value_col], errors="coerce"),
                    }
                )
            )
        cur = nxt
    if not frames:
        return pd.DataFrame(columns=["mtu_start", "production_type", "generation_mw"])
    return pd.concat(frames, ignore_index=True)


def fetch_wind_solar_forecast(start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    """14.1.D Generation Forecasts for Wind and Solar, day-ahead. Compared
    against fetch_generation_actual downstream to surface likely
    curtailment (forecast >> actual while price is near/below zero).
    """
    p_start, p_end = _period(start, end)
    result = GenerationForecastWindAndSolar(
        period_start=p_start, period_end=p_end, in_domain=BZN_DE_LU_EIC, process_type="A01"
    ).query_api()
    df = pd.DataFrame(_to_records(result))
    if df.empty:
        return pd.DataFrame(columns=["mtu_start", "production_type", "forecast_mw"])
    value_col = _pick_column(df, ["quantity"])
    type_col = _pick_column(df, ["mkt_psrtype.psr_type", "psr_type"])
    return pd.DataFrame(
        {
            "mtu_start": df["timestamp"],
            "production_type": df[type_col],
            "forecast_mw": pd.to_numeric(df[value_col], errors="coerce"),
        }
    )


def fetch_day_ahead_prices(start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    """12.1.D Energy Prices, day-ahead, EUR/MWh, per MTU. Confirmed value
    column suffix: "price_amount" (per entsoe-apy's own quick-start example).
    """
    p_start, p_end = _period(start, end)
    result = EnergyPrices(
        period_start=p_start,
        period_end=p_end,
        in_domain=BZN_DE_LU_EIC,
        out_domain=BZN_DE_LU_EIC,
        contract_market_agreement_type="A01",  # day-ahead
    ).query_api()
    df = pd.DataFrame(_to_records(result))
    if df.empty:
        return pd.DataFrame(columns=["mtu_start", "day_ahead_price_eur_mwh"])
    value_col = _pick_column(df, ["price_amount"])
    return pd.DataFrame(
        {"mtu_start": df["timestamp"], "day_ahead_price_eur_mwh": pd.to_numeric(df[value_col], errors="coerce")}
    )


def fetch_crossborder_flows(start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    """12.1.G Cross-Border Physical Flows, MW, per MTU, both directions vs.
    each tracked neighbour. Long format: one row per (mtu, neighbour, direction).
    out_domain = origin of the flow, in_domain = destination (per entsoe-apy docs).
    """
    p_start, p_end = _period(start, end)
    frames = []
    for code, eic in NEIGHBOURS_EIC.items():
        try:
            exp_result = CrossBorderPhysicalFlows(
                period_start=p_start, period_end=p_end, out_domain=BZN_DE_LU_EIC, in_domain=eic
            ).query_api()
            df = pd.DataFrame(_to_records(exp_result))
            if not df.empty:
                value_col = _pick_column(df, ["quantity", "period.point.quantity"])
                df = pd.DataFrame(
                    {"mtu_start": df["timestamp"], "flow_mw": pd.to_numeric(df[value_col], errors="coerce")}
                )
                df["neighbour"] = code
                df["direction"] = "export"
                frames.append(df)
        except Exception as exc:  # noqa: BLE001 -- log and continue, don't kill the whole pull
            log.warning("export flow DE_LU->%s failed: %s", code, exc)

        try:
            imp_result = CrossBorderPhysicalFlows(
                period_start=p_start, period_end=p_end, out_domain=eic, in_domain=BZN_DE_LU_EIC
            ).query_api()
            df = pd.DataFrame(_to_records(imp_result))
            if not df.empty:
                value_col = _pick_column(df, ["quantity", "period.point.quantity"])
                df = pd.DataFrame(
                    {"mtu_start": df["timestamp"], "flow_mw": pd.to_numeric(df[value_col], errors="coerce")}
                )
                df["neighbour"] = code
                df["direction"] = "import"
                frames.append(df)
        except Exception as exc:  # noqa: BLE001
            log.warning("import flow %s->DE_LU failed: %s", code, exc)

    if not frames:
        return pd.DataFrame(columns=["mtu_start", "flow_mw", "neighbour", "direction"])
    return pd.concat(frames, ignore_index=True)
