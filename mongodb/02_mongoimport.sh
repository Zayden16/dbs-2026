#!/bin/bash
# ============================================================================
# DBS Project: "Are EVs Really Better?"
# MongoDB Data Loading — mongoimport for all 10 datasets
# ============================================================================
# Usage: bash 02_mongoimport.sh
# Prerequisites: mongoimport installed (part of MongoDB Database Tools)
#                .env file in the repo root (copy from .env.example)
# ============================================================================

# Load credentials from .env in the repo root
set -a
[ -f "../.env" ] && . ../.env
[ -f ".env" ] && . ./.env
set +a

MONGO_URI="${MONGO_URI:?Set MONGO_URI in .env}/?authSource=admin"
DB="ev_project"
DATA_DIR="../datasets"

echo "============================================"
echo "Loading datasets into MongoDB (ev_project)"
echo "============================================"

# --- Drop existing staging collections ---
echo "[0/10] Dropping existing staging collections..."
mongosh "$MONGO_URI" --quiet --eval "
  use('$DB');
  ['stg_cars_2025','stg_co2','stg_ev_specs','stg_iea_ev',
   'stg_charging_station','stg_country_summary','stg_ember_electricity',
   'stg_ch_elec_prices','stg_eurostat_elec_prices','stg_fuel_prices'].forEach(c => {
    db[c].drop();
  });
  print('Staging collections dropped.');
"

# --- 1. Cars Datasets 2025 (1,218 rows) ---
echo "[1/10] Loading Cars Datasets 2025..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_cars_2025" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/Cars Datasets 2025.csv"

# --- 2. CO2 Emissions (7,385 rows) ---
echo "[2/10] Loading CO2 Emissions..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_co2" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/co2.csv"

# --- 3. EV Specs Database (67 rows) ---
echo "[3/10] Loading EV Specs..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_ev_specs" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/ev_specs_database.csv"

# --- 4. IEA Global EV Data (12,654 rows) ---
echo "[4/10] Loading IEA Global EV Data..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_iea_ev" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/iea_global_ev_data_2024.csv"

# --- 5. Charging Stations (242,417 rows) ---
echo "[5/10] Loading Charging Stations..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_charging_station" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/charging_station.csv"

# --- 6. Country Summary (121 rows) ---
echo "[6/10] Loading Country Summary..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_country_summary" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/country_summary.csv"

# --- 7. Ember Yearly Electricity (359,796 rows) ---
echo "[7/10] Loading Ember Electricity Data..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_ember_electricity" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/ember_yearly_electricity.csv"

# --- 8. Swiss Electricity Prices (16 rows) ---
echo "[8/10] Loading Swiss Electricity Prices..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_ch_elec_prices" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/ch_electricity_prices_elcom.csv"

# --- 9. Eurostat Electricity Prices (73 rows) ---
echo "[9/10] Loading Eurostat Electricity Prices..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_eurostat_elec_prices" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/eurostat_elec_prices_defr.csv"

# --- 10. Fuel Prices (3 rows) ---
echo "[10/10] Loading Fuel Prices..."
mongoimport --uri="$MONGO_URI" \
  --db="$DB" \
  --collection="stg_fuel_prices" \
  --type=csv \
  --headerline \
  --file="$DATA_DIR/fuel_prices.csv"

# --- Verification ---
echo ""
echo "============================================"
echo "Verifying row counts..."
echo "============================================"
mongosh "$MONGO_URI" --quiet --eval "
  use('$DB');
  const collections = [
    'stg_cars_2025', 'stg_co2', 'stg_ev_specs', 'stg_iea_ev',
    'stg_charging_station', 'stg_country_summary', 'stg_ember_electricity',
    'stg_ch_elec_prices', 'stg_eurostat_elec_prices', 'stg_fuel_prices'
  ];
  let total = 0;
  collections.forEach(c => {
    const count = db[c].countDocuments();
    total += count;
    print(c.padEnd(30) + count);
  });
  print('─'.repeat(40));
  print('TOTAL'.padEnd(30) + total);
"

echo ""
echo "Data loading complete."
