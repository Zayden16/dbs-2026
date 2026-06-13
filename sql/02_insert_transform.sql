-- ELT: INSERT ... SELECT from stg_* into 3NF target tables (ev_project).
-- Reference: er_model.txt, HSLU ELT requirement.
-- Prerequisites: 01_truncate_target.sql (optional if first load).
USE ev_project;

-- ---------------------------------------------------------------------------
-- COUNTRY (CH, DE, FR) — fuel prices are illustrative reference values (EUR/L)
-- for the use-case year — replace if you ingest a dedicated fuel-price source.
-- ---------------------------------------------------------------------------
INSERT INTO country (country_code, country_name, petrol_price_eur_per_l, diesel_price_eur_per_l)
VALUES
  ('CH', 'Switzerland', 1.859, 1.929),
  ('DE', 'Germany',     1.749, 1.649),
  ('FR', 'France',      1.779, 1.699);

-- ---------------------------------------------------------------------------
-- ELECTRICITY_PRICE — Eurostat (DE, FR) + Swiss BFE-style averages (CH, ct/kWh → EUR/kWh)
-- ---------------------------------------------------------------------------
INSERT INTO electricity_price (country_code, year, half_year, price_eur_per_kwh)
SELECT
  country_code,
  CAST(SUBSTRING(period, 1, 4) AS UNSIGNED) AS y,
  CASE SUBSTRING(period, 6, 1)
    WHEN '1' THEN 1
    WHEN '2' THEN 2
    ELSE NULL
  END AS hy,
  price_eur_per_kwh
FROM stg_eurostat_elec_prices
WHERE country_code IN ('DE', 'FR')
  AND period REGEXP '^[0-9]{4}-S[12]$'
  AND CAST(SUBSTRING(period, 1, 4) AS UNSIGNED) >= 2015;

INSERT INTO electricity_price (country_code, year, half_year, price_eur_per_kwh)
SELECT
  'CH',
  year,
  NULL,
  -- ElCom avg_price is in Rappen/kWh: /100 = CHF/kWh, then x0.94 = EUR/kWh.
  (avg_price / 100.0) * 0.94
FROM stg_ch_elec_prices;

-- ---------------------------------------------------------------------------
-- GRID_MIX — Ember long-form (TWh + % share per fuel)
-- ---------------------------------------------------------------------------
INSERT INTO grid_mix (country_code, year, source_type, generation_twh, share_pct, co2_intensity_gkwh)
SELECT
  CASE e_twh.area
    WHEN 'France' THEN 'FR'
    WHEN 'Germany' THEN 'DE'
    WHEN 'Switzerland' THEN 'CH'
  END,
  e_twh.year,
  e_twh.variable,
  e_twh.value,
  e_pct.value,
  NULL
FROM stg_ember_electricity e_twh
INNER JOIN stg_ember_electricity e_pct
  ON e_pct.area = e_twh.area
 AND e_pct.year = e_twh.year
 AND e_pct.variable = e_twh.variable
 AND e_pct.category = 'Electricity generation'
 AND e_pct.subcategory = 'Fuel'
 AND e_pct.unit = '%'
WHERE e_twh.category = 'Electricity generation'
  AND e_twh.subcategory = 'Fuel'
  AND e_twh.unit = 'TWh'
  AND e_twh.area IN ('France', 'Germany', 'Switzerland')
  AND e_twh.year BETWEEN 2018 AND 2023;

-- ---------------------------------------------------------------------------
-- CHARGING (OpenChargeMap-derived staging) — project focus countries only
-- ---------------------------------------------------------------------------
INSERT INTO charging_country_summary (
  country_code, station_count, port_count, fast_station_share, fast_port_share
)
SELECT
  country_code,
  station_count,
  port_count,
  fast_station_share,
  fast_port_share
FROM stg_country_summary
WHERE country_code IN ('CH', 'DE', 'FR');

