# Quelldatenanalyse (Source Data Analysis)

**Project:** "Are EVs Really Better?"
**Focus:** CH, DE, FR — comparing EV vs ICE total cost & CO2 impact

**8 independent data sources, 10 datasets total.**

---

## Source 1: Kaggle — Car Specs & Prices (abdulmalik1518)

**Publisher:** Kaggle user abdulmalik1518
**URL:** https://www.kaggle.com/datasets/abdulmalik1518/cars-datasets-2025

**Dataset:** `Cars Datasets 2025.csv` — 1,218 rows, 11 columns
**Content:** Global car specifications including both ICE and Electric vehicles
**Structure:** Flat table, one row per car model

**Key fields:**

| Field | Type | Description |
|-------|------|-------------|
| Company Names | TEXT | Manufacturer, 35 unique (FERRARI, BMW, Tesla, etc.) |
| Cars Names | TEXT | Model name, 1,200 unique |
| Engines | TEXT | Engine description ("V8", "Electric Motor", etc.) |
| CC/Battery Capacity | TEXT | "3990 cc" for ICE, "75 kWh" for EV |
| HorsePower | TEXT | "963 hp" — units embedded |
| Total Speed | TEXT | "340 km/h" — units embedded |
| Cars Prices | TEXT | "$460,000" or ranges "$10,000 - $12,000" |
| Fuel Types | TEXT | 23 types incl. "Electric", "Diesel", "Petrol", "Hybrid" |
| Seats | TEXT | Number of seats |
| Torque | TEXT | "800 Nm" — units embedded |

**Example row:**
`FERRARI | SF90 STRADALE | V8 | 3990 cc | 963 hp | 340 km/h | $1,100,000 | plug in hybrid`

---

## Source 2: Kaggle — Vehicle CO2 Emissions (brsahan)

**Publisher:** Kaggle user brsahan
**URL:** https://www.kaggle.com/datasets/brsahan/vehicle-co2-emissions-dataset

**Dataset:** `co2.csv` — 7,385 rows, 12 columns
**Content:** ICE vehicle fuel consumption and CO2 emissions (Canadian government data)
**Structure:** Flat table, one row per vehicle variant

**Key fields:**

| Field | Type | Description |
|-------|------|-------------|
| Make | TEXT | Manufacturer, 42 unique |
| Model | TEXT | Model name, 2,048 unique |
| Vehicle Class | TEXT | 16 classes (COMPACT, SUV-SMALL, etc.) |
| Engine Size(L) | FLOAT | 0.9 to 8.4 |
| Cylinders | INT | 3 to 16 |
| Fuel Type | TEXT | Coded: D=Diesel, E=E85, N=NatGas, X=Regular, Z=Premium |
| Fuel Consumption Comb (L/100 km) | FLOAT | Combined fuel consumption |
| CO2 Emissions(g/km) | INT | 96 to 522 |

**Example row:**
`ACURA | ILX | COMPACT | 2.0 | 4 | AS5 | Z | 8.5 L/100km | 196 g/km`

---

## Source 3: GitHub — EV Specifications Database (OSkrk)

**Publisher:** GitHub user OSkrk
**URL:** https://github.com/OSkrk/Electric-vehicles-EV-Database

**Dataset:** `ev_specs_database.csv` — 67 rows, 12 columns
**Content:** EV model specifications with battery and charging data
**Structure:** Flat table, one row per EV model

**Key fields:**

| Field | Type | Description |
|-------|------|-------------|
| Car model | TEXT | "Tesla Model 3", "Audi E tron s", etc. |
| Autonomy_WLTP_Km | INT | Range in km (150–610) |
| Battery_Capacity_kWh | FLOAT | Battery size (17.6–100) |
| DC_nominal_charge_power_KW | INT | DC charging power |
| Car_type | TEXT | SUV, Sedan, Hatchback, etc. |
| Approx_Release_price_order_in_K$ | TEXT | Price in thousands |
| year | INT | Release year |

**Derived field:** `kWh/100km = Battery_Capacity_kWh / Autonomy_WLTP_Km * 100`

---

## Source 4: IEA — Global EV Data Explorer

**Publisher:** International Energy Agency (IEA)
**URL:** https://www.iea.org/data-and-statistics/data-tools/global-ev-data-explorer

**Dataset:** `iea_global_ev_data_2024.csv` — 12,654 rows, 8 columns
**Content:** EV stock, sales, and market share by country
**Structure:** Long format — region/parameter/powertrain/year

**Key fields:**

| Field | Type | Description |
|-------|------|-------------|
| region | TEXT | Country name |
| parameter | TEXT | "EV sales", "EV stock", "EV sales share", "EV stock share" |
| powertrain | TEXT | BEV, PHEV, EV (aggregate) |
| year | INT | 2010–2024 |
| unit | TEXT | "Vehicles" or "percent" |
| value | FLOAT | The measurement |

**Example row:**
`France | Historical | EV sales | Cars | BEV | 2023 | Vehicles | 298819`

---

## Source 5: GitHub — Global EV Charging Infrastructure (tarekmasryo)

**Publisher:** GitHub user tarekmasryo
**URL:** https://github.com/tarekmasryo/global-ev-infra-dataset

