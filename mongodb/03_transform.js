// ============================================================================
// DBS Project: "Are EVs Really Better?"
// MongoDB ELT Transformation — Aggregation Pipelines
// ============================================================================
// Run with: mongosh "$MONGO_URI" 03_transform.js
// ============================================================================
// Transforms staging collections (stg_*) into the 4 target collections.
// All transformation happens INSIDE MongoDB using aggregation pipelines,
// following the ELT principle (Extract → Load → Transform in DB).
// ============================================================================

use("ev_project");

// ============================================================================
// STEP 0: Drop target collections for idempotent re-runs
// ============================================================================
print("Dropping target collections...");
db.vehicles.drop();
db.countries.drop();
db.country_year_data.drop();
db.charging_stations.drop();

// ============================================================================
// STEP 1: Transform stg_co2 → vehicles (ICE vehicles with embedded emissions)
// ============================================================================
// Source: co2.csv via stg_co2 — 7,385 ICE vehicle entries
// Transformation:
//   - Map fuel type codes: D=Diesel, E=E85, N=Natural Gas, X=Regular Gasoline, Z=Premium Gasoline
//   - Embed ice_emission subdocument (denormalization)
//   - Set fuel_type to readable string
// ============================================================================
print("Transforming ICE vehicles from stg_co2...");

db.stg_co2.aggregate([
  {
    $addFields: {
      fuel_type_mapped: {
        $switch: {
          branches: [
            { case: { $eq: ["$Fuel Type", "D"] }, then: "Diesel" },
            { case: { $eq: ["$Fuel Type", "E"] }, then: "E85" },
            { case: { $eq: ["$Fuel Type", "N"] }, then: "Natural Gas" },
            { case: { $eq: ["$Fuel Type", "X"] }, then: "Petrol" },
            { case: { $eq: ["$Fuel Type", "Z"] }, then: "Premium Petrol" }
          ],
          default: "Unknown"
        }
      }
    }
  },
  {
    $project: {
      _id: 0,
      make: "$Make",
      model: "$Model",
      fuel_type: "$fuel_type_mapped",
      vehicle_class: "$Vehicle Class",
      ice_emission: {
        engine_size_l: { $toDouble: "$Engine Size(L)" },
        cylinders: { $toInt: "$Cylinders" },
        transmission: "$Transmission",
        fuel_consumption_city: { $toDouble: "$Fuel Consumption City (L/100 km)" },
        fuel_consumption_hwy: { $toDouble: "$Fuel Consumption Hwy (L/100 km)" },
        fuel_consumption_comb: { $toDouble: "$Fuel Consumption Comb (L/100 km)" },
        co2_emissions_gkm: { $toInt: "$CO2 Emissions(g/km)" }
      }
    }
  },
  { $out: "vehicles" }
]);

print("  ICE vehicles inserted: " + db.vehicles.countDocuments());

// ============================================================================
// STEP 2: Transform stg_ev_specs → vehicles (EV vehicles with embedded specs)
// ============================================================================
// Source: ev_specs_database.csv via stg_ev_specs — 67 EV entries
// Transformation:
//   - Split "Car model" into make + model (first word = make)
//   - Parse price from "K$" format
//   - Derive energy_consumption_kwh_100km = battery / range * 100
//   - Embed ev_spec subdocument
//   - Use $merge to append to existing vehicles collection
// ============================================================================
print("Transforming EV vehicles from stg_ev_specs...");