INSERT INTO charging_station (
  station_id, name, city, state_province, country_code,
  latitude, longitude, ports, power_kw, power_class, is_fast_dc
)
SELECT
  s.id,
  s.name,
  s.city,
  s.state_province,
  s.country_code,
  s.latitude,
  s.longitude,
  s.ports,
  s.power_kw,
  s.power_class,
  CASE
    WHEN LOWER(TRIM(s.is_fast_dc)) IN ('1', 'true', 'yes', 'y') THEN 1
    WHEN LOWER(TRIM(s.is_fast_dc)) IN ('0', 'false', 'no', 'n') THEN 0
    ELSE NULL
  END
FROM stg_charging_station s
WHERE s.country_code IN ('CH', 'DE', 'FR')
  AND s.id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- EV_ADOPTION — IEA, passenger cars only (mode = Cars)
-- ---------------------------------------------------------------------------
INSERT INTO ev_adoption (
  country_code, year, powertrain, ev_sales, ev_stock,
  ev_sales_share_pct, ev_stock_share_pct
)
SELECT
  CASE b.region
    WHEN 'Switzerland' THEN 'CH'
    WHEN 'Germany' THEN 'DE'
    WHEN 'France' THEN 'FR'
  END,
  b.year,
  'BEV',
  MAX(CASE WHEN b.parameter = 'EV sales' THEN b.value END),
  MAX(CASE WHEN b.parameter = 'EV stock' THEN b.value END),
  NULL,
  NULL
FROM stg_iea_ev b
WHERE b.category = 'Historical'
  AND b.mode = 'Cars'
  AND b.powertrain = 'BEV'
  AND b.parameter IN ('EV sales', 'EV stock')
  AND b.region IN ('Switzerland', 'Germany', 'France')
  AND b.year BETWEEN 2018 AND 2023
GROUP BY b.region, b.year;

INSERT INTO ev_adoption (
  country_code, year, powertrain, ev_sales, ev_stock,
  ev_sales_share_pct, ev_stock_share_pct
)
SELECT
  CASE p.region
    WHEN 'Switzerland' THEN 'CH'
    WHEN 'Germany' THEN 'DE'
    WHEN 'France' THEN 'FR'
  END,
  p.year,
  'PHEV',
  MAX(CASE WHEN p.parameter = 'EV sales' THEN p.value END),
  MAX(CASE WHEN p.parameter = 'EV stock' THEN p.value END),
  NULL,
  NULL
FROM stg_iea_ev p
WHERE p.category = 'Historical'
  AND p.mode = 'Cars'
  AND p.powertrain = 'PHEV'
  AND p.parameter IN ('EV sales', 'EV stock')
  AND p.region IN ('Switzerland', 'Germany', 'France')
  AND p.year BETWEEN 2018 AND 2023
GROUP BY p.region, p.year;

INSERT INTO ev_adoption (
  country_code, year, powertrain, ev_sales, ev_stock,
  ev_sales_share_pct, ev_stock_share_pct
)
SELECT
  CASE e.region
    WHEN 'Switzerland' THEN 'CH'
    WHEN 'Germany' THEN 'DE'
    WHEN 'France' THEN 'FR'
  END,
  e.year,
  'EV',
  NULL,
  NULL,
  MAX(CASE WHEN e.parameter = 'EV sales share' THEN e.value END),
  MAX(CASE WHEN e.parameter = 'EV stock share' THEN e.value END)
FROM stg_iea_ev e
WHERE e.category = 'Historical'
  AND e.mode = 'Cars'
  AND e.powertrain = 'EV'
  AND e.parameter IN ('EV sales share', 'EV stock share')
  AND e.region IN ('Switzerland', 'Germany', 'France')
  AND e.year BETWEEN 2018 AND 2023
GROUP BY e.region, e.year;

