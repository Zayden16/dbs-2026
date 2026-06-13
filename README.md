# Are EVs Really Better?

DBS project (HSLU, FS2026) — Team Real Team 1. A data-backed buy/don't-buy
decision system comparing **Total Cost of Ownership** and **CO₂ emissions** of
battery-electric (BEV) vs. internal-combustion (ICE) vehicles across
**Switzerland, Germany and France**.

The same data is modelled in **MySQL** (3NF) and **MongoDB** (denormalised),
analysed in both, and visualised in **Metabase** — so the relational and
document approaches can be compared on one use case.

## Repository layout

| Path | Contents |
|------|----------|
| `datasets/` | 10 source CSVs from 8 independent publishers (~624k rows); `dqa/` holds per-dataset data-quality analysis |
| `sql/` | MySQL: schema (3NF), ER model, canonical EV-vs-ICE decision query |
| `mongodb/` | MongoDB: schema validators, import, transform, analytics, performance, Metabase queries |

```
sql/
  01_quelldatenanalyse.md          source-data analysis
  02_er_model.txt                  ER model notes
  03_schema.sql                    DDL — 9 target tables (3NF) + staging
  04_model_to_schema_mapping.txt   source → schema mapping
  05_ev_ice_decision_canonical.sql canonical analytics query (reconciled with MongoDB)

mongodb/
  01_schema_prototypes.js          $jsonSchema validators for 4 collections
  02_mongoimport.sh                load 10 CSVs into stg_* collections
  03_transform.js                  ELT transform → 4 denormalised collections
  04_analytics.js                  EV-vs-ICE decision pipeline
  05_performance.js                explain / index / materialized-view benchmarks
  06_metabase_queries.js           dashboard query library
```

## Setup

Credentials live in `.env` (gitignored). Copy the template and fill in:

```bash
cp .env.example .env
# edit .env with the Railway MySQL / MongoDB / Metabase credentials
```

## Running

**MongoDB** (scripts read `MONGO_URI` from `.env`):

```bash
cd mongodb
bash 02_mongoimport.sh                       # load staging
mongosh "$MONGO_URI" 01_schema_prototypes.js
mongosh "$MONGO_URI" 03_transform.js
mongosh "$MONGO_URI" 04_analytics.js
mongosh "$MONGO_URI" 05_performance.js
```

**MySQL**:

```bash
mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
  ev_project < sql/03_schema.sql
mysql ... ev_project < sql/05_ev_ice_decision_canonical.sql
```

## Decision rule

Recommend a BEV when **both** hold (reference year 2022):
1. BEV cost/km ≤ 1.10 × ICE cost/km
2. BEV CO₂/km ≤ ICE CO₂/km

ICE fleet = Petrol + Diesel only; ICE cost/km uses the mean of national petrol &
diesel prices. The MySQL and MongoDB pipelines use an identical methodology and
produce identical results.
