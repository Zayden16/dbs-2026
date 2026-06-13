# MongoDB Native Queries for Metabase

In Metabase: **New Question → Native query → Database: MongoDB (ev_project) →
Collection** as noted per query. Paste the JSON array. `{{country}}` becomes a
Metabase variable (Text); set the dropdown values to `CH`, `DE`, `FR`.

Source of truth: `mongodb/06_metabase_queries.js`.

---

## Q1 — Decision KPI (table / bar). Collection: `mv_ev_decision`

All countries:
```json
[
  { "$match": {} },
  { "$project": { "_id": 0, "country": 1, "ice_cost": 1, "ev_cost": 1, "ev_co2": 1, "ice_co2": 1, "recommend_ev": 1 } },
  { "$sort": { "country": 1 } }
]
```

Filtered by country variable:
```json
[
  { "$match": { "country": {{country}} } },
  { "$sort": { "country": 1 } }
]
```

### Q1b — Cost €/km EV vs ICE (bar). Collection: `mv_ev_decision`
```json
[
  { "$project": { "_id": 0, "country": 1, "ev_cost": 1, "ice_cost": 1 } },
  { "$sort": { "country": 1 } }
]
```

### Q1c — CO₂ g/km EV vs ICE (bar). Collection: `mv_ev_decision`
```json
[
  { "$project": { "_id": 0, "country": 1, "ev_co2": 1, "ice_co2": 1 } },
  { "$sort": { "country": 1 } }
]
```

---

## Q2 — Grid CO₂ intensity over time (line). Collection: `country_year_data`
X = year, Y = gCO₂/kWh, colour = country.
```json
[
  { "$match": { "country_code": { "$in": ["CH", "DE", "FR"] }, "co2_intensity_gkwh": { "$gt": 0 } } },
  { "$project": { "_id": 0, "country_code": 1, "year": 1, "co2_intensity_gkwh": 1 } },
  { "$sort": { "country_code": 1, "year": 1 } }
]
```

## Q3 — Electricity price trend (line). Collection: `country_year_data`
```json
[
  { "$match": { "country_code": { "$in": ["CH", "DE", "FR"] }, "electricity_price_eur_per_kwh": { "$gt": 0 } } },
  { "$project": { "_id": 0, "country_code": 1, "year": 1, "electricity_price_eur_per_kwh": 1 } },
  { "$sort": { "year": 1 } }
]
```

## Q4 — EV adoption trend (line). Collection: `country_year_data`
Dot-notation on the embedded `ev_adoption` subdocument.
```json
[
  { "$match": { "country_code": { "$in": ["CH", "DE", "FR"] }, "ev_adoption.bev_sales": { "$gt": 0 } } },
  { "$project": { "_id": 0, "country_code": 1, "year": 1, "bev_sales": "$ev_adoption.bev_sales", "sales_share_pct": "$ev_adoption.sales_share_pct" } },
  { "$sort": { "year": 1 } }
]
```

## Q5 — Charging infrastructure by country & power class (bar). Collection: `charging_stations`
```json
[
  { "$group": { "_id": { "country": "$country_code", "power_class": "$power_class" }, "count": { "$sum": 1 } } },
  { "$project": { "_id": 0, "country": "$_id.country", "power_class": "$_id.power_class", "count": 1 } },
  { "$sort": { "country": 1, "count": -1 } }
]
```

## Q6 — Grid mix 2022 (stacked bar). Collection: `country_year_data`
`$unwind` on the embedded `grid_mix` array.
```json
[
  { "$match": { "year": 2022, "country_code": { "$in": ["CH", "DE", "FR"] } } },
  { "$unwind": "$grid_mix" },
  { "$project": { "_id": 0, "country_code": 1, "source": "$grid_mix.source", "generation_twh": "$grid_mix.generation_twh" } },
  { "$match": { "generation_twh": { "$gt": 0.5 } } },
  { "$sort": { "country_code": 1, "generation_twh": -1 } }
]
```

---

## Q7 — Interactive decision per country + year. Collection: `country_year_data`
Parameters: `{{country}}` (Text), `{{year}}` (Number).

> **NOTE:** the ICE `$match` MUST include `fuel_type IN ["Petrol","Diesel"]`,
> otherwise the average is taken over the full registry (Premium Petrol, E85,
> Natural Gas) and ice_co2 becomes ~250 instead of the canonical 235.
```json
[
  { "$match": { "country_code": {{country}}, "year": {{year}} } },
  { "$lookup": { "from": "countries", "localField": "country_code", "foreignField": "country_code", "as": "country" } },
  { "$unwind": "$country" },
  { "$lookup": { "from": "vehicles", "pipeline": [
      { "$match": { "fuel_type": { "$in": ["Petrol", "Diesel"] }, "ice_emission.fuel_consumption_comb": { "$gt": 0 }, "ice_emission.co2_emissions_gkm": { "$gt": 0 } } },
      { "$group": { "_id": null, "avg_l": { "$avg": "$ice_emission.fuel_consumption_comb" }, "avg_co2": { "$avg": "$ice_emission.co2_emissions_gkm" } } }
    ], "as": "ice" } },
  { "$unwind": "$ice" },
  { "$lookup": { "from": "vehicles", "pipeline": [
      { "$match": { "ev_spec.energy_consumption_kwh_100km": { "$gt": 0 } } },
      { "$group": { "_id": null, "avg_kwh": { "$avg": "$ev_spec.energy_consumption_kwh_100km" } } }
    ], "as": "ev" } },
  { "$unwind": "$ev" },
  { "$project": {
      "_id": 0, "country": "$country_code", "year": 1,
      "electricity_price": "$electricity_price_eur_per_kwh",
      "co2_intensity": "$co2_intensity_gkwh",
      "ice_cost_per_km": { "$round": [ { "$multiply": [ { "$divide": ["$ice.avg_l", 100] }, { "$divide": [ { "$add": ["$country.petrol_price_eur_per_l", "$country.diesel_price_eur_per_l"] }, 2 ] } ] }, 4 ] },
      "ev_cost_per_km": { "$round": [ { "$multiply": [ { "$divide": ["$ev.avg_kwh", 100] }, "$electricity_price_eur_per_kwh" ] }, 4 ] },
      "ev_co2_per_km": { "$round": [ { "$multiply": [ { "$divide": ["$ev.avg_kwh", 100] }, "$co2_intensity_gkwh" ] }, 2 ] },
      "ice_co2_per_km": { "$round": ["$ice.avg_co2", 0] }
    } }
]
```