### Dataset a: `charging_station.csv` — 242,417 rows, 11 columns

**Content:** Individual EV charging stations worldwide
**Structure:** One row per station

| Field | Type | Description |
|-------|------|-------------|
| id | INT | Unique station ID |
| name | TEXT | Station name |
| city | TEXT | City (messy data) |
| country_code | TEXT | 2-letter code, 121 countries |
| latitude / longitude | FLOAT | GPS coordinates |
| ports | INT | Number of charging ports |
| power_kw | FLOAT | Charging power (1.9% nulls) |
| power_class | TEXT | AC_L1, AC_L2, AC_HIGH, DC_FAST, DC_ULTRA |
| is_fast_dc | BOOL | True/False |

### Dataset b: `country_summary.csv` — 121 rows, 6 columns

**Content:** Charging infrastructure summary per country
**Structure:** One row per country

| Field | Type | Description |
|-------|------|-------------|
| country_code | TEXT | 2-letter code |
| country | TEXT | Full name |
| station_count | INT | Total stations |
| port_count | INT | Total ports |
| fast_station_share | FLOAT | % of stations with fast charging |

---

## Source 6: Ember Energy — Yearly Electricity Data

**Publisher:** Ember (independent energy think tank)
**URL:** https://ember-energy.org/data/

**Dataset:** `ember_yearly_electricity.csv` — 359,796 rows, 18 columns
**Content:** Global electricity generation by source, yearly
**Structure:** Long format — each row is one variable for one country-year

**Key fields:**

| Field | Type | Description |
|-------|------|-------------|
| Area | TEXT | Country name, 228 unique |
| ISO 3 code | TEXT | Country code |
| Year | INT | 2000–2025 |
| Category | TEXT | Capacity, Electricity demand, Electricity generation, etc. |
| Variable | TEXT | Coal, Gas, Hydro, Nuclear, Solar, Wind, etc. |
| Unit | TEXT | GW, TWh, %, gCO2/kWh, etc. |
| Value | FLOAT | The measurement |

**Example row:**
`Germany | DEU | 2023 | Electricity generation | Coal | TWh | 110.2`

---

## Source 7: ElCom — Swiss Electricity Tariffs

**Publisher:** Federal Electricity Commission ElCom (Swiss Government)
**URL:** https://ld.admin.ch/query (SPARQL endpoint)

**Dataset:** `ch_electricity_prices_elcom.csv` — 16 rows, 5 columns
**Content:** Swiss household electricity prices, annual averages
**Structure:** One row per year (2011–2026)

**Key fields:**

| Field | Type | Description |
|-------|------|-------------|
| year | INT | Year |
| avgPrice | FLOAT | Average price in Rappen/kWh across all providers |
| minPrice | FLOAT | Minimum price |
| maxPrice | FLOAT | Maximum price |
| numProviders | INT | ~3,000 providers per year |

**Note:** 1 Rappen = 0.01 CHF; need CHF to EUR conversion (~0.94)

---

## Source 8: Eurostat — EU Household Electricity Prices

**Publisher:** European Commission / Eurostat
**URL:** https://ec.europa.eu/eurostat/databrowser/view/nrg_pc_204

**Dataset:** `eurostat_elec_prices_defr.csv` — 73 rows, 3 columns
**Content:** DE + FR household electricity prices, semi-annual
**Structure:** One row per country-period

**Key fields:**

| Field | Type | Description |
|-------|------|-------------|
| country_code | TEXT | DE or FR |
| period | TEXT | "2007-S1", "2007-S2", etc. |
| price_eur_per_kwh | FLOAT | Price including taxes |

---

## Reference Data (not an independent source)

**Dataset:** `fuel_prices.csv` — 3 rows, 3 columns
**Content:** Current fuel prices for CH, DE, FR
**Fields:** Country, Petrol_EUR_per_L, Diesel_EUR_per_L
Manually compiled from public pricing data.

---

## Summary of Sources

| # | Publisher | Type | Datasets | Rows |
|---|-----------|------|----------|------|
| 1 | Kaggle (abdulmalik) | Car specs | Cars Datasets 2025 | 1,218 |
| 2 | Kaggle (brsahan) | CO2 emissions | co2.csv | 7,385 |
| 3 | GitHub (OSkrk) | EV specs | ev_specs_database | 67 |
| 4 | IEA | EV market | iea_global_ev_data | 12,654 |
| 5 | GitHub (tarekmasryo) | Charging infra | charging_station + country_summary | 242,538 |
| 6 | Ember Energy | Grid mix | ember_yearly_elec | 359,796 |
| 7 | ElCom (Swiss Gov) | Elec prices | ch_elec_prices_elcom | 16 |
| 8 | Eurostat (EU) | Elec prices | eurostat_elec_prices | 73 |
| | (Reference) | Fuel prices | fuel_prices.csv | 3 |
| | **TOTAL** | | **10 datasets** | **623,750** |

All 8 sources are formally, structurally, and content-wise independent:
- **Different publishers:** Kaggle users, GitHub repos, IEA, Ember, ElCom, Eurostat
- **Different data formats:** flat CSV, long-format, SPARQL, TSV
- **Different subject matter:** vehicles, emissions, charging, electricity, market data
