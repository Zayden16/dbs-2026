// ============================================================================
// DBS Project: "Are EVs Really Better?"
// MongoDB Performance Optimization
// ============================================================================
// Run with: mongosh "$MONGO_URI" 05_performance.js
// ============================================================================
// Demonstrates 3+ optimization approaches:
//   1. Execution Plan Analysis (explain)
//   2. Compound Indexes
//   3. Materialized View ($out)
// Measures query time before and after each optimization.
// ============================================================================

use("ev_project");

// ============================================================================
// STEP 0: Collection Size Analysis (dataSize / storageSize)
// ============================================================================
print("── 0. COLLECTION SIZE ANALYSIS ─────────────────────────────");
print("");

const collections = ["vehicles", "countries", "country_year_data", "charging_stations", "stg_ember_electricity"];
collections.forEach(c => {
  const stats = db[c].stats();
  print("  " + c.padEnd(25) +
    " docs: " + String(stats.count).padStart(7) +
    "  dataSize: " + (stats.size / 1024 / 1024).toFixed(2).padStart(7) + " MB" +
    "  storageSize: " + (stats.storageSize / 1024 / 1024).toFixed(2).padStart(7) + " MB");
});
print("");

// ── Reset: drop all user-created indexes so the baseline is genuinely
//    unindexed. Without this, a re-run would measure an already-optimized
//    "baseline" (indexes persist between runs) and the before/after
//    comparison below would be meaningless.
print("Resetting indexes (dropping all non-_id indexes for a clean baseline)...");
collections.forEach(c => {
  db[c].getIndexes().forEach(ix => {
    if (ix.name !== "_id_") {
      try { db[c].dropIndex(ix.name); } catch (e) { /* ignore */ }
    }
  });
});
print("  Done.");
print("");

// ============================================================================
// HELPER: Measure execution time of a pipeline
// ============================================================================
function measurePipeline(collection, pipeline, label) {
  const start = new Date();
  const result = db[collection].aggregate(pipeline).toArray();
  const elapsed = new Date() - start;
  print("  " + label + ": " + elapsed + " ms (" + result.length + " results)");
  return { elapsed, result };
}

// ============================================================================
// BASELINE: The analytics pipeline (same as 04_analytics.js core logic)
// ============================================================================
// This is the query we want to optimize. It computes the EV vs ICE decision
// for all 3 countries using data from vehicles + countries + country_year_data.

const analyticsPipeline = [
  { $match: { fuel_type: { $in: ["Petrol", "Diesel"] }, "ice_emission.fuel_consumption_comb": { $gt: 0 }, "ice_emission.co2_emissions_gkm": { $gt: 0 } } },
  { $group: { _id: null, avg_ice_l: { $avg: "$ice_emission.fuel_consumption_comb" }, avg_ice_co2: { $avg: "$ice_emission.co2_emissions_gkm" } } },
  { $lookup: { from: "vehicles", pipeline: [ { $match: { "ev_spec.energy_consumption_kwh_100km": { $gt: 0 } } }, { $group: { _id: null, avg_ev_kwh: { $avg: "$ev_spec.energy_consumption_kwh_100km" } } } ], as: "ev" } },
  { $unwind: "$ev" },
  { $lookup: { from: "countries", pipeline: [ { $match: { country_code: { $in: ["CH", "DE", "FR"] } } } ], as: "c" } },
  { $unwind: "$c" },
  { $lookup: { from: "country_year_data", let: { cc: "$c.country_code" }, pipeline: [ { $match: { $expr: { $and: [ { $eq: ["$country_code", "$$cc"] }, { $eq: ["$year", 2022] } ] } } } ], as: "yd" } },
  { $unwind: "$yd" },
  { $addFields: {
      ice_cost: { $round: [ { $multiply: [ { $divide: ["$avg_ice_l", 100] }, { $divide: [ { $add: ["$c.petrol_price_eur_per_l", "$c.diesel_price_eur_per_l"] }, 2 ] } ] }, 4 ] },
      ev_cost: { $round: [ { $multiply: [ { $divide: ["$ev.avg_ev_kwh", 100] }, "$yd.electricity_price_eur_per_kwh" ] }, 4 ] },
      ev_co2: { $round: [ { $multiply: [ { $divide: ["$ev.avg_ev_kwh", 100] }, "$yd.co2_intensity_gkwh" ] }, 2 ] },
      ice_co2: { $round: ["$avg_ice_co2", 0] }
  }},
  { $project: { _id: 0, country: "$c.country_code", ice_cost: 1, ev_cost: 1, ev_co2: 1, ice_co2: 1 } },
  { $sort: { country: 1 } }
];

// Separate pipeline for querying the staging collection (large, unindexed)
const emberQueryPipeline = [
  {
    $match: {
      Area: { $in: ["Switzerland", "Germany", "France"] },
      Category: "Power sector emissions",
      Subcategory: "CO2 intensity",
      Variable: "CO2 intensity",
      Unit: "gCO2/kWh",
      Year: 2022
    }
  },
  {
    $project: {
      _id: 0,
      country: "$Area",
      year: "$Year",
      co2_intensity: "$Value"
    }
  }
];

