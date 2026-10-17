# Power BI Dashboard Spec

Build checklist for the German Grid Balance Intelligence report (DE-LU, ENTSO-E + DWD, February–August 2026). The warehouse already holds the rows. This file is the source of truth for how the report looks and which fields it binds. Apply it in Power BI Desktop after the marts refresh below. Do not recompute MAE, RMSE, MAPE, shares, or MWh in DAX; `powerbi/measures.dax` only aggregates the KPI views.

Canvas for every page: **1280 × 720**, type 16:9. Positions below are pixels from the top-left of the canvas. Gap and page margin are 16 px. Visual background white, shadow off, border off. Title font 12 pt. With those widths the titles fit on one line, including the closing parenthesis.

## 0. Refresh the marts, then the model

Run these three scripts in order against `grid-analysis-505021`, location `EU` (the `bq` CLI defaults to US):

1. `sql/30_marts/10_dimensions.sql`
2. `sql/30_marts/20_facts.sql`
3. `sql/30_marts/30_kpis.sql`

Then in Power BI: Home → Refresh. Import mode. Dataset `grid_marts` only.

Import these tables:

| Table | Role |
|---|---|
| `dim_date` | Date axis, date slicer, partial-day filter, low-renewable slicer |
| `dim_production_type` | Category and production-type slicers, legend names |
| `dim_neighbour` | Neighbour slicer and cross-border legend |
| `kpi_total_consumption_daily` | Consumption |
| `kpi_load_distribution_raw` | Load distribution and mean-load cards |
| `kpi_energy_mix_daily` | Generation mix |
| `kpi_load_forecast_accuracy` | Forecast vs actual, MAE, RMSE, MAPE |
| `kpi_renewable_forecast_accuracy` | Inferred curtailment combo |
| `kpi_crossborder_net_flow_daily` | Cross-border flows |
| `kpi_price_stats_daily` | Price line and negative-price cards |
| `kpi_price_vs_renewable_share` | Price vs renewable share |
| `kpi_fossil_drivers_daily` | Page 4 |

Leave `fact_*`, `kpi_mean_load`, `kpi_total_consumption_summary`, `kpi_energy_mix_share`, and `kpi_load_profile_by_hour` out of the model. The three KPI views are period aggregates; a card built on their columns shows "Sum of mean_load_mw" and a donut centre of 1.00.

File → Options → Current file → Data Load → Time intelligence → **Auto date/time off**. Model view → `dim_date` → **Mark as date table** on `date`.

## 1. Model

Relationships are many-to-one, single direction, from the dimension to the KPI view.

| From | To |
|---|---|
| `dim_date[date]` | `kpi_total_consumption_daily[date]` |
| `dim_date[date]` | `kpi_load_distribution_raw[date]` |
| `dim_date[date]` | `kpi_energy_mix_daily[date]` |
| `dim_date[date]` | `kpi_load_forecast_accuracy[date]` |
| `dim_date[date]` | `kpi_renewable_forecast_accuracy[date]` |
| `dim_date[date]` | `kpi_crossborder_net_flow_daily[date]` |
| `dim_date[date]` | `kpi_price_stats_daily[date]` |
| `dim_date[date]` | `kpi_price_vs_renewable_share[date]` |
| `dim_date[date]` | `kpi_fossil_drivers_daily[date]` |
| `dim_production_type[production_type]` | `kpi_energy_mix_daily[production_type]` |
| `dim_production_type[production_type]` | `kpi_renewable_forecast_accuracy[production_type]` |
| `dim_neighbour[neighbour]` | `kpi_crossborder_net_flow_daily[neighbour]` |

Sort by column:

| Column | Sort by |
|---|---|
| `dim_production_type[production_type_name]` | `type_sort` |
| `dim_production_type[category]` | `category_sort` |
| `dim_neighbour[neighbour_name]` | `neighbour_sort` |
| `kpi_energy_mix_daily[production_type_name]` | `type_sort` |
| `kpi_energy_mix_daily[category]` | `category_sort` |
| `kpi_renewable_forecast_accuracy[production_type_name]` | `type_sort` |

Hide in report view:

- `dim_date[day_of_month]`, `dim_date[load_mtu_count]`, `dim_date[expected_mtu_count]`
- `kpi_energy_mix_daily[production_type]` (the code; the name is the legend)

Share columns are 0–1 ratios. Set the default summarization to **Average** (so a table total cannot sum them past 1) and the format to **Percentage**.