db.stg_ev_specs.aggregate([
  {
    $match: {
      "Car model": { $ne: null, $ne: "" }
    }
  },
  {
    $addFields: {
      // Split car model: first word = make, rest = model
      _name_parts: { $split: ["$Car model", " "] },
      _battery: { $convert: { input: "$Battery_Capacity_kWh", to: "double", onError: null, onNull: null } },
      _range: { $convert: { input: "$Autonomy_WLTP_Km", to: "double", onError: null, onNull: null } }
    }
  },
  {
    $addFields: {
      make: { $arrayElemAt: ["$_name_parts", 0] },
      model: {
        $reduce: {
          input: { $slice: ["$_name_parts", 1, { $subtract: [{ $size: "$_name_parts" }, 1] }] },
          initialValue: "",
          in: {
            $cond: {
              if: { $eq: ["$$value", ""] },
              then: "$$this",
              else: { $concat: ["$$value", " ", "$$this"] }
            }
          }
        }
      }
    }
  },
  {
    $project: {
      _id: 0,
      make: 1,
      model: 1,
      fuel_type: { $literal: "Electric" },
      vehicle_class: {
        $cond: {
          if: { $or: [{ $eq: ["$Car_type", "empty"] }, { $eq: ["$Car_type", null] }] },
          then: null,
          else: "$Car_type"
        }
      },
      price_usd: {
        $let: {
          vars: {
            parsed: { $convert: { input: "$Approx_Release_price_order_in_K$", to: "double", onError: null, onNull: null } }
          },
          in: { $cond: { if: { $gt: ["$$parsed", 0] }, then: { $multiply: ["$$parsed", 1000] }, else: null } }
        }
      },
      ev_spec: {
        battery_capacity_kwh: "$_battery",
        range_wltp_km: { $convert: { input: "$Autonomy_WLTP_Km", to: "int", onError: null, onNull: null } },
        energy_consumption_kwh_100km: {
          $cond: {
            if: { $and: [{ $gt: ["$_battery", 0] }, { $gt: ["$_range", 0] }] },
            then: { $round: [{ $multiply: [{ $divide: ["$_battery", "$_range"] }, 100] }, 1] },
            else: null
          }
        },
        dc_charge_power_kw: { $convert: { input: "$DC_nominal_charge_power_KW", to: "int", onError: null, onNull: null } },
        release_year: { $convert: { input: "$year", to: "int", onError: null, onNull: null } }
      }
    }
  },
  {
    $merge: {
      into: "vehicles",
      whenMatched: "keepExisting",
      whenNotMatched: "insert"
    }
  }
]);

print("  Total vehicles after EV merge: " + db.vehicles.countDocuments());

// ============================================================================
// STEP 3: Transform stg_cars_2025 → vehicles (additional car specs)
// ============================================================================
// Source: Cars Datasets 2025.csv — 1,218 entries (ICE + EV mixed)
// Transformation:
//   - Parse embedded units: "$1,100,000" → 1100000, "963 hp" → 963
//   - Standardize fuel types
//   - Merge into vehicles collection
// ============================================================================
print("Transforming car specs from stg_cars_2025...");

db.stg_cars_2025.aggregate([
  {
    $match: {
      "Company Names": { $ne: null, $ne: "" }
    }
  },
  {
    $addFields: {
      // Parse price: remove $, commas, handle ranges (take first value)
      // Note: $literal used because "$" alone is interpreted as a field path
      _price_clean: {
        $trim: {
          input: {
            $replaceAll: {
              input: {
                $replaceAll: {
                  input: {
                    $arrayElemAt: [{ $split: [{ $ifNull: ["$Cars Prices", "0"] }, " - "] }, 0]
                  },
                  find: { $literal: "$" }, replacement: ""
                }
              },
              find: ",", replacement: ""
            }
          }
        }
      },
      // Parse horsepower: "963 hp" → 963
      _hp_clean: {
        $trim: {
          input: {
            $arrayElemAt: [{ $split: [{ $ifNull: ["$HorsePower", "0"] }, " "] }, 0]
          }
        }
      },
      // Standardize fuel type
      _fuel: {
        $switch: {
          branches: [
            { case: { $regexMatch: { input: { $toLower: { $ifNull: ["$Fuel Types", ""] } }, regex: /electric/ } }, then: "Electric" },
            { case: { $regexMatch: { input: { $toLower: { $ifNull: ["$Fuel Types", ""] } }, regex: /diesel/ } }, then: "Diesel" },
            { case: { $regexMatch: { input: { $toLower: { $ifNull: ["$Fuel Types", ""] } }, regex: /hybrid/ } }, then: "Hybrid" },
            { case: { $regexMatch: { input: { $toLower: { $ifNull: ["$Fuel Types", ""] } }, regex: /petrol|gasoline|benzin/ } }, then: "Petrol" }
          ],
          default: { $ifNull: ["$Fuel Types", "Unknown"] }
        }
      }
    }
  },
  {
    $project: {
      _id: 0,
      make: { $toUpper: "$Company Names" },
      model: "$Cars Names",
      fuel_type: "$_fuel",
      price_usd: {
        $convert: {
          input: "$_price_clean",
          to: "double",
          onError: null,
          onNull: null
        }
      },
      horsepower: {
        $convert: {
          input: "$_hp_clean",
          to: "int",
          onError: null,
          onNull: null
        }
      },
      seats: {
        $convert: {
          input: "$Seats",
          to: "int",
          onError: null,
          onNull: null
        }
      }
    }
  },
  {
    $merge: {
      into: "vehicles",
      whenMatched: "keepExisting",
      whenNotMatched: "insert"
    }
  }
]);

