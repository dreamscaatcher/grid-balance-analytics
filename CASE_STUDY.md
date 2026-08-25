# German Grid Balance Intelligence: Case Study

## Problem

I built a data tool using real weather and power grid facts to show exactly how green energy changes electricity supply and prices in Germany. The dashboard covers the DE-LU bidding zone from February to August 2026, built entirely on real ENTSO-E Transparency Platform and DWD weather data, with no synthetic numbers anywhere.

## Architecture & trade-offs

Python ingestion (ENTSO-E + DWD open data) lands raw data in BigQuery, flows through a staging layer for typing and deduplication, into a marts layer with a star schema and a set of purpose-built KPI views. Power BI reads only from marts, never raw or staging. I deliberately kept several KPI views self-contained (denormalized) rather than relying on Power BI relationships, after hitting an ambiguous-relationship-path error trying to activate a legitimate `fact_generation → dim_production_type` relationship, blocked by an existing indirect path through another table. Remodeling the whole schema mid-build was a real temptation in the moment. Instead I stuck to the workaround, kept building, and logged the proper fix as a follow-up rather than letting it stall the deliverable.

## What I'd do differently at scale

Two things. First, the schema needs a genuine remodel: resolve the ambiguous relationship path properly instead of leaning on denormalized shortcut fields, workable for one dashboard, not workable as the model grows. Second, my storage-vs-fossil investigation below only checked 2 of the 4 low-renewable-weather days the dataset actually flags; at scale I'd run it as a structured test across every flagged day, and across multiple seasons, before treating the pattern as more than a hypothesis.

## Measured outcome

Two findings, each stated at the confidence the data actually supports, not beyond it. On the two low-renewable-weather days examined, storage generation was markedly elevated versus nearby comparable days: 35,879 MWh (3.46% of that day's generation mix) versus 2,839 MWh (0.28%) the day before, and a comparable gap on the second flagged day. That's consistent with a "storage picks up the slack" pattern, but with n=2 it's a hypothesis worth testing at scale, not a conclusion. Separately, summed across its 8 tracked interconnections for the February to August 2026 window, Germany's net cross-border flow was negative (-3.15M MWh), a net importer over this specific period and set of borders, not a general claim about its year-round trade position.

Building this also meant catching my own mistakes before they shipped: two Sum-vs-Average aggregation bugs (one of them a regression that reappeared after a rebuild) and a field-source mix-up between two visuals were all caught and fixed through a deliberate QA pass, rather than assumed correct because a chart "looked right" at a glance. That's the same discipline the findings above are held to.