| Column | Display name | Summarization | Format |
|---|---|---|---|
| `kpi_price_vs_renewable_share[renewable_share_pct]` | Renewable share | Average | `0.00%` |
| `kpi_fossil_drivers_daily[fossil_share_pct]` | Fossil share | Average | `0.00%` |
| `kpi_price_vs_renewable_share[avg_price_eur_mwh]` | Day-ahead price (EUR/MWh) | Average | `#,0.00` |
| `kpi_fossil_drivers_daily[avg_price_eur_mwh]` | Price (EUR/MWh) | Average | `#,0.00` |
| `dim_date[low_renewable_day_label]` | Low-renewable day | — | text |
| `kpi_fossil_drivers_daily[low_renewable_day_label]` | Low-renewable day | — | text |
| `kpi_fossil_drivers_daily[day_night]` | Day / Night | — | text |
| `kpi_fossil_drivers_daily[date]` | Date | — | `YYYY-MM-DD` |

Category colours, set on any visual whose legend is `dim_production_type[category]`:

| Category | Colour |
|---|---|
| Renewable | `#2E7D32` |
| Fossil | `#6D4C41` |
| Nuclear | `#6A1B9A` |
| Storage | `#1565C0` |
| Other | `#757575` |

Paste measures from `powerbi/measures.dax`. Set each measure's **Format** property to the `Format:` comment above it. Display units = **None** on every measure and every visual. If the pbix still has `Generation Share of Total`, `Total Consumption Trend (MWh)`, or `Load Distribution HTML`, delete those three.

Calculated column on `kpi_load_distribution_raw`:

```dax
Load Bin (MW) = INT ( kpi_load_distribution_raw[actual_load_mw] / 2000 ) * 2000
```

## 2. Chrome on every page

Page names, in this order. Delete any extra blank tab (a second "Grid Bal Ops" page has shown up before).

1. Executive Overview
2. Grid Balance Operations
3. Price View
4. Fossil Fuel Drivers

Page title sits at x=16, y=12, w=600, h=28, 18 pt semibold, and uses the page name.

Slicers, same position and same sync group on all four pages. Header on, header font 10 pt. Dropdowns are multi-select with Select all. The report opens with every slicer on Select all. The partial-day filter below is what keeps the short edge day off the canvas.

| Slicer header | Field | Style | x | y | w | h |
|---|---|---|---|---|---|---|
| Date | `dim_date[date]` | Between | 16 | 44 | 280 | 72 |
| Category | `dim_production_type[category]` | Dropdown | 312 | 44 | 200 | 72 |
| Production type | `dim_production_type[production_type_name]` | Dropdown | 528 | 44 | 240 | 72 |
| Neighbour | `dim_neighbour[neighbour_name]` | Dropdown | 784 | 44 | 220 | 72 |
| Low-renewable day | `dim_date[low_renewable_day_label]` | Dropdown | 1020 | 44 | 244 | 72 |

View → Sync slicers: each of the five is synced and visible on all four pages.

Filters on **all pages**: `dim_date[is_partial_day]` is False. This is a filter, not a slicer. The partial first or last day stays in the table; clearing this one filter puts it back on the charts. That is the consumption-trend dip at the start of the window.

What each slicer reaches, through the relationships above:

| Slicer | Visuals it filters |
|---|---|
| Date | Every visual on every page |
| Low-renewable day | Every visual on every page (the flag is on the date) |
| Category, Production type | Generation mix, donut, curtailment combo, generation-by-type chart |
| Neighbour | Net cross-border chart |

Daily chart axis, every time series on every page:

- Field: `dim_date[date]`
- Field menu reads **Date**, not **Date Hierarchy**
- Axis type: **Continuous**
- Axis title: `Date`

The live charts put the Day level of the auto date hierarchy on the axis. That sums every 1st together and every 31st together. In February–August 2026 the 31st exists only in May, July, and August, so the column drops. `day_of_month` is hidden so it does not go back on an axis.

## 3. Page 1 — Executive Overview

Four cards, then two chart rows. Card setup for every card on this page: visual title = the string below, 12 pt; category label off (that subtitle is the "Sum of mean_load_mw" line); display units None.

| Title | x | y | w | h |
|---|---|---|---|---|
| Total Consumption (MWh) | 16 | 132 | 300 | 100 |
| Mean Load (MW) | 332 | 132 | 300 | 100 |
| Mean Peak Load (MW) | 648 | 132 | 300 | 100 |
| Mean Off-Peak Load (MW) | 964 | 132 | 300 | 100 |