print("  Total vehicles after cars_2025 merge: " + db.vehicles.countDocuments());

// ============================================================================
// STEP 4: Build countries collection (fuel prices + charging summary embedded)
// ============================================================================
// Sources: stg_fuel_prices + stg_country_summary
// Denormalization: embed charging_summary directly in the country document
// ============================================================================
print("Building countries collection...");

// Country name mapping
const countryMap = {
  "Switzerland": "CH",
  "Germany": "DE",
  "France": "FR"
};

// First, insert base country data from fuel_prices
db.stg_fuel_prices.aggregate([
  {
    $match: {
      Country: { $in: ["Switzerland", "Germany", "France"] }
    }
  },
  {
    $addFields: {
      country_code: {
        $switch: {
          branches: [
            { case: { $eq: ["$Country", "Switzerland"] }, then: "CH" },
            { case: { $eq: ["$Country", "Germany"] },    then: "DE" },
            { case: { $eq: ["$Country", "France"] },     then: "FR" }
          ],
          default: "XX"
        }
      }
    }
  },
  {
    $lookup: {
      from: "stg_country_summary",
      localField: "country_code",
      foreignField: "country_code",
      as: "charging"
    }
  },
  { $unwind: { path: "$charging", preserveNullAndEmptyArrays: true } },
  {
    $project: {
      _id: 0,
      country_code: 1,
      country_name: "$Country",
      petrol_price_eur_per_l: { $toDouble: "$Petrol_EUR_per_L" },
      diesel_price_eur_per_l: { $toDouble: "$Diesel_EUR_per_L" },
      charging_summary: {
        station_count: { $toInt: { $ifNull: ["$charging.station_count", 0] } },
        port_count: { $toInt: { $ifNull: ["$charging.port_count", 0] } },
        fast_station_share: { $round: [{ $toDouble: { $ifNull: ["$charging.fast_station_share", 0] } }, 4] },
        fast_port_share: { $round: [{ $toDouble: { $ifNull: ["$charging.fast_port_share", 0] } }, 4] }
      }
    }
  },
  { $out: "countries" }
]);

print("  Countries inserted: " + db.countries.countDocuments());

// ============================================================================
// STEP 5: Build country_year_data — the big denormalized aggregate
// ============================================================================
// Combines: electricity_price + grid_mix + ev_adoption per country-year
// Sources: stg_ember_electricity, stg_ch_elec_prices, stg_eurostat_elec_prices, stg_iea_ev
// ============================================================================
print("Building country_year_data...");

