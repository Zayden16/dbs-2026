// ============================================================================
// DBS Project: "Are EVs Really Better?"
// MongoDB Analytics — EV vs ICE Decision Query
// ============================================================================
// Run with: mongosh "$MONGO_URI" 04_analytics.js
// ============================================================================
// This aggregation pipeline mirrors the SQL query from 03_ev_ice_decision.sql.
// It computes the same KPIs and decision recommendation per country.
//
// Decision Rule:
//   Recommend EV if BOTH conditions are met:
//   1. BEV cost/km <= 1.10 × ICE cost/km (max 10% premium)
//   2. BEV CO2/km  <= ICE CO2/km
//
// Canonical methodology (must match SQL output):
//   - Fuel prices: real fuel_prices.csv (CH 1.67/1.80, DE 1.85/1.76, FR 1.79/1.75)
//   - ICE fleet: fuel_type IN ("Petrol","Diesel") only
//   - ICE cost/km: avg consumption / 100 * avg(petrol, diesel) price
//
// Expected Results (must match SQL output):
//   CH: ice=0.1740 EUR/km, ev=0.0375, ev_co2=6.91,  ice_co2=235, recommend=1
//   DE: ice=0.1810 EUR/km, ev=0.0684, ev_co2=77.84, ice_co2=235, recommend=1
//   FR: ice=0.1775 EUR/km, ev=0.0470, ev_co2=14.57, ice_co2=235, recommend=1
//
// MQL Keywords used (15+):
//   $match, $group, $project, $lookup, $unwind, $addFields, $avg, $sum,
//   $multiply, $divide, $cond, $lte, $and, $sort, $round, $let,
//   $toDouble, $ifNull
// ============================================================================

use("ev_project");

print("============================================");
print("EV vs ICE Decision Analysis (Reference Year: 2022)");
print("============================================");
print("");

// ============================================================================
// MAIN ANALYTICS PIPELINE
// ============================================================================
// Strategy:
// 1. Compute average ICE fuel consumption (L/100km) and CO2 (g/km) from vehicles
// 2. Compute average EV energy consumption (kWh/100km) from vehicles
// 3. For each country (CH, DE, FR), lookup 2022 electricity price and CO2 intensity
// 4. Calculate cost/km and CO2/km for both ICE and EV
// 5. Apply decision rule
// ============================================================================