| Title | Measure | Format |
|---|---|---|
| Total Consumption (MWh) | `Total Consumption (MWh)` | `#,0` |
| Mean Load (MW) | `Mean Load (MW)` | `#,0.0` |
| Mean Peak Load (MW) | `Mean Peak Load (MW)` | `#,0.0` |
| Mean Off-Peak Load (MW) | `Mean Off-Peak Load (MW)` | `#,0.0` |

### Consumption Trend

| | |
|---|---|
| Title | Consumption Trend |
| Visual | Line chart |
| Position | x=16, y=248, w=760, h=220 |
| X-axis | `dim_date[date]`, continuous. Axis title `Date` |
| Y-axis | `Total Consumption (MWh)`. Axis title `Consumption (MWh)`. Display units None |
| Format | `#,0` |

### Load Distribution

| | |
|---|---|
| Title | Load Distribution |
| Visual | Clustered column chart |
| Position | x=792, y=248, w=472, h=220 |
| X-axis | `Load Bin (MW)`, categorical, sorted ascending. Axis title `Load (MW)` |
| Y-axis | Count of `kpi_load_distribution_raw[actual_load_mw]`. Axis title `Quarter-hours` |
| Bin | The calculated column in section 1. Native column chart only |

### Generation by Category

| | |
|---|---|
| Title | Generation by Category |
| Visual | Stacked area chart |
| Position | x=16, y=484, w=760, h=220 |
| X-axis | `dim_date[date]`, continuous. Axis title `Date` |
| Y-axis | `Generation (MWh)`. Axis title `Generation (MWh)`. Display units None |
| Legend | `dim_production_type[category]`, colours from section 1 |
| Format | `#,0` |

### Generation Mix by Category

| | |
|---|---|
| Title | Generation Mix by Category |
| Visual | Donut chart |
| Position | x=792, y=484, w=472, h=220 |
| Legend | `dim_production_type[category]`, colours from section 1 |
| Values | `Generation Mix Share %` |
| Detail labels | On. Contents: **Data value** only |
| Total label / centre | Off |
| Format | `0.00%` |
| Tooltip | `Generation (MWh)` |

