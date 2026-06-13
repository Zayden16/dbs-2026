// ============================================================================
// DBS Project: "Are EVs Really Better?"
// MongoDB Schema — Denormalized Document Model
// ============================================================================
// Run with: mongosh "$MONGO_URI" 01_schema_prototypes.js
// ============================================================================

use("ev_project");

// ============================================================================
// Drop existing collections (clean slate)
// ============================================================================
db.vehicles.drop();
db.countries.drop();
db.country_year_data.drop();
db.charging_stations.drop();

// ============================================================================
// 1. VEHICLES — denormalized: embeds ev_spec OR ice_emission
// ============================================================================
// In SQL, vehicle + ice_emission + ev_spec are 3 separate tables in 3NF.
// In MongoDB, we embed the type-specific subdocument directly, avoiding JOINs.
// A discriminator field (fuel_type) determines which subdocument is present.

db.createCollection("vehicles", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["make", "model", "fuel_type"],
      properties: {
        make:          { bsonType: "string", description: "Manufacturer" },
        model:         { bsonType: "string", description: "Model name" },
        fuel_type:     { bsonType: "string", description: "Electric, Petrol, Diesel, Hybrid, etc." },
        vehicle_class: { bsonType: "string", description: "SUV, Compact, Sedan, etc." },
        price_usd:     { bsonType: "double", description: "Approximate price in USD" },
        horsepower:    { bsonType: "int",    description: "Engine/motor power in hp" },
        seats:         { bsonType: "int",    description: "Number of seats" },
        // Embedded subdocument for EVs (only present when fuel_type = Electric)
        ev_spec: {
          bsonType: "object",
          properties: {
            battery_capacity_kwh:         { bsonType: "double" },
            range_wltp_km:                { bsonType: "int" },
            energy_consumption_kwh_100km: { bsonType: "double" },
            dc_charge_power_kw:           { bsonType: "int" },
            ac_charge_power_kw:           { bsonType: "double" },
            release_year:                 { bsonType: "int" }
          }
        },
        // Embedded subdocument for ICE vehicles
        ice_emission: {
          bsonType: "object",
          properties: {
            engine_size_l:        { bsonType: "double" },
            cylinders:            { bsonType: "int" },
            transmission:         { bsonType: "string" },
            fuel_consumption_city:{ bsonType: "double" },
            fuel_consumption_hwy: { bsonType: "double" },
            fuel_consumption_comb:{ bsonType: "double" },
            co2_emissions_gkm:    { bsonType: "int" }
          }
        }
      }
    }
  }
});

// JSON Prototype — EV document
/*
{
  "make": "Tesla",
  "model": "Model 3",
  "fuel_type": "Electric",
  "vehicle_class": "Sedan",
  "price_usd": 42000.00,
  "horsepower": 283,
  "seats": 5,
  "ev_spec": {
    "battery_capacity_kwh": 60.0,
    "range_wltp_km": 491,
    "energy_consumption_kwh_100km": 12.2,
    "dc_charge_power_kw": 170,
    "ac_charge_power_kw": 11.0,
    "release_year": 2019
  }
}
*/

// JSON Prototype — ICE document
/*
{
  "make": "BMW",
  "model": "320i",
  "fuel_type": "Petrol",
  "vehicle_class": "COMPACT",
  "price_usd": 41000.00,
  "horsepower": 184,
  "seats": 5,
  "ice_emission": {
    "engine_size_l": 2.0,
    "cylinders": 4,
    "transmission": "AS8",
    "fuel_consumption_city": 9.1,
    "fuel_consumption_hwy": 6.4,
    "fuel_consumption_comb": 7.9,
    "co2_emissions_gkm": 183
  }
}
*/

// ============================================================================
// 2. COUNTRIES — denormalized: embeds charging_country_summary
// ============================================================================
// In SQL, country + charging_country_summary are 2 tables (1:1 relationship).
// In MongoDB, we embed the summary directly into the country document.

db.createCollection("countries", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["country_code", "country_name"],
      properties: {
        country_code:          { bsonType: "string", description: "ISO 2-letter code" },
        country_name:          { bsonType: "string", description: "Full country name" },
        petrol_price_eur_per_l:{ bsonType: "double" },
        diesel_price_eur_per_l:{ bsonType: "double" },
        // Embedded: replaces charging_country_summary table
        charging_summary: {
          bsonType: "object",
          properties: {
            station_count:      { bsonType: "int" },
            port_count:         { bsonType: "int" },
            fast_station_share: { bsonType: "double" },
            fast_port_share:    { bsonType: "double" }
          }
        }
      }
    }
  }
});

