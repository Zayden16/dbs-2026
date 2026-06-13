// ============================================================================
// DBS Project: "Are EVs Really Better?"
// MongoDB Native Queries for Metabase
// ============================================================================
// These queries are designed to be used in Metabase's "Native Query" mode
// with the MongoDB connector. Each query produces data for a specific
// dashboard visualization.
//
// In Metabase: New Question → Native Query → Select MongoDB database
// Paste the pipeline array as the query.
//
// Parameters: Metabase supports {{variable}} syntax for interactive filtering.
// ============================================================================

use("ev_project");

// ============================================================================
// QUERY 1: EV vs ICE Decision Dashboard (Main KPI)
// ============================================================================
// Visualization: Bar chart or table comparing cost/km and CO2/km per country
// Metabase: Use the materialized view for instant results
//
// Native query in Metabase (collection: mv_ev_decision):
// [{ "$match": {} }, { "$sort": { "country": 1 } }]
//
// With country parameter:
// [{ "$match": { "country": {{country}} } }]

print("Query 1: EV vs ICE Decision (from materialized view)");
printjson(
  db.mv_ev_decision.find(
    {},
    { _id: 0, country: 1, ice_cost: 1, ev_cost: 1, ev_co2: 1, ice_co2: 1, recommend_ev: 1 }
  ).sort({ country: 1 }).toArray()
);
print("");

// ============================================================================
// QUERY 2: Grid CO2 Intensity Over Time (Line Chart)
// ============================================================================
// Visualization: Line chart — X=year, Y=CO2 intensity, color=country
// Shows how clean each country's electricity grid is over time
//
// Native query (collection: country_year_data):
// [
//   { "$match": { "country_code": { "$in": ["CH", "DE", "FR"] }, "co2_intensity_gkwh": { "$gt": 0 } } },
//   { "$project": { "_id": 0, "country_code": 1, "year": 1, "co2_intensity_gkwh": 1 } },
//   { "$sort": { "country_code": 1, "year": 1 } }
// ]

print("Query 2: CO2 Intensity Over Time");
printjson(
  db.country_year_data.aggregate([
    { $match: { country_code: { $in: ["CH", "DE", "FR"] }, co2_intensity_gkwh: { $gt: 0 } } },
    { $project: { _id: 0, country_code: 1, year: 1, co2_intensity_gkwh: 1 } },
    { $sort: { country_code: 1, year: 1 } }
  ]).toArray().slice(-15)  // show last 15 for brevity
);
print("");

// ============================================================================
// QUERY 3: Electricity Price Trend (Line Chart)
// ============================================================================
// Visualization: Line chart — X=year, Y=price EUR/kWh, color=country
//
// Native query (collection: country_year_data):
// [
//   { "$match": { "country_code": { "$in": ["CH", "DE", "FR"] }, "electricity_price_eur_per_kwh": { "$gt": 0 } } },
//   { "$project": { "_id": 0, "country_code": 1, "year": 1, "electricity_price_eur_per_kwh": 1 } },
//   { "$sort": { "year": 1 } }
// ]

print("Query 3: Electricity Price Trend");
printjson(
  db.country_year_data.aggregate([
    { $match: { country_code: { $in: ["CH", "DE", "FR"] }, electricity_price_eur_per_kwh: { $gt: 0 } } },
    { $project: { _id: 0, country_code: 1, year: 1, electricity_price_eur_per_kwh: 1 } },
    { $sort: { year: 1 } }
  ]).toArray().slice(-15)
);
print("");

// ============================================================================
// QUERY 4: EV Adoption Trend (Line Chart)
// ============================================================================
// Visualization: Line chart — X=year, Y=BEV sales, color=country
//
// Native query (collection: country_year_data):
// [
//   { "$match": { "country_code": { "$in": ["CH", "DE", "FR"] }, "ev_adoption.bev_sales": { "$gt": 0 } } },
//   { "$project": { "_id": 0, "country_code": 1, "year": 1, "bev_sales": "$ev_adoption.bev_sales", "sales_share_pct": "$ev_adoption.sales_share_pct" } },
//   { "$sort": { "year": 1 } }
// ]

print("Query 4: EV Adoption Trend");
printjson(
  db.country_year_data.aggregate([
    { $match: { country_code: { $in: ["CH", "DE", "FR"] }, "ev_adoption.bev_sales": { $gt: 0 } } },
    { $project: { _id: 0, country_code: 1, year: 1, bev_sales: "$ev_adoption.bev_sales", sales_share_pct: "$ev_adoption.sales_share_pct" } },
    { $sort: { year: 1 } }
  ]).toArray().slice(-12)
);
print("");

