-- ELT: INSERT ... SELECT from stg_* into 3NF target tables (ev_project).
-- Reference: er_model.txt, HSLU ELT requirement.
-- Prerequisites: 01_truncate_target.sql (optional if first load).
USE ev_project;

-- ---------------------------------------------------------------------------
-- COUNTRY (CH, DE, FR) — real fuel prices (EUR/L) from datasets/fuel_prices.csv.
-- These values MUST match the MongoDB `countries` collection so SQL and NoSQL
-- reconcile to the same cost/km (canonical methodology).
-- ---------------------------------------------------------------------------
INSERT INTO country (country_code, country_name, petrol_price_eur_per_l, diesel_price_eur_per_l)
VALUES
  ('CH', 'Switzerland', 1.670, 1.800),
  ('DE', 'Germany',     1.850, 1.760),
  ('FR', 'France',      1.790, 1.750);

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
-- ICE_EMISSION — full CO2 registry as 3NF vehicles + emissions (1:1 per stg_co2).
-- Mirrors the MongoDB `vehicles` collection (every co2.csv row becomes a vehicle
-- with an embedded ice_emission). The analytics query filters the fleet to
-- fuel_type IN ('Petrol','Diesel') -> 3812 rows, identical to MongoDB.
--
-- Gap-proof 1:1 link without surrogate keys (InnoDB auto-increment can leave
-- gaps under interleaved lock mode, so id arithmetic is unsafe). Step 1 inserts
-- one vehicle per stg_co2 row in a fixed order. Step 2 matches vehicle <-> stg_co2
-- on (make, model, fuel_type) and aligned ROW_NUMBER(): within each group the
-- vehicle_id ascending order equals the stg_co2 attribute order (same ORDER BY),
-- so rn pairs each vehicle with its source row regardless of id gaps.
-- @ice_v0 fences off the catalogue vehicles inserted above (co2 vehicles get the
-- larger ids). Fuel codes: X=Petrol, Z=Premium Petrol, D=Diesel, E=E85, N=Natural Gas.
-- ---------------------------------------------------------------------------
SET @ice_v0 := (SELECT COALESCE(MAX(vehicle_id), 0) FROM vehicle);

INSERT INTO vehicle (make, model, fuel_type, vehicle_class)
SELECT make_c, model_c, fuel_c, class_c
FROM (
  SELECT
    NULLIF(TRIM(make), '')          AS make_c,
    NULLIF(TRIM(model), '')         AS model_c,
    CASE fuel_type
      WHEN 'X' THEN 'Petrol'
      WHEN 'Z' THEN 'Premium Petrol'
      WHEN 'D' THEN 'Diesel'
      WHEN 'E' THEN 'E85'
      WHEN 'N' THEN 'Natural Gas'
      ELSE 'Unknown'
    END                             AS fuel_c,
    NULLIF(TRIM(vehicle_class), '') AS class_c,
    ROW_NUMBER() OVER (
      ORDER BY make, model, fuel_type, engine_size_l, cylinders,
               transmission, fuel_city, fuel_hwy, fuel_comb, co2_gkm
    ) AS seq
  FROM stg_co2
  WHERE co2_gkm IS NOT NULL
) s
ORDER BY seq;

INSERT INTO ice_emission (
  vehicle_id, engine_size_l, cylinders, transmission,
  fuel_consumption_city, fuel_consumption_hwy, fuel_consumption_comb, co2_emissions_gkm
)
SELECT
  vt.vehicle_id,
  c.engine_size_l, c.cylinders, c.transmission,
  c.fuel_city, c.fuel_hwy, c.fuel_comb, c.co2_gkm
FROM (
  SELECT
    vehicle_id,
    UPPER(TRIM(make))  AS mk,
    UPPER(TRIM(model)) AS md,
    fuel_type,
    ROW_NUMBER() OVER (
      PARTITION BY UPPER(TRIM(make)), UPPER(TRIM(model)), fuel_type
      ORDER BY vehicle_id
    ) AS rn
  FROM vehicle
  WHERE vehicle_id > @ice_v0
) vt
INNER JOIN (
  SELECT
    UPPER(TRIM(make))  AS mk,
    UPPER(TRIM(model)) AS md,
    CASE fuel_type
      WHEN 'X' THEN 'Petrol'
      WHEN 'Z' THEN 'Premium Petrol'
      WHEN 'D' THEN 'Diesel'
      WHEN 'E' THEN 'E85'
      WHEN 'N' THEN 'Natural Gas'
      ELSE 'Unknown'
    END AS fuel_c,
    engine_size_l, cylinders, transmission, fuel_city, fuel_hwy, fuel_comb, co2_gkm,
    ROW_NUMBER() OVER (
      PARTITION BY UPPER(TRIM(make)), UPPER(TRIM(model)),
        CASE fuel_type
          WHEN 'X' THEN 'Petrol'
          WHEN 'Z' THEN 'Premium Petrol'
          WHEN 'D' THEN 'Diesel'
          WHEN 'E' THEN 'E85'
          WHEN 'N' THEN 'Natural Gas'
          ELSE 'Unknown'
        END
      ORDER BY engine_size_l, cylinders, transmission, fuel_city, fuel_hwy, fuel_comb, co2_gkm
    ) AS rn
  FROM stg_co2
  WHERE co2_gkm IS NOT NULL
) c
  ON vt.mk = c.mk AND vt.md = c.md AND vt.fuel_type = c.fuel_c AND vt.rn = c.rn;

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
    -- 1 decimal to match MongoDB ($round ..., 1) and the DECIMAL(4,1) column
    -- (avoids double-rounding, e.g. 12.247 -> 12.25 -> 12.3 vs MongoDB 12.2).
    ROUND(
      (CAST(e.battery_capacity_kwh AS DECIMAL(8, 2))
       / CAST(e.autonomy_wltp_km   AS DECIMAL(10, 2))) * 100.0, 1
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