const result = db.vehicles.aggregate([
  // ── Stage 1: Match only ICE vehicles with valid fuel consumption data ──
  // Canonical ICE fleet = Petrol + Diesel only (excludes Premium Petrol,
  // E85, Natural Gas). SQL must use the identical filter.
  {
    $match: {
      fuel_type: { $in: ["Petrol", "Diesel"] },
      "ice_emission.fuel_consumption_comb": { $gt: 0 },
      "ice_emission.co2_emissions_gkm": { $gt: 0 }
    }
  },

  // ── Stage 2: Group to get fleet-average ICE consumption and CO2 ──
  {
    $group: {
      _id: null,
      avg_ice_consumption_l_100km: { $avg: "$ice_emission.fuel_consumption_comb" },
      avg_ice_co2_gkm: { $avg: "$ice_emission.co2_emissions_gkm" }
    }
  },

  // ── Stage 3: Lookup EV fleet averages via a sub-pipeline ──
  {
    $lookup: {
      from: "vehicles",
      pipeline: [
        {
          $match: {
            "ev_spec.energy_consumption_kwh_100km": { $gt: 0 }
          }
        },
        {
          $group: {
            _id: null,
            avg_ev_consumption_kwh_100km: { $avg: "$ev_spec.energy_consumption_kwh_100km" }
          }
        }
      ],
      as: "ev_data"
    }
  },
  { $unwind: "$ev_data" },

  // ── Stage 4: Add EV average to the working document ──
  {
    $addFields: {
      avg_ev_consumption_kwh_100km: "$ev_data.avg_ev_consumption_kwh_100km"
    }
  },

  // ── Stage 5: Lookup the 3 countries ──
  {
    $lookup: {
      from: "countries",
      pipeline: [
        { $match: { country_code: { $in: ["CH", "DE", "FR"] } } }
      ],
      as: "country_list"
    }
  },
  { $unwind: "$country_list" },

  // ── Stage 6: Lookup country_year_data for 2022 per country ──
  {
    $lookup: {
      from: "country_year_data",
      let: { cc: "$country_list.country_code" },
      pipeline: [
        {
          $match: {
            $expr: {
              $and: [
                { $eq: ["$country_code", "$$cc"] },
                { $eq: ["$year", 2022] }
              ]
            }
          }
        }
      ],
      as: "year_data"
    }
  },
  { $unwind: "$year_data" },

  // ── Stage 7: Calculate all KPIs ──
  {
    $addFields: {
      country_code: "$country_list.country_code",

      // ICE cost per km = avg consumption (L/100km) / 100 * petrol price (EUR/L)
      // Using average of petrol and diesel prices
      avg_ice_cost_per_km: {
        $round: [
          {
            $multiply: [
              { $divide: ["$avg_ice_consumption_l_100km", 100] },
              {
                $divide: [
                  { $sum: [
                    "$country_list.petrol_price_eur_per_l",
                    "$country_list.diesel_price_eur_per_l"
                  ]},
                  2
                ]
              }
            ]
          },
          4
        ]
      },

      // EV cost per km = avg consumption (kWh/100km) / 100 * electricity price (EUR/kWh)
      avg_bev_cost_per_km: {
        $round: [
          {
            $multiply: [
              { $divide: ["$avg_ev_consumption_kwh_100km", 100] },
              "$year_data.electricity_price_eur_per_kwh"
            ]
          },
          4
        ]
      },

      // EV CO2 per km = avg consumption (kWh/100km) / 100 * grid CO2 intensity (gCO2/kWh)
      avg_bev_co2_gkm: {
        $round: [
          {
            $multiply: [
              { $divide: ["$avg_ev_consumption_kwh_100km", 100] },
              "$year_data.co2_intensity_gkwh"
            ]
          },
          2
        ]
      },

      // ICE CO2 (already in g/km from fleet average)
      avg_ice_co2_gkm: { $round: ["$avg_ice_co2_gkm", 0] }
    }
  },

  // ── Stage 8: Apply decision rule ──
  {
    $addFields: {
      recommend_ev: {
        $cond: {
          if: {
            $and: [
              // Cost condition: EV cost <= 1.10 * ICE cost
              { $lte: ["$avg_bev_cost_per_km", { $multiply: ["$avg_ice_cost_per_km", 1.10] }] },
              // CO2 condition: EV CO2 <= ICE CO2
              { $lte: ["$avg_bev_co2_gkm", "$avg_ice_co2_gkm"] }
            ]
          },
          then: 1,
          else: 0
        }
      },
      // Show the threshold ratios for transparency
      cost_ratio: {
        $round: [{ $divide: ["$avg_bev_cost_per_km", { $max: ["$avg_ice_cost_per_km", 0.0001] }] }, 2]
      },
      co2_ratio: {
        $round: [{ $divide: ["$avg_bev_co2_gkm", { $max: [{ $toDouble: "$avg_ice_co2_gkm" }, 0.0001] }] }, 2]
      }
    }
  },

  // ── Stage 9: Final projection — clean output ──
  {
    $project: {
      _id: 0,
      country: "$country_code",
      ice_eur_per_km: "$avg_ice_cost_per_km",
      ev_eur_per_km: "$avg_bev_cost_per_km",
      ev_co2_gkm: "$avg_bev_co2_gkm",
      ice_co2_gkm: "$avg_ice_co2_gkm",
      recommend_ev: 1,
      cost_ratio: 1,
      co2_ratio: 1
    }
  },

  // ── Stage 10: Sort by country ──
  { $sort: { country: 1 } }
]).toArray();

// ============================================================================
// DISPLAY RESULTS
// ============================================================================
print("┌─────────┬────────────┬───────────┬───────────┬───────────┬──────────────┐");
print("│ Country │ ICE EUR/km │ EV EUR/km │ EV CO2    │ ICE CO2   │ Recommend EV │");
print("├─────────┼────────────┼───────────┼───────────┼───────────┼──────────────┤");

result.forEach(r => {
  print(
    "│ " + r.country.padEnd(7) +
    " │ " + r.ice_eur_per_km.toFixed(4).padStart(10) +
    " │ " + r.ev_eur_per_km.toFixed(4).padStart(9) +
    " │ " + r.ev_co2_gkm.toFixed(2).padStart(9) +
    " │ " + String(r.ice_co2_gkm).padStart(9) +
    " │ " + (r.recommend_ev ? "YES" : "NO").padStart(12) + " │"
  );
});

print("└─────────┴────────────┴───────────┴───────────┴───────────┴──────────────┘");
print("");

print("Decision Rule: Recommend EV if cost/km <= 1.10 × ICE AND CO2/km <= ICE");
print("");

result.forEach(r => {
  print(r.country + ": Cost ratio = " + r.cost_ratio + " (max 1.10), CO2 ratio = " + r.co2_ratio + " (max 1.00) → " + (r.recommend_ev ? "RECOMMEND EV" : "DO NOT RECOMMEND"));
});

print("");
print("Analysis complete.");
