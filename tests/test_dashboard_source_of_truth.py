"""Locks the presentation-pass source of truth. No network or warehouse access."""

from pathlib import Path

import sqlglot

ROOT = Path(__file__).resolve().parents[1]

# Official ENTSO-E Asset Type titles B01-B20 (code list v36r0) and this
# project's category grouping. "poundage" is the code-list spelling of B11.
PSR_TYPES = [
    ("B01", "Biomass", "Renewable", 1),
    ("B02", "Fossil Brown coal/Lignite", "Fossil", 2),
    ("B03", "Fossil Coal-derived gas", "Fossil", 2),
    ("B04", "Fossil Gas", "Fossil", 2),
    ("B05", "Fossil Hard coal", "Fossil", 2),
    ("B06", "Fossil Oil", "Fossil", 2),
    ("B07", "Fossil Oil shale", "Fossil", 2),
    ("B08", "Fossil Peat", "Fossil", 2),
    ("B09", "Geothermal", "Renewable", 1),
    ("B10", "Hydro Pumped Storage", "Storage", 4),
    ("B11", "Hydro Run-of-river and poundage", "Renewable", 1),
    ("B12", "Hydro Water Reservoir", "Renewable", 1),
    ("B13", "Marine", "Renewable", 1),
    ("B14", "Nuclear", "Nuclear", 3),
    ("B15", "Other renewable", "Renewable", 1),
    ("B16", "Solar", "Renewable", 1),
    ("B17", "Waste", "Other", 5),
    ("B18", "Wind Offshore", "Renewable", 1),
    ("B19", "Wind Onshore", "Renewable", 1),
    ("B20", "Other", "Other", 5),
]

VISUAL_TITLES = [
    "Total Consumption (MWh)",
    "Mean Load (MW)",
    "Mean Peak Load (MW)",
    "Mean Off-Peak Load (MW)",
    "Consumption Trend",
    "Load Distribution",
    "Generation by Category",
    "Generation Mix by Category",
    "Load Forecast MAE (MW)",
    "Load Forecast RMSE (MW)",
    "Load Forecast MAPE (%)",
    "Day-Ahead Load Forecast vs Actual",
    "Inferred Curtailment Hours and Forecast MAE",
    "Net Cross-Border Flow by Neighbour",
    "Average Day-Ahead Price (EUR/MWh)",
    "Negative-Price Hours (period total)",
    "Negative-Price Share (period)",
    "Day-Ahead Price",
    "Day-Ahead Price vs Renewable Share",
    "Generation by Production Type (Daily Detail)",
    "Daily Fossil Share & Price (Low-Renewable-Weather Days Flagged)",
    "Fossil Drivers by Day and Night",
    "Day-Ahead Price vs Fossil Share",
]


def test_production_type_lookup_matches_entsoe_titles():
    sql = (ROOT / "sql/30_marts/10_dimensions.sql").read_text(encoding="utf-8")
    assert len(PSR_TYPES) == 20
    for code, name, category, category_sort in PSR_TYPES:
        label = f"{code} {name}"
        matches = [line for line in sql.splitlines() if f"'{label}'" in line]
        assert len(matches) == 1, label
        line = matches[0]
        assert f"'{code}'" in line
        assert f"'{name}'" in line
        assert f"'{category}'" in line
        assert str(category_sort) in line
        assert int(code[1:]) == PSR_TYPES.index((code, name, category, category_sort)) + 1


def test_partial_day_flag_keeps_rows_and_marks_edges_only():
    sql = (ROOT / "sql/30_marts/10_dimensions.sql").read_text(encoding="utf-8")
    assert "days.date = bounds.min_date OR days.date = bounds.max_date" in sql
    assert "days.load_mtu_count < days.expected_mtu_count AS is_partial_day" in sql
    assert "Europe/Brussels" in sql
    assert "DELETE FROM" not in sql.upper()
    kpis = (ROOT / "sql/30_marts/30_kpis.sql").read_text(encoding="utf-8")
    assert "DELETE FROM" not in kpis.upper()
    assert "is_partial_day" in kpis
    assert "production_type_name" in kpis
    assert "AVG(ABS(f.forecast_error_mw)) AS mae_mw" in kpis
    assert "COUNTIF(f.actual_mw < f.forecast_mw * 0.8 AND p.day_ahead_price_eur_mwh <= 0)" in kpis
    assert "SAFE_DIVIDE(SUM(fossil_mw), SUM(total_mw)) AS fossil_share_pct" in kpis


def test_measures_average_shares_and_declare_formats():
    dax = (ROOT / "powerbi/measures.dax").read_text(encoding="utf-8")
    assert "Generation Mix Share % =" in dax
    assert "Format: 0.00%" in dax
    assert "Fossil Share % = AVERAGE ( kpi_fossil_drivers_daily[fossil_share_pct] )" in dax
    assert "SUM ( kpi_fossil_drivers_daily[fossil_share_pct] )" not in dax
    assert "Mean Load (MW) = AVERAGE ( kpi_load_distribution_raw[actual_load_mw] )" in dax
    assert "Load Forecast RMSE (MW) =" in dax
    assert "Load Forecast MAE (MW) =" in dax


def test_marts_sql_parses_as_bigquery():
    for relative in (
        "sql/30_marts/10_dimensions.sql",
        "sql/30_marts/20_facts.sql",
        "sql/30_marts/30_kpis.sql",
    ):
        statements = sqlglot.parse((ROOT / relative).read_text(encoding="utf-8"), read="bigquery")
        assert statements
        assert all(statement is not None for statement in statements)


def test_dashboard_spec_titles_are_closed_and_sliced():
    spec = (ROOT / "powerbi/DASHBOARD_SPEC.md").read_text(encoding="utf-8")
    for title in VISUAL_TITLES:
        assert title in spec, title
    for header in ("Date", "Category", "Production type", "Neighbour", "Low-renewable day"):
        assert header in spec
    assert "dim_date[date]" in spec
    assert "Date Hierarchy" in spec
    assert "is_partial_day" in spec
    assert "0.00%" in spec
