-- Zusätzlich zu FORMAT=TREE: tatsächliche Laufzeiten („actual time“, gelesene Zeilen).
-- Nur MySQL 8.0.18+ / 9.x. In DBeaver ausführen; Ausgabe für Bericht/Screenshot.
USE ev_project;

EXPLAIN ANALYZE
WITH ref_year AS (
  SELECT 2022 AS y
),
grid_intensity AS (
  SELECT
    CASE e.area
      WHEN 'France' THEN 'FR'
      WHEN 'Germany' THEN 'DE'
      WHEN 'Switzerland' THEN 'CH'
    END AS country_code,
    CAST(e.value AS DECIMAL(10, 4)) AS co2_g_per_kwh
  FROM stg_ember_electricity e
  CROSS JOIN ref_year ry
  WHERE e.category = 'Power sector emissions'
    AND e.subcategory = 'CO2 intensity'
    AND e.variable = 'CO2 intensity'
    AND e.unit = 'gCO2/kWh'
    AND e.area IN ('France', 'Germany', 'Switzerland')
    AND e.year = ry.y
),
elec_yearly AS (
  SELECT
    ep.country_code,
    ROUND(AVG(ep.price_eur_per_kwh), 4) AS price_eur_per_kwh
  FROM electricity_price ep
  CROSS JOIN ref_year ry
  WHERE ep.year = ry.y
  GROUP BY ep.country_code
),
ice_fleet AS (
  SELECT
    AVG(ie.fuel_consumption_comb) AS l_per_100km,
    AVG(ie.co2_emissions_gkm) AS co2_gkm_tailpipe
  FROM vehicle v
  INNER JOIN ice_emission ie ON ie.vehicle_id = v.vehicle_id
  WHERE v.fuel_type IN ('Petrol', 'Diesel')
    AND ie.fuel_consumption_comb IS NOT NULL
    AND ie.co2_emissions_gkm IS NOT NULL
  HAVING COUNT(*) >= 5
),
ev_fleet AS (
  SELECT
    AVG(es.energy_consumption_kwh_100km) AS kwh_per_100km
  FROM vehicle v
  INNER JOIN ev_spec es ON es.vehicle_id = v.vehicle_id
  WHERE v.fuel_type = 'Electric'
    AND es.energy_consumption_kwh_100km IS NOT NULL
    AND es.energy_consumption_kwh_100km > 0
  HAVING COUNT(*) >= 1
)
SELECT
  c.country_code,
  c.country_name,
  'FLEET_AVG' AS segment,
  ROUND(c.petrol_price_eur_per_l * i.l_per_100km / 100.0, 4) AS ice_eur_per_km,
  ROUND(e.price_eur_per_kwh * ev.kwh_per_100km / 100.0, 4) AS ev_eur_per_km,
  ROUND(g.co2_g_per_kwh * ev.kwh_per_100km / 100.0, 2) AS ev_co2_g_per_km,
  ROUND(i.co2_gkm_tailpipe, 0) AS ice_co2_g_per_km,
  CASE
    WHEN (e.price_eur_per_kwh * ev.kwh_per_100km / 100.0)
         <= 1.10 * (c.petrol_price_eur_per_l * i.l_per_100km / 100.0)
      AND (g.co2_g_per_kwh * ev.kwh_per_100km / 100.0) < i.co2_gkm_tailpipe
    THEN 1
    ELSE 0
  END AS recommend_ev,
  1.10 AS r_cost,
  1.00 AS r_co2
FROM country c
CROSS JOIN ice_fleet i
CROSS JOIN ev_fleet ev
INNER JOIN grid_intensity g ON g.country_code = c.country_code
INNER JOIN elec_yearly e ON e.country_code = c.country_code
WHERE c.country_code IN ('CH', 'DE', 'FR')
ORDER BY c.country_code;