// Pipeline for charging station analysis
const chargingPipeline = [
  {
    $match: {
      country_code: { $in: ["CH", "DE", "FR"] }
    }
  },
  {
    $group: {
      _id: { country: "$country_code", power_class: "$power_class" },
      count: { $sum: 1 },
      avg_power: { $avg: "$power_kw" }
    }
  },
  { $sort: { "_id.country": 1, count: -1 } }
];

print("============================================================");
print("PERFORMANCE OPTIMIZATION — Before vs After");
print("============================================================");
print("");

// ============================================================================
// 1. EXECUTION PLAN ANALYSIS (Before Optimization)
// ============================================================================
print("── 1. EXECUTION PLAN ANALYSIS ──────────────────────────────");
print("");

// Helper to extract explain stats (handles both nested and flat formats)
function getExplainStats(explain) {
  // Flat format (MongoDB 7+)
  if (explain.executionStats) {
    return {
      timeMs: explain.executionStats.executionTimeMillis,
      docsExamined: explain.executionStats.totalDocsExamined,
      keysExamined: explain.executionStats.totalKeysExamined,
      stage: explain.queryPlanner.winningPlan.stage || explain.queryPlanner.winningPlan.queryPlan?.stage || "unknown"
    };
  }
  // Nested format (older versions)
  const cursor = explain.stages[0].$cursor;
  return {
    timeMs: cursor.executionStats.executionTimeMillis,
    docsExamined: cursor.executionStats.totalDocsExamined,
    keysExamined: cursor.executionStats.totalKeysExamined,
    stage: cursor.queryPlanner.winningPlan.stage
  };
}

// Show explain for the Ember staging query (largest collection)
print("Explain plan for stg_ember_electricity query (BEFORE index):");
const explainBefore = db.stg_ember_electricity.explain("executionStats").aggregate(emberQueryPipeline);
const statsBefore = getExplainStats(explainBefore);
print("  Execution time:    " + statsBefore.timeMs + " ms");
print("  Total docs examined: " + statsBefore.docsExamined);
print("  Total keys examined: " + statsBefore.keysExamined);
print("  Winning plan stage: " + JSON.stringify(statsBefore.stage));
print("");

// Explain for charging station query
print("Explain plan for charging_stations query (BEFORE index):");
const explainCharging = db.charging_stations.explain("executionStats").aggregate(chargingPipeline);
const statsCharging = getExplainStats(explainCharging);
print("  Execution time:    " + statsCharging.timeMs + " ms");
print("  Total docs examined: " + statsCharging.docsExamined);
print("  Winning plan stage: " + JSON.stringify(statsCharging.stage));
print("");

// ── Baseline Timings ──
print("── BASELINE TIMINGS (no indexes, no materialization) ──");
print("");

// Run each query 3 times, take median
function benchmark(collection, pipeline, label, runs) {
  const times = [];
  for (let i = 0; i < runs; i++) {
    const { elapsed } = measurePipeline(collection, pipeline, label + " run " + (i + 1));
    times.push(elapsed);
  }
  times.sort((a, b) => a - b);
  const median = times[Math.floor(times.length / 2)];
  print("  → " + label + " MEDIAN: " + median + " ms");
  print("");
  return median;
}

const baselineEmber = benchmark("stg_ember_electricity", emberQueryPipeline, "Ember CO2 query", 3);
const baselineCharging = benchmark("charging_stations", chargingPipeline, "Charging analysis", 3);
const baselineAnalytics = benchmark("vehicles", analyticsPipeline, "Full analytics", 3);

// ============================================================================
// 2. INDEX CREATION
// ============================================================================
print("");
print("── 2. INDEX CREATION ───────────────────────────────────────");
print("");

// 2a. Compound index on stg_ember_electricity for CO2 intensity lookups
print("Creating index on stg_ember_electricity (Area, Category, Subcategory, Variable, Unit, Year)...");
db.stg_ember_electricity.createIndex(
  { Area: 1, Category: 1, Subcategory: 1, Variable: 1, Unit: 1, Year: 1 },
  { name: "idx_ember_co2_lookup" }
);
print("  Done.");

// 2b. Compound index on country_year_data
print("Creating index on country_year_data (country_code, year)...");
db.country_year_data.createIndex(
  { country_code: 1, year: 1 },
  { name: "idx_cyd_country_year" }
);
print("  Done.");

// 2c. Index on vehicles for fuel_type filtering
print("Creating index on vehicles (fuel_type)...");
db.vehicles.createIndex(
  { fuel_type: 1 },
  { name: "idx_vehicles_fuel_type" }
);
print("  Done.");

// 2d. Compound index on charging_stations for country + power_class
print("Creating index on charging_stations (country_code, power_class)...");
db.charging_stations.createIndex(
  { country_code: 1, power_class: 1 },
  { name: "idx_charging_country_class" }
);
print("  Done.");

