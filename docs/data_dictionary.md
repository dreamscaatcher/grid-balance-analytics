# Data Dictionary

## Sources

| Field group | Source | Real / Derived |
|---|---|---|
| Total load (actual, day-ahead forecast) | ENTSO-E Transparency Platform, `query_load` / `query_load_forecast` | Real |
| Generation by production type (actual) | ENTSO-E Transparency Platform, `query_generation` | Real |
| Wind/solar generation forecast | ENTSO-E Transparency Platform, `query_wind_and_solar_forecast` | Real |
| Day-ahead price | ENTSO-E Transparency Platform, `query_day_ahead_prices` | Real |
| Cross-border physical flows | ENTSO-E Transparency Platform, `query_crossborder_flows` | Real |
| Wind speed, sunshine duration | DWD Open Data (CDC), hourly station observations | Real |
| Forecast error, MAE/RMSE, curtailment signal, renewable share, negative-price hours | Computed in `sql/30_marts/30_kpis.sql` | Derived from real data |

No synthetic data in this project -- unlike rail-ops-analytics, there's no commercial-confidentiality gap to work around; ENTSO-E and DWD both publish real, measured figures.

## Bidding zone

**DE-LU** (Germany-Luxembourg), EIC code `10Y1001A1001A82H`. Confirmed against ENTSO-E's Area List. Merged from the former DE-AT-LU zone in 2018 when Austria split off.

## Curtailment signal -- caveat

`kpi_renewable_forecast_accuracy.likely_curtailment_hours` is an **inference**, not a directly reported figure: hours where actual wind/solar generation fell materially (>20%) below the day-ahead forecast while the day-ahead price was at or below zero. ENTSO-E does not publish a direct "curtailment" field for Germany at this granularity -- this flags the pattern you'd expect if a grid operator throttled output, but a low reading could also reflect the forecast simply being wrong for weather reasons unrelated to grid congestion. Label as inferred wherever it appears on the dashboard.

## Production type codes (`dim_production_type`)

**Correction (2026-08-09):** an earlier draft of this pipeline assumed ENTSO-E generation data would arrive wide (one column per human-readable type name like "Wind Onshore") and needed an `UNPIVOT` in staging. That was wrong. Confirmed by cloning `BerriJ/entsoe-apy` and reading its generated model source directly: `production_type` is a **PSR code** (`AssetTypeList` enum, e.g. `B19 = "B19"` -- the enum value is the code itself, not the description), and the data already arrives **long** (one row per MTU per type) straight out of `pipeline/ingest/entsoe_grid.py`. `sql/20_staging/staging.sql` is now a plain typed pass-through, no `UNPIVOT`.

| Code | Production type | Category |
|---|---|---|
| B01 | Biomass | Renewable |
| B02 | Fossil Brown coal/Lignite | Fossil |
| B03 | Fossil Coal-derived gas | Fossil |
| B04 | Fossil Gas | Fossil |
| B05 | Fossil Hard coal | Fossil |
| B06 | Fossil Oil | Fossil |
| B07 | Fossil Oil shale | Fossil |
| B08 | Fossil Peat | Fossil |
| B09 | Geothermal | Renewable |
| B10 | Hydro Pumped Storage | Storage |
| B11 | Hydro Run-of-river and poundage | Renewable |
| B12 | Hydro Water Reservoir | Renewable |
| B13 | Marine | Renewable |
| B14 | Nuclear | Nuclear |
| B15 | Other renewable | Renewable |
| B16 | Solar | Renewable |
| B17 | Waste | Other |
| B18 | Wind Offshore | Renewable |
| B19 | Wind Onshore | Renewable |
| B20 | Other | Other |

This is the full standard ENTSO-E PSR type list -- Germany won't populate every row (e.g. B08 Fossil Peat, B13 Marine are not present in the DE generation mix); those codes simply won't appear in `grid_raw.generation_actual` and any join against them returns nothing, which is fine.

## Known open items

- Cross-border neighbour list (`FR, NL, BE, AT, CH, CZ, PL, DK_1`) covers DE-LU's major direct interconnections but is not exhaustive (e.g. Sweden/Norway subsea links excluded for scope).
- DWD station list is a first pass (5 stations spread across Germany) -- may want to expand or reweight once wind/solar generation patterns are visible, to better match where German wind/solar capacity is actually concentrated (e.g. more wind capacity in the north).