// --- 5a: Extract CO2 intensity per country-year from Ember ---
print("  5a: Extracting CO2 intensity from Ember...");
db.stg_ember_electricity.aggregate([
  {
    $match: {
      Area: { $in: ["Switzerland", "Germany", "France"] },
      Category: "Power sector emissions",
      Subcategory: "CO2 intensity",
      Variable: "CO2 intensity",
      Unit: "gCO2/kWh"
    }
  },
  {
    $addFields: {
      country_code: {
        $switch: {
          branches: [
            { case: { $eq: ["$Area", "Switzerland"] }, then: "CH" },
            { case: { $eq: ["$Area", "Germany"] },    then: "DE" },
            { case: { $eq: ["$Area", "France"] },     then: "FR" }
          ],
          default: "XX"
        }
      }
    }
  },
  {
    $group: {
      _id: { country_code: "$country_code", year: { $toInt: "$Year" } },
      co2_intensity_gkwh: { $avg: { $toDouble: "$Value" } }
    }
  },
  {
    $project: {
      _id: 0,
      country_code: "$_id.country_code",
      year: "$_id.year",
      co2_intensity_gkwh: 1
    }
  },
  { $out: "tmp_co2_intensity" }
]);

// --- 5b: Extract grid mix (generation sources) per country-year ---
print("  5b: Extracting grid mix from Ember...");
db.stg_ember_electricity.aggregate([
  {
    $match: {
      Area: { $in: ["Switzerland", "Germany", "France"] },
      Category: "Electricity generation",
      Subcategory: "Fuel",
      Unit: "TWh"
    }
  },
  {
    $addFields: {
      country_code: {
        $switch: {
          branches: [
            { case: { $eq: ["$Area", "Switzerland"] }, then: "CH" },
            { case: { $eq: ["$Area", "Germany"] },    then: "DE" },
            { case: { $eq: ["$Area", "France"] },     then: "FR" }
          ],
          default: "XX"
        }
      }
    }
  },
  {
    $group: {
      _id: { country_code: "$country_code", year: { $toInt: "$Year" } },
      grid_mix: {
        $push: {
          source: "$Variable",
          generation_twh: { $round: [{ $toDouble: { $ifNull: ["$Value", 0] } }, 2] }
        }
      }
    }
  },
  {
    $project: {
      _id: 0,
      country_code: "$_id.country_code",
      year: "$_id.year",
      grid_mix: 1
    }
  },
  { $out: "tmp_grid_mix" }
]);

// --- 5c: Extract Swiss electricity prices (Rappen → EUR) ---
print("  5c: Processing Swiss electricity prices...");
db.stg_ch_elec_prices.aggregate([
  {
    $project: {
      _id: 0,
      country_code: { $literal: "CH" },
      year: { $toInt: "$year" },
      // avgPrice is in Rappen/kWh → convert to EUR/kWh: (Rp / 100) * 0.94
      electricity_price_eur_per_kwh: {
        $round: [{ $multiply: [{ $divide: [{ $toDouble: "$avgPrice" }, 100] }, 0.94] }, 4]
      }
    }
  },
  { $out: "tmp_elec_prices_ch" }
]);

// --- 5d: Extract DE/FR electricity prices ---
print("  5d: Processing Eurostat electricity prices...");
db.stg_eurostat_elec_prices.aggregate([
  {
    $addFields: {
      // Parse period "2022-S1" → year 2022, take annual average later
      _year: { $toInt: { $substr: ["$period", 0, 4] } }
    }
  },
  {
    $group: {
      _id: { country_code: "$country_code", year: "$_year" },
      electricity_price_eur_per_kwh: { $avg: { $toDouble: "$price_eur_per_kwh" } }
    }
  },
  {
    $project: {
      _id: 0,
      country_code: "$_id.country_code",
      year: "$_id.year",
      electricity_price_eur_per_kwh: { $round: ["$electricity_price_eur_per_kwh", 4] }
    }
  },
  { $out: "tmp_elec_prices_defr" }
]);