// 2e. Index on countries
print("Creating index on countries (country_code)...");
db.countries.createIndex(
  { country_code: 1 },
  { name: "idx_countries_code", unique: true }
);
print("  Done.");

// ── Show all indexes with getIndexes() ──
print("");
print("── INDEXES OVERVIEW (getIndexes) ──");
["stg_ember_electricity", "country_year_data", "vehicles", "charging_stations", "countries"].forEach(c => {
  print("  " + c + ":");
  db[c].getIndexes().forEach(idx => {
    print("    - " + idx.name + ": " + JSON.stringify(idx.key));
  });
});
print("");

// ── Post-Index Explain ──
print("Explain plan AFTER indexing (stg_ember_electricity):");
const explainAfter = db.stg_ember_electricity.explain("executionStats").aggregate(emberQueryPipeline);
const statsAfter = getExplainStats(explainAfter);
print("  Execution time:    " + statsAfter.timeMs + " ms");
print("  Total docs examined: " + statsAfter.docsExamined);
print("  Total keys examined: " + statsAfter.keysExamined);
print("  Winning plan stage: " + JSON.stringify(statsAfter.stage));
print("");

// ── Post-Index Timings ──
print("── POST-INDEX TIMINGS ──");
print("");

const indexedEmber = benchmark("stg_ember_electricity", emberQueryPipeline, "Ember CO2 query (indexed)", 3);
const indexedCharging = benchmark("charging_stations", chargingPipeline, "Charging analysis (indexed)", 3);
const indexedAnalytics = benchmark("vehicles", analyticsPipeline, "Full analytics (indexed)", 3);

// ============================================================================
// 3. MATERIALIZED VIEW — pre-compute analytics result
// ============================================================================
print("");
print("── 3. MATERIALIZED VIEW ────────────────────────────────────");
print("");

// Pre-compute the full decision result into mv_ev_decision
print("Creating materialized view mv_ev_decision...");

const mvPipeline = [
  ...analyticsPipeline.slice(0, -1), // all stages except final $sort
  {
    $addFields: {
      recommend_ev: {
        $cond: {
          if: {
            $and: [
              { $lte: ["$ev_cost", { $multiply: ["$ice_cost", 1.10] }] },
              { $lte: ["$ev_co2", "$ice_co2"] }
            ]
          },
          then: 1,
          else: 0
        }
      },
      // Mirror SQL analytics_view: ratio_cost = ev/ice cost, ratio_co2 = ev/ice CO2.
      ratio_cost: { $round: [{ $divide: ["$ev_cost", "$ice_cost"] }, 2] },
      ratio_co2: { $round: [{ $divide: ["$ev_co2", "$ice_co2"] }, 2] }
    }
  },
  { $sort: { country: 1 } },
  { $out: "mv_ev_decision" }
];

db.vehicles.aggregate(mvPipeline);
print("  mv_ev_decision created with " + db.mv_ev_decision.countDocuments() + " documents.");

// Now querying the materialized view is instant
print("");
print("── MATERIALIZED VIEW TIMINGS ──");
const mvTiming = benchmark("mv_ev_decision", [{ $match: {} }], "MV direct read", 3);

// ============================================================================
// SUMMARY
// ============================================================================
print("");
print("════════════════════════════════════════════════════════════");
print("PERFORMANCE SUMMARY");
print("════════════════════════════════════════════════════════════");
print("");
print("┌──────────────────────────┬────────────┬────────────┬────────────┐");
print("│ Query                    │ Baseline   │ Indexed    │ MV         │");
print("├──────────────────────────┼────────────┼────────────┼────────────┤");
print("│ Ember CO2 intensity      │ " + String(baselineEmber).padStart(6) + " ms  │ " + String(indexedEmber).padStart(6) + " ms  │     n/a    │");
print("│ Charging analysis        │ " + String(baselineCharging).padStart(6) + " ms  │ " + String(indexedCharging).padStart(6) + " ms  │     n/a    │");
print("│ Full analytics pipeline  │ " + String(baselineAnalytics).padStart(6) + " ms  │ " + String(indexedAnalytics).padStart(6) + " ms  │ " + String(mvTiming).padStart(6) + " ms  │");
print("└──────────────────────────┴────────────┴────────────┴────────────┘");
print("");

// Improvement factors
if (baselineEmber > 0 && indexedEmber > 0) {
  print("Ember query speedup: " + (baselineEmber / indexedEmber).toFixed(1) + "x faster with index");
}
if (baselineAnalytics > 0 && mvTiming > 0) {
  print("Analytics speedup:   " + (baselineAnalytics / mvTiming).toFixed(1) + "x faster with materialized view");
}
print("");

print("Optimization approaches used:");
print("  1. Execution Plan Analysis (explain) — identified COLLSCAN bottleneck");
print("  2. Compound Indexes — idx_ember_co2_lookup, idx_cyd_country_year, idx_vehicles_fuel_type, idx_charging_country_class");
print("  3. Materialized View — mv_ev_decision pre-computes the full analytics result");
print("");
print("Performance optimization complete.");