-- ---------------------------------------------------------------------------
-- VEHICLE — Cars catalogue (clean VARCHAR staging → typed columns)
-- ---------------------------------------------------------------------------
INSERT INTO vehicle (make, model, fuel_type, vehicle_class, price_usd, horsepower, seats)
SELECT
  NULLIF(TRIM(company_name), ''),
  NULLIF(TRIM(car_name), ''),
  CASE
    WHEN LOWER(TRIM(fuel_type)) LIKE '%plug%' OR LOWER(TRIM(fuel_type)) LIKE '%phev%' THEN 'Plug-in Hybrid'
    WHEN LOWER(TRIM(fuel_type)) LIKE '%electric%' AND LOWER(TRIM(fuel_type)) NOT LIKE '%hybrid%' THEN 'Electric'
    WHEN LOWER(TRIM(fuel_type)) LIKE '%diesel%' THEN 'Diesel'
    WHEN LOWER(TRIM(fuel_type)) LIKE '%petrol%' OR LOWER(TRIM(fuel_type)) LIKE '%gasoline%' THEN 'Petrol'
    WHEN LOWER(TRIM(fuel_type)) LIKE '%hybrid%' THEN 'Hybrid'
    ELSE NULLIF(TRIM(fuel_type), '')
  END,
  NULL,
  CAST(
    NULLIF(
      REGEXP_SUBSTR(
        REPLACE(REPLACE(REPLACE(REPLACE(TRIM(price), '$', ''), ',', ''), ' ', ''), '-', ' '),
        '[0-9]+',
        1,
        1
      ),
      ''
    ) AS DECIMAL(12, 2)
  ),
  CAST(
    NULLIF(REGEXP_SUBSTR(REPLACE(TRIM(horsepower), ',', ''), '[0-9]+', 1, 1), '') AS UNSIGNED
  ),
  CAST(
    NULLIF(REGEXP_SUBSTR(TRIM(seats), '[0-9]+', 1, 1), '') AS UNSIGNED
  )
FROM stg_cars_2025
WHERE TRIM(IFNULL(company_name, '')) <> ''
  AND TRIM(IFNULL(car_name, '')) <> '';

-- Backfill vehicle_class from CO2 registry (any matching ICE row)
UPDATE vehicle v
INNER JOIN (
  SELECT
    UPPER(TRIM(make)) AS mk,
    UPPER(TRIM(model)) AS md,
    MIN(vehicle_class) AS vehicle_class
  FROM stg_co2
  GROUP BY UPPER(TRIM(make)), UPPER(TRIM(model))
) c
  ON UPPER(TRIM(v.make)) = c.mk
 AND UPPER(TRIM(v.model)) = c.md
SET v.vehicle_class = c.vehicle_class
WHERE v.vehicle_class IS NULL;

-- ---------------------------------------------------------------------------
-- ICE_EMISSION — one representative ICE row per vehicle (lowest combined L/100km)
-- ---------------------------------------------------------------------------
INSERT INTO ice_emission (
  vehicle_id, engine_size_l, cylinders, transmission,
  fuel_consumption_city, fuel_consumption_hwy, fuel_consumption_comb, co2_emissions_gkm
)
SELECT
  v.vehicle_id,
  x.engine_size_l,
  x.cylinders,
  x.transmission,
  x.fuel_city,
  x.fuel_hwy,
  x.fuel_comb,
  x.co2_gkm
FROM vehicle v
INNER JOIN (
  SELECT
    UPPER(TRIM(k.make)) AS mk,
    UPPER(TRIM(k.model)) AS md,
    k.engine_size_l,
    k.cylinders,
    k.transmission,
    k.fuel_city,
    k.fuel_hwy,
    k.fuel_comb,
    k.co2_gkm,
    ROW_NUMBER() OVER (
      PARTITION BY UPPER(TRIM(k.make)), UPPER(TRIM(k.model))
      ORDER BY k.fuel_comb ASC, k.co2_gkm ASC
    ) AS rn
  FROM stg_co2 k
  WHERE k.fuel_type IN ('Z', 'D', 'X', 'N')
) x
  ON UPPER(TRIM(v.make)) = x.mk
 AND UPPER(TRIM(v.model)) = x.md
 AND x.rn = 1