// JSON Prototype
/*
{
  "country_code": "CH",
  "country_name": "Switzerland",
  "petrol_price_eur_per_l": 1.67,
  "diesel_price_eur_per_l": 1.80,
  "charging_summary": {
    "station_count": 878,
    "port_count": 1998,
    "fast_station_share": 0.2153,
    "fast_port_share": 0.3964
  }
}
*/

// ============================================================================
// 3. COUNTRY_YEAR_DATA — heavily denormalized aggregate document
// ============================================================================
// In SQL, electricity_price + grid_mix + ev_adoption are 3 separate tables,
// all linked to country via FK and queried together via JOINs.
// In MongoDB, we aggregate them into ONE document per country-year,
// embedding grid_mix as an array and ev_adoption as a subdocument.

db.createCollection("country_year_data", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["country_code", "year"],
      properties: {
        country_code:                  { bsonType: "string" },
        year:                          { bsonType: "int" },
        electricity_price_eur_per_kwh: { bsonType: "double" },
        co2_intensity_gkwh:            { bsonType: "double" },
        // Embedded array: replaces grid_mix table rows
        grid_mix: {
          bsonType: "array",
          items: {
            bsonType: "object",
            properties: {
              source:         { bsonType: "string" },
              generation_twh: { bsonType: "double" },
              share_pct:      { bsonType: "double" }
            }
          }
        },
        // Embedded subdocument: replaces ev_adoption table
        ev_adoption: {
          bsonType: "object",
          properties: {
            bev_sales:       { bsonType: "int" },
            phev_sales:      { bsonType: "int" },
            bev_stock:       { bsonType: "int" },
            phev_stock:      { bsonType: "int" },
            sales_share_pct: { bsonType: "double" },
            stock_share_pct: { bsonType: "double" }
          }
        }
      }
    }
  }
});

// JSON Prototype
/*
{
  "country_code": "CH",
  "year": 2022,
  "electricity_price_eur_per_kwh": 0.2187,
  "co2_intensity_gkwh": 37.26,
  "grid_mix": [
    { "source": "Hydro",    "generation_twh": 36.20, "share_pct": 52.10 },
    { "source": "Nuclear",  "generation_twh": 23.10, "share_pct": 33.24 },
    { "source": "Solar",    "generation_twh": 3.56,  "share_pct": 5.12 },
    { "source": "Wind",     "generation_twh": 0.15,  "share_pct": 0.22 },
    { "source": "Gas",      "generation_twh": 0.89,  "share_pct": 1.28 }
  ],
  "ev_adoption": {
    "bev_sales": 40000,
    "phev_sales": 19000,
    "bev_stock": 92000,
    "phev_stock": 51000,
    "sales_share_pct": 17.5,
    "stock_share_pct": 2.1
  }
}
*/

// ============================================================================
// 4. CHARGING_STATIONS — flat collection with GeoJSON
// ============================================================================
// Too many documents (~38k for CH/DE/FR) to embed in countries.
// Kept as a separate collection, but enriched with GeoJSON for geospatial queries.

db.createCollection("charging_stations", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["station_id", "country_code"],
      properties: {
        station_id:    { bsonType: "int" },
        name:          { bsonType: "string" },
        city:          { bsonType: "string" },
        state_province:{ bsonType: "string" },
        country_code:  { bsonType: "string" },
        location: {
          bsonType: "object",
          properties: {
            type:        { bsonType: "string" },
            coordinates: { bsonType: "array" }
          }
        },
        ports:       { bsonType: "int" },
        power_kw:    { bsonType: "double" },
        power_class: { bsonType: "string" },
        is_fast_dc:  { bsonType: "bool" }
      }
    }
  }
});

// JSON Prototype
/*
{
  "station_id": 307660,
  "name": "Supercharger Zürich",
  "city": "Zürich",
  "state_province": "ZH",
  "country_code": "CH",
  "location": {
    "type": "Point",
    "coordinates": [8.5417, 47.3769]
  },
  "ports": 8,
  "power_kw": 250.0,
  "power_class": "DC_ULTRA_(>=150kW)",
  "is_fast_dc": true
}
*/

// ============================================================================
// SCHEMA COMPARISON: SQL (3NF) vs MongoDB (Denormalized)
// ============================================================================
/*
  SQL (9 tables, 3NF)              MongoDB (4 collections, denormalized)
  ─────────────────────────────    ─────────────────────────────────────
  country                     ──>  countries (embeds charging_summary)
  charging_country_summary    ──╯
  vehicle                     ──>  vehicles (embeds ev_spec OR ice_emission)
  ice_emission                ──╯
  ev_spec                     ──╯
  electricity_price           ──>  country_year_data (embeds grid_mix array
  grid_mix                    ──╯    + ev_adoption subdocument)
  ev_adoption                 ──╯
  charging_station            ──>  charging_stations (with GeoJSON)
*/

print("Schema created successfully: vehicles, countries, country_year_data, charging_stations");