// --- 5e: Combine all electricity prices into one temp collection ---
print("  5e: Merging electricity prices...");
db.tmp_elec_prices_ch.aggregate([
  {
    $merge: {
      into: "tmp_elec_prices",
      whenMatched: "replace",
      whenNotMatched: "insert"
    }
  }
]);
db.tmp_elec_prices_defr.aggregate([
  {
    $merge: {
      into: "tmp_elec_prices",
      whenMatched: "replace",
      whenNotMatched: "insert"
    }
  }
]);

// --- 5f: Extract EV adoption data from IEA ---
print("  5f: Processing IEA EV adoption data...");
db.stg_iea_ev.aggregate([
  {
    $match: {
      region: { $in: ["Switzerland", "Germany", "France"] },
      mode: "Cars",
      parameter: { $in: ["EV sales", "EV stock", "EV sales share", "EV stock share"] },
      powertrain: { $in: ["BEV", "PHEV"] }
    }
  },
  {
    $addFields: {
      country_code: {
        $switch: {
          branches: [
            { case: { $eq: ["$region", "Switzerland"] }, then: "CH" },
            { case: { $eq: ["$region", "Germany"] },    then: "DE" },
            { case: { $eq: ["$region", "France"] },     then: "FR" }
          ],
          default: "XX"
        }
      }
    }
  },
  {
    $group: {
      _id: { country_code: "$country_code", year: { $toInt: "$year" } },
      entries: {
        $push: {
          parameter: "$parameter",
          powertrain: "$powertrain",
          value: { $toDouble: { $ifNull: ["$value", 0] } }
        }
      }
    }
  },
  {
    $addFields: {
      ev_adoption: {
        bev_sales: {
          $sum: {
            $map: {
              input: { $filter: { input: "$entries", cond: { $and: [{ $eq: ["$$this.parameter", "EV sales"] }, { $eq: ["$$this.powertrain", "BEV"] }] } } },
              in: "$$this.value"
            }
          }
        },
        phev_sales: {
          $sum: {
            $map: {
              input: { $filter: { input: "$entries", cond: { $and: [{ $eq: ["$$this.parameter", "EV sales"] }, { $eq: ["$$this.powertrain", "PHEV"] }] } } },
              in: "$$this.value"
            }
          }
        },
        bev_stock: {
          $sum: {
            $map: {
              input: { $filter: { input: "$entries", cond: { $and: [{ $eq: ["$$this.parameter", "EV stock"] }, { $eq: ["$$this.powertrain", "BEV"] }] } } },
              in: "$$this.value"
            }
          }
        },
        phev_stock: {
          $sum: {
            $map: {
              input: { $filter: { input: "$entries", cond: { $and: [{ $eq: ["$$this.parameter", "EV stock"] }, { $eq: ["$$this.powertrain", "PHEV"] }] } } },
              in: "$$this.value"
            }
          }
        },
        sales_share_pct: {
          $sum: {
            $map: {
              input: { $filter: { input: "$entries", cond: { $and: [{ $eq: ["$$this.parameter", "EV sales share"] }, { $eq: ["$$this.powertrain", "BEV"] }] } } },
              in: "$$this.value"
            }
          }
        },
        stock_share_pct: {
          $sum: {
            $map: {
              input: { $filter: { input: "$entries", cond: { $and: [{ $eq: ["$$this.parameter", "EV stock share"] }, { $eq: ["$$this.powertrain", "BEV"] }] } } },
              in: "$$this.value"
            }
          }
        }
      }
    }
  },
  {
    $project: {
      _id: 0,
      country_code: "$_id.country_code",
      year: "$_id.year",
      ev_adoption: 1
    }
  },
  { $out: "tmp_ev_adoption" }
]);

