# Metabase — Dashboard Queries

Paste-ready queries for the Metabase dashboard (Kap. 7 of the Bericht). Two
sources, one dashboard:

- `mongodb_native_queries.md` — MongoDB **Native Query** pipelines (paste the
  JSON array). Source DB: MongoDB → `ev_project`.
- `mysql_queries.sql` — MySQL dashboard queries (decision KPI + TCO-over-time).
  Source DB: MySQL → `ev_project`.

## Connection

Metabase instance + DB credentials live in the repo-root `.env` (gitignored).
In Metabase: **Admin → Databases → Add** one MySQL and one MongoDB connection,
both pointing at database `ev_project`.

## Canonical result (verified SQL == MongoDB, 4 decimals, ref. year 2022)

| country | ice €/km | ev €/km | ev CO₂ g/km | ice CO₂ g/km | recommend_ev |
|---------|----------|---------|-------------|--------------|--------------|
| CH | 0.1740 | 0.0375 | 6.91  | 235 | 1 |
| DE | 0.1810 | 0.0684 | 77.84 | 235 | 1 |
| FR | 0.1775 | 0.0470 | 14.57 | 235 | 1 |

EV recommended in all three countries: ev cost/km is far below the 110 % ICE
threshold, and ev CO₂/km is below the ICE fleet (235 g/km) everywhere.

## Decision rule

Recommend a BEV when **both** hold:
1. `ev_cost_per_km ≤ 1.10 × ice_cost_per_km`
2. `ev_co2_per_km ≤ ice_co2_per_km`

ICE fleet = Petrol + Diesel only (n=3812); ICE cost/km uses the mean of the
national petrol & diesel price.

## Panels

| Panel | Source | Query |
|-------|--------|-------|
| Decision KPI (table/bar) | MySQL or Mongo | SQL Q1 / MQL Q1 |
| TCO over N years (line) | MySQL | SQL Q2 |
| Cost €/km EV vs ICE (bar) | Mongo | MQL Q1b |
| CO₂ g/km EV vs ICE (bar) | Mongo | MQL Q1c |
| Grid CO₂ intensity over time | Mongo | MQL Q2 |
| Electricity price trend | Mongo | MQL Q3 |
| EV adoption trend | Mongo | MQL Q4 |
| Charging infrastructure | Mongo | MQL Q5 |
| Grid mix 2022 (stacked bar) | Mongo | MQL Q6 |

> **Caveat (TCO query):** purchase prices in `v_ev_tco_base` are fleet-median
> `price_usd` (USD), while cost/km is EUR — the TCO total mixes currencies and
> uses one purchase price for all three countries (no country pricing/subsidies).
> Treat the TCO chart as indicative. The headline decision (cost/km + CO₂/km) is
> the rigorous part.
