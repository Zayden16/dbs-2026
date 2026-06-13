-- Gleiche fachliche Logik wie `03_ev_ice_decision.sql`, aber `grid_intensity` und `elec_yearly`
-- kommen aus den materialisierten Tabellen (`03_ctas_materialize.sql`).
USE ev_project;

WITH ice_fleet AS (
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
  ROUND((c.petrol_price_eur_per_l + c.diesel_price_eur_per_l) / 2.0 * i.l_per_100km / 100.0, 4) AS ice_eur_per_km,
  ROUND(e.price_eur_per_kwh * ev.kwh_per_100km / 100.0, 4) AS ev_eur_per_km,
  ROUND(g.co2_g_per_kwh * ev.kwh_per_100km / 100.0, 2) AS ev_co2_g_per_km,
  ROUND(i.co2_gkm_tailpipe, 0) AS ice_co2_g_per_km,
  CASE
    WHEN (e.price_eur_per_kwh * ev.kwh_per_100km / 100.0)
         <= 1.10 * ((c.petrol_price_eur_per_l + c.diesel_price_eur_per_l) / 2.0 * i.l_per_100km / 100.0)
      AND (g.co2_g_per_kwh * ev.kwh_per_100km / 100.0) < i.co2_gkm_tailpipe
    THEN 1
    ELSE 0
  END AS recommend_ev,
  1.10 AS r_cost,
  1.00 AS r_co2
FROM country c
CROSS JOIN ice_fleet i
CROSS JOIN ev_fleet ev
INNER JOIN analytics_mv_grid_co2_intensity_2022 g ON g.country_code = c.country_code
INNER JOIN analytics_mv_elec_yearly_2022 e ON e.country_code = c.country_code
WHERE c.country_code IN ('CH', 'DE', 'FR')
ORDER BY c.country_code;