// --- 5g: Final assembly — join all temp collections into country_year_data ---
print("  5g: Assembling country_year_data...");
db.tmp_co2_intensity.aggregate([
  {
    $lookup: {
      from: "tmp_elec_prices",
      let: { cc: "$country_code", yr: "$year" },
      pipeline: [
        { $match: { $expr: { $and: [{ $eq: ["$country_code", "$$cc"] }, { $eq: ["$year", "$$yr"] }] } } }
      ],
      as: "price_data"
    }
  },
  { $unwind: { path: "$price_data", preserveNullAndEmptyArrays: true } },
  {
    $lookup: {
      from: "tmp_grid_mix",
      let: { cc: "$country_code", yr: "$year" },
      pipeline: [
        { $match: { $expr: { $and: [{ $eq: ["$country_code", "$$cc"] }, { $eq: ["$year", "$$yr"] }] } } }
      ],
      as: "mix_data"
    }
  },
  { $unwind: { path: "$mix_data", preserveNullAndEmptyArrays: true } },
  {
    $lookup: {
      from: "tmp_ev_adoption",
      let: { cc: "$country_code", yr: "$year" },
      pipeline: [
        { $match: { $expr: { $and: [{ $eq: ["$country_code", "$$cc"] }, { $eq: ["$year", "$$yr"] }] } } }
      ],
      as: "adoption_data"
    }
  },
  { $unwind: { path: "$adoption_data", preserveNullAndEmptyArrays: true } },
  {
    $project: {
      _id: 0,
      country_code: 1,
      year: 1,
      co2_intensity_gkwh: 1,
      electricity_price_eur_per_kwh: { $ifNull: ["$price_data.electricity_price_eur_per_kwh", null] },
      grid_mix: { $ifNull: ["$mix_data.grid_mix", []] },
      ev_adoption: { $ifNull: ["$adoption_data.ev_adoption", null] }
    }
  },
  { $sort: { country_code: 1, year: 1 } },
  { $out: "country_year_data" }
]);

print("  country_year_data documents: " + db.country_year_data.countDocuments());

// ============================================================================
// STEP 6: Transform charging stations (filter to CH/DE/FR, add GeoJSON)
// ============================================================================
print("Transforming charging stations...");

db.stg_charging_station.aggregate([
  {
    $match: {
      country_code: { $in: ["CH", "DE", "FR"] }
    }
  },
  {
    $project: {
      _id: 0,
      station_id: { $convert: { input: "$id", to: "int", onError: 0, onNull: 0 } },
      name: "$name",
      city: "$city",
      state_province: "$state_province",
      country_code: "$country_code",
      location: {
        type: { $literal: "Point" },
        coordinates: [
          { $convert: { input: "$longitude", to: "double", onError: 0, onNull: 0 } },
          { $convert: { input: "$latitude", to: "double", onError: 0, onNull: 0 } }
        ]
      },
      ports: { $convert: { input: "$ports", to: "int", onError: 0, onNull: 0 } },
      power_kw: { $convert: { input: "$power_kw", to: "double", onError: 0, onNull: 0 } },
      power_class: "$power_class",
      is_fast_dc: { $eq: [{ $toLower: { $convert: { input: "$is_fast_dc", to: "string", onError: "false", onNull: "false" } } }, "true"] }
    }
  },
  { $out: "charging_stations" }
]);

print("  Charging stations (CH/DE/FR): " + db.charging_stations.countDocuments());

// ============================================================================
// STEP 7: Clean up temporary collections
// ============================================================================
print("Cleaning up temporary collections...");
db.tmp_co2_intensity.drop();
db.tmp_grid_mix.drop();
db.tmp_elec_prices_ch.drop();
db.tmp_elec_prices_defr.drop();
db.tmp_elec_prices.drop();
db.tmp_ev_adoption.drop();

// ============================================================================
// VERIFICATION
// ============================================================================
print("");
print("============================================");
print("Transformation complete. Collection counts:");
print("============================================");
print("  vehicles:          " + db.vehicles.countDocuments());
print("  countries:         " + db.countries.countDocuments());
print("  country_year_data: " + db.country_year_data.countDocuments());
print("  charging_stations: " + db.charging_stations.countDocuments());
print("");

// Quick sanity check: show a sample country_year_data for CH 2022
print("Sample: country_year_data for CH, 2022:");
printjson(db.country_year_data.findOne({ country_code: "CH", year: 2022 }));