A slice label reads `65.06%`. It does not read `0.6505833027227442 (65.06%)`, and the hole in the middle is empty. Those two came from putting the 0–1 column `share_of_total` on the donut (Sum, plus Power BI's own percent, plus a centre total of 1). The centre stays off because a total of 100% does not add a fact.

## 4. Page 2 — Grid Balance Operations

Three cards. Same card rules as page 1 (title 12 pt, category label off, display units None). The space before `(MW)` is part of the title.

| Title | Measure | Format | x | y | w | h |
|---|---|---|---|---|---|---|
| Load Forecast MAE (MW) | `Load Forecast MAE (MW)` | `#,0.0` | 16 | 132 | 405 | 100 |
| Load Forecast RMSE (MW) | `Load Forecast RMSE (MW)` | `#,0.0` | 437 | 132 | 405 | 100 |
| Load Forecast MAPE (%) | `Load Forecast MAPE (%)` | `#,0.00` | 858 | 132 | 406 | 100 |

MAPE is already a 0–100 number in SQL. The format is `#,0.00`, not a percent format.

### Day-Ahead Load Forecast vs Actual

| | |
|---|---|
| Title | Day-Ahead Load Forecast vs Actual |
| Visual | Line chart |
| Position | x=16, y=248, w=1248, h=220 |
| X-axis | `dim_date[date]`, continuous. Axis title `Date` |
| Y-axis | `Actual Load (MW)` and `Forecast Load (MW)`. Axis title `Load (MW)`. Display units None |
| Series | Actual solid `#1565C0`. Forecast dashed `#EF6C00` |
| Format | `#,0.0` |

### Inferred Curtailment Hours and Forecast MAE

| | |
|---|---|
| Title | Inferred Curtailment Hours and Forecast MAE |
| Subtitle | Inferred: actual generation under 80% of the day-ahead forecast while the price is at or below zero. Quarter-hour MTUs, not a reported curtailment figure. |
| Visual | Line and clustered column chart |
| Position | x=16, y=484, w=760, h=220 |
| Shared axis | `dim_date[date]`, continuous. Axis title `Date` |
| Columns | `Likely Curtailment Hours`. Axis title `Inferred curtailment (quarter-hours)` |
| Line | `Renewable Forecast MAE (MW)`, secondary axis. Axis title `Forecast MAE (MW)` |
| Legend | `dim_production_type[production_type_name]` |
| Formats | Hours `#,0`. MAE `#,0.0` |

The visual title is the sentence above. Power BI's automatic title "Sum of likely_curtailment_hours and Average of mae_mw" stays off (Title = On, text set by hand).

### Net Cross-Border Flow by Neighbour

| | |
|---|---|
| Title | Net Cross-Border Flow by Neighbour |
| Subtitle | Positive is net export. Negative is net import. |
| Visual | Line chart |
| Position | x=792, y=484, w=472, h=220 |
| X-axis | `dim_date[date]`, continuous. Axis title `Date` |
| Y-axis | `Net Export (MWh)`. Axis title `Net export (MWh)`. Display units None |
| Legend | `dim_neighbour[neighbour_name]`. Legend title `Neighbour` |
| Format | `#,0.0` |

## 5. Page 3 — Price View

Three cards, then a full-width line, then a full-width scatter. Same card rules as page 1. The negative-price title includes the closing parenthesis; the card is 405 px wide so the parenthesis is visible.

| Title | Measure | Format | x | y | w | h |
|---|---|---|---|---|---|---|
| Average Day-Ahead Price (EUR/MWh) | `Avg Day-Ahead Price (EUR/MWh)` | `#,0.00` | 16 | 132 | 405 | 100 |
| Negative-Price Hours (period total) | `Negative Price Hours` | `#,0` | 437 | 132 | 405 | 100 |
| Negative-Price Share (period) | `Negative Price Hours %` | `0.00%` | 858 | 132 | 406 | 100 |

### Day-Ahead Price

| | |
|---|---|
| Title | Day-Ahead Price |
| Visual | Line chart |
| Position | x=16, y=248, w=1248, h=220 |
| X-axis | `dim_date[date]`, continuous. Axis title `Date` |
| Y-axis | `Avg Day-Ahead Price (EUR/MWh)`. Axis title `Price (EUR/MWh)`. Display units None |
| Analytics | Constant line at value `0`. Label `EUR 0/MWh`. Colour `#616161` |
| Tooltips | `Min Day-Ahead Price (EUR/MWh)`, `Max Day-Ahead Price (EUR/MWh)`, `Price Volatility (StdDev)` |
| Format | `#,0.00` |

### Day-Ahead Price vs Renewable Share

| | |
|---|---|
| Title | Day-Ahead Price vs Renewable Share |
| Visual | Scatter chart |
| Position | x=16, y=484, w=1248, h=220 |
| X-axis | `avg_price_eur_mwh`, summarization **Don't summarize**. Axis title `Day-ahead price (EUR/MWh)` |
| Y-axis | `renewable_share_pct`, summarization **Don't summarize**. Axis title `Renewable share (%)` |
| Legend | None. Date stays out of the legend |
| Tooltips | `dim_date[date]` |
| Formats | Price `#,0.00`. Share `0.00%` (column format from section 1) |

The view has one row per date, and Don't summarize plots that row. A measure on both axes, with no field to split the points, would draw a single dot for the whole period. The percent format is what turns 0.65 into 65%. Title is on. The automatic title stays off.

## 6. Page 4 — Fossil Fuel Drivers

No card row. A 2×2 grid fills the page under the slicers. Both charts use `dim_date[date]`, continuous, axis title `Date`.

| Title | x | y | w | h |
|---|---|---|---|---|
| Generation by Production Type (Daily Detail) | 16 | 132 | 616 | 278 |
| Daily Fossil Share & Price (Low-Renewable-Weather Days Flagged) | 648 | 132 | 616 | 278 |
| Fossil Drivers by Day and Night | 16 | 426 | 616 | 278 |
| Day-Ahead Price vs Fossil Share | 648 | 426 | 616 | 278 |

The two long titles include the closing parenthesis. At 12 pt they fit inside 616 px. Title wrap off.

### Generation by Production Type (Daily Detail)

| | |
|---|---|
| Title | Generation by Production Type (Daily Detail) |
| Visual | Stacked column chart |
| X-axis | `dim_date[date]`, continuous. Axis title `Date` |
| Y-axis | `Generation (MWh)`. Axis title `Generation (MWh)`. Display units None |
| Legend | `dim_production_type[production_type_name]` |
| Tooltip | `dim_production_type[production_type_label]` |
| Format | `#,0` |

The legend reads Biomass, Fossil Brown coal/Lignite, Wind Onshore, and the other official names. It does not read B01, B02, B19.

### Daily Fossil Share & Price (Low-Renewable-Weather Days Flagged)

| | |
|---|---|
| Title | Daily Fossil Share & Price (Low-Renewable-Weather Days Flagged) |
| Subtitle | Orange columns are low-renewable-weather days: bottom-quartile wind and bottom-quartile sunshine. This is not a pressure reading. |
| Visual | Line and clustered column chart |
| Columns | `Fossil Share %`. Axis title `Fossil share (%)`. Colour: field value `Low-Renewable Day Colour` |
| Line | `Fossil Driver Avg Price (EUR/MWh)` on the **secondary** axis. Axis title `Price (EUR/MWh)`. Colour `#1565C0` |
| Shared axis | `dim_date[date]`, continuous. Axis title `Date` |
| Formats | Share `0.00%`. Price `#,0.00` |

Column colours: Format pane → Columns → Colors → fx → Format style **Field value** → `Low-Renewable Day Colour`. Orange `#E65100` is a flagged day. Brown `#6D4C41` is every other day.

### Fossil Drivers by Day and Night

| | |
|---|---|
| Title | Fossil Drivers by Day and Night |
| Visual | Table |
| Total row | On |
| Column width | Low-renewable day at least 160 px, so the header is fully visible |

Columns, left to right. The share value is the measure `Fossil Share %`, not the column. Dropping `fossil_share_pct` with Sum is what produced shares above 1 and a meaningless total. The column's default summarization is Average anyway; the measure is what this table uses.

| Header | Field | Format |
|---|---|---|
| Date | `kpi_fossil_drivers_daily[date]`, shown as a date, not a date hierarchy | Short date `YYYY-MM-DD` |
| Day / Night | `day_night` | text |
| Fossil generation (MWh) | `Fossil Generation (MWh)` | `#,0` |
| Fossil share | `Fossil Share %` | `0.00%` |
| Wind (m/s) | `Avg Wind Speed (m/s)` | `#,0.00` |
| Sunshine (min) | `Avg Sunshine (min)` | `#,0.0` |
| Low-renewable day | `low_renewable_day_label` | text |
| Price (EUR/MWh) | `Fossil Driver Avg Price (EUR/MWh)` | `#,0.00` |

The total row evaluates the measures: generation sums, and fossil share averages. The share total is a percent at or under 100%.

### Day-Ahead Price vs Fossil Share

| | |
|---|---|
| Title | Day-Ahead Price vs Fossil Share |
| Visual | Scatter chart |
| X-axis | `avg_price_eur_mwh`, summarization **Don't summarize**. Axis title `Day-ahead price (EUR/MWh)` |
| Y-axis | `fossil_share_pct`, summarization **Don't summarize**. Axis title `Fossil share (%)` |
| Legend | `low_renewable_day_label`. Legend title `Low-renewable day` |
| Tooltips | `date`, `day_night` |
| Formats | Price `#,0.00`. Share `0.00%` |

Title is on, set to the string above. Don't summarize plots each day and night row (two points per date, same price, different share). The table is where `Fossil Share %` averages those shares, including on the total row.

## 7. Acceptance checklist

After refresh, with the all-pages partial-day filter on and every slicer on Select all:

1. Donut labels look like `65.06%`. The centre is empty. The open slices add to 100%.
2. Mean-load cards have no subtitle "Sum of mean_load_mw". Titles are `Mean Load (MW)`, `Mean Peak Load (MW)`, and `Mean Off-Peak Load (MW)`.
3. Units on titles read `MWh`, `MW`, and `EUR/MWh`. Display units are None, so a total does not pick up an auto "M" or "MWH".
4. Consumption Trend has no one-day dip on the first date. Clearing the `is_partial_day` filter brings that date back.
5. No time series is plotted by day-of-month. The 31st is three points (May, July, August), not one short column.
6. Curtailment visual title is `Inferred Curtailment Hours and Forecast MAE`, and its subtitle calls the hours inferred.
7. MAE card title is `Load Forecast MAE (MW)`. RMSE card title is `Load Forecast RMSE (MW)`, with a space before the parenthesis.
8. Page 3 card title is `Negative-Price Hours (period total)`, parenthesis included.
9. Renewable-share axis reads percent, not a raw decimal.
10. Page 4 titles end with `)`. Production-type legend shows official names. The fossil table has no column header starting `is_low_renewable_we`, and its share column and total are percents at or under 100%.
11. All four pages show the five slicers: Date, Category, Production type, Neighbour, Low-renewable day.
12. Category filter changes the generation charts and leaves the price line's shape to the date and low-renewable slicers. Neighbour filter changes the cross-border lines.

`kpi_energy_mix_share` in BigQuery is still the full-period mix, partial edge included. The donut follows the page filter, so its slices can differ from that view by the partial day. That is the filter, not a second formula.