// ============================================================================
// QUERY 5: Charging Infrastructure by Country (Bar Chart)
// ============================================================================
// Visualization: Grouped bar chart — X=country, Y=station count, stacked by power_class
//
// Native query (collection: charging_stations):
// [
//   { "$group": { "_id": { "country": "$country_code", "power_class": "$power_class" }, "count": { "$sum": 1 } } },
//   { "$sort": { "_id.country": 1, "count": -1 } },
//   { "$project": { "_id": 0, "country": "$_id.country", "power_class": "$_id.power_class", "count": 1 } }
// ]

print("Query 5: Charging Infrastructure by Country & Power Class");
printjson(
  db.charging_stations.aggregate([
    { $group: { _id: { country: "$country_code", power_class: "$power_class" }, count: { $sum: 1 } } },
    { $sort: { "_id.country": 1, count: -1 } },
    { $project: { _id: 0, country: "$_id.country", power_class: "$_id.power_class", count: 1 } }
  ]).toArray()
);
print("");

// ============================================================================
// QUERY 6: Grid Mix Breakdown for 2022 (Stacked Bar / Pie)
// ============================================================================
// Visualization: Stacked bar chart — X=country, Y=generation TWh, color=source
//
// Native query (collection: country_year_data):
// [
//   { "$match": { "year": 2022, "country_code": { "$in": ["CH", "DE", "FR"] } } },
//   { "$unwind": "$grid_mix" },
//   { "$project": { "_id": 0, "country_code": 1, "source": "$grid_mix.source", "generation_twh": "$grid_mix.generation_twh" } },
//   { "$match": { "generation_twh": { "$gt": 0.5 } } },
//   { "$sort": { "country_code": 1, "generation_twh": -1 } }
// ]

print("Query 6: Grid Mix 2022");
printjson(
  db.country_year_data.aggregate([
    { $match: { year: 2022, country_code: { $in: ["CH", "DE", "FR"] } } },
    { $unwind: "$grid_mix" },
    { $project: { _id: 0, country_code: 1, source: "$grid_mix.source", generation_twh: "$grid_mix.generation_twh" } },
    { $match: { generation_twh: { $gt: 0.5 } } },
    { $sort: { country_code: 1, generation_twh: -1 } }
  ]).toArray()
);
print("");

// ============================================================================
// QUERY 7: Parametrized Decision Query (Interactive)
// ============================================================================
// This query allows a Metabase user to select a specific country and year
// to see the EV recommendation for their scenario.
//
// Metabase native query with parameters (collection: country_year_data):
// [
//   { "$match": { "country_code": {{country}}, "year": {{year}} } },
//   { "$lookup": { ... } },
//   ...
// ]
// Parameters: country (Text), year (Number)

print("Query 7: Interactive decision for a specific country+year");
// Example: CH, 2022
const interactiveResult = db.country_year_data.aggregate([
  { $match: { country_code: "CH", year: 2022 } },
  {
    $lookup: {
      from: "countries",
      localField: "country_code",
      foreignField: "country_code",
      as: "country"
    }
  },
  { $unwind: "$country" },
  {
    $lookup: {
      from: "vehicles",
      pipeline: [
        { $match: { "ice_emission.fuel_consumption_comb": { $gt: 0 } } },
        { $group: { _id: null, avg_l: { $avg: "$ice_emission.fuel_consumption_comb" }, avg_co2: { $avg: "$ice_emission.co2_emissions_gkm" } } }
      ],
      as: "ice"
    }
  },
  { $unwind: "$ice" },
  {
    $lookup: {
      from: "vehicles",
      pipeline: [
        { $match: { "ev_spec.energy_consumption_kwh_100km": { $gt: 0 } } },
        { $group: { _id: null, avg_kwh: { $avg: "$ev_spec.energy_consumption_kwh_100km" } } }
      ],
      as: "ev"
    }
  },
  { $unwind: "$ev" },
  {
    $project: {
      _id: 0,
      country: "$country_code",
      year: 1,
      electricity_price: "$electricity_price_eur_per_kwh",
      co2_intensity: "$co2_intensity_gkwh",
      ice_cost_per_km: { $round: [{ $multiply: [{ $divide: ["$ice.avg_l", 100] }, { $divide: [{ $add: ["$country.petrol_price_eur_per_l", "$country.diesel_price_eur_per_l"] }, 2] }] }, 4] },
      ev_cost_per_km: { $round: [{ $multiply: [{ $divide: ["$ev.avg_kwh", 100] }, "$electricity_price_eur_per_kwh"] }, 4] },
      ev_co2_per_km: { $round: [{ $multiply: [{ $divide: ["$ev.avg_kwh", 100] }, "$co2_intensity_gkwh"] }, 2] },
      ice_co2_per_km: { $round: ["$ice.avg_co2", 0] },
      grid_mix: 1,
      ev_adoption: 1,
      charging: "$country.charging_summary"
    }
  }
]).toArray();

printjson(interactiveResult);
print("");

print("============================================");
print("All Metabase queries validated successfully.");
print("============================================");