WHERE v.fuel_type IN ('Petrol', 'Diesel', 'Hybrid', 'Petrol/Diesel', 'Plug-in Hybrid', 'Petrol/Hybrid', 'Diesel/Petrol', 'Hybrid (Petrol)', 'Petrol, Diesel', 'Petrol/AWD', 'Petrol, Hybrid', 'plug in hyrbrid', 'Petrol/EV');

-- ---------------------------------------------------------------------------
-- EV_SPEC — full EV fleet from the supplemental spec sheet (n = 32 valid EVs).
-- The catalogue (stg_cars_2025) is ICE-dominated, so its EV coverage is partial.
-- To get a defensible EV fleet we take EVERY spec-sheet EV with valid battery &
-- range: missing EVs are added to `vehicle` first (FK), then specs are attached.
-- Consumption is derived: kWh/100km = battery_capacity_kwh / range_wltp_km * 100.
-- ---------------------------------------------------------------------------
-- (1) Ensure a vehicle row exists for each valid spec-sheet EV (anti-join).
INSERT INTO vehicle (make, model, fuel_type)
SELECT
  SUBSTRING_INDEX(TRIM(e.car_model), ' ', 1) AS make,
  TRIM(SUBSTRING(TRIM(e.car_model),
        LENGTH(SUBSTRING_INDEX(TRIM(e.car_model), ' ', 1)) + 2)) AS model,
  'Electric'
FROM stg_ev_specs e
WHERE CAST(e.battery_capacity_kwh AS DECIMAL(8, 2)) > 0
  AND CAST(e.autonomy_wltp_km   AS DECIMAL(10, 2)) > 0
  AND NOT EXISTS (
        SELECT 1
        FROM vehicle v
        WHERE v.fuel_type = 'Electric'
          AND REPLACE(UPPER(CONCAT_WS(' ', v.make, v.model)), ' ', '')
            = REPLACE(UPPER(TRIM(e.car_model)), ' ', ''));

-- (2) Attach specs: exactly one row per valid spec-sheet EV (best vehicle match).
INSERT INTO ev_spec (
  vehicle_id, battery_capacity_kwh, range_wltp_km, energy_consumption_kwh_100km,
  dc_charge_power_kw, ac_charge_power_kw, release_year
)
SELECT
  vehicle_id,
  battery_capacity_kwh,
  range_wltp_km,
  energy_consumption_kwh_100km,
  dc_charge_power_kw,
  ac_charge_power_kw,
  release_year
FROM (
  SELECT
    v.vehicle_id,
    CAST(e.battery_capacity_kwh AS DECIMAL(8, 2))  AS battery_capacity_kwh,
    CAST(e.autonomy_wltp_km   AS DECIMAL(10, 2)) AS range_wltp_km,
    ROUND(
      (CAST(e.battery_capacity_kwh AS DECIMAL(8, 2))
       / CAST(e.autonomy_wltp_km   AS DECIMAL(10, 2))) * 100.0, 2
    ) AS energy_consumption_kwh_100km,
    e.dc_charge_power_kw,
    CAST(REGEXP_SUBSTR(e.ac_charge_power, '[0-9]+(\\.[0-9]+)?', 1, 1) AS DECIMAL(6, 2)) AS ac_charge_power_kw,
    e.release_year,
    ROW_NUMBER() OVER (
      PARTITION BY REPLACE(UPPER(TRIM(e.car_model)), ' ', '')
      ORDER BY v.vehicle_id
    ) AS rn
  FROM stg_ev_specs e
  INNER JOIN vehicle v
    ON v.fuel_type = 'Electric'
   AND REPLACE(UPPER(CONCAT_WS(' ', v.make, v.model)), ' ', '')
     = REPLACE(UPPER(TRIM(e.car_model)), ' ', '')
  WHERE CAST(e.battery_capacity_kwh AS DECIMAL(8, 2)) > 0
    AND CAST(e.autonomy_wltp_km   AS DECIMAL(10, 2)) > 0
) ranked
WHERE rn = 1;
