-- ============================================================================
-- analytics_view — SQL decision view for Metabase (Kap. 5 + Kap. 7).
-- The relational analogue of MongoDB's materialized mv_ev_decision: one row per
-- country with the EV-vs-ICE decision KPIs, read directly by the dashboard
-- (parametrized via WHERE country_code = {{country}}).
-- Wraps the canonical query in sql/03_ev_ice_decision.sql 1:1 (same fleet,
-- prices, rounding) so SQL and MongoDB stay reconciled to 4 decimals.
-- ============================================================================
USE ev_project;

CREATE OR REPLACE VIEW analytics_view AS
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
  SELECT ep.country_code, ROUND(AVG(ep.price_eur_per_kwh), 4) AS price_eur_per_kwh
  FROM electricity_price ep
  CROSS JOIN ref_year ry
  WHERE ep.year = ry.y
  GROUP BY ep.country_code
),
ice_fleet AS (
  SELECT AVG(ie.fuel_consumption_comb) AS l_per_100km,
         AVG(ie.co2_emissions_gkm)     AS co2_gkm_tailpipe
  FROM vehicle v
  INNER JOIN ice_emission ie ON ie.vehicle_id = v.vehicle_id
  WHERE v.fuel_type IN ('Petrol', 'Diesel')
    AND ie.fuel_consumption_comb IS NOT NULL
    AND ie.co2_emissions_gkm IS NOT NULL
),
ev_fleet AS (
  SELECT AVG(es.energy_consumption_kwh_100km) AS kwh_per_100km
  FROM vehicle v
  INNER JOIN ev_spec es ON es.vehicle_id = v.vehicle_id
  WHERE v.fuel_type = 'Electric'
    AND es.energy_consumption_kwh_100km > 0
)
SELECT
  c.country_code,
  ROUND((c.petrol_price_eur_per_l + c.diesel_price_eur_per_l) / 2.0 * i.l_per_100km / 100.0, 4) AS ice_eur_per_km,
  ROUND(e.price_eur_per_kwh * ev.kwh_per_100km / 100.0, 4)                                       AS ev_eur_per_km,
  ROUND(g.co2_g_per_kwh * ev.kwh_per_100km / 100.0, 2)                                           AS ev_co2_g_per_km,
  ROUND(i.co2_gkm_tailpipe, 0)                                                                   AS ice_co2_g_per_km,
  CASE WHEN (e.price_eur_per_kwh * ev.kwh_per_100km / 100.0)
            <= 1.10 * ((c.petrol_price_eur_per_l + c.diesel_price_eur_per_l) / 2.0 * i.l_per_100km / 100.0)
        AND (g.co2_g_per_kwh * ev.kwh_per_100km / 100.0) <= i.co2_gkm_tailpipe
       THEN 1 ELSE 0 END                                                                         AS recommend_ev,
  ROUND((e.price_eur_per_kwh * ev.kwh_per_100km / 100.0)
        / ((c.petrol_price_eur_per_l + c.diesel_price_eur_per_l) / 2.0 * i.l_per_100km / 100.0), 2) AS ratio_cost,
  ROUND((g.co2_g_per_kwh * ev.kwh_per_100km / 100.0) / i.co2_gkm_tailpipe, 2)                    AS ratio_co2
FROM country c
CROSS JOIN ice_fleet i
CROSS JOIN ev_fleet ev
INNER JOIN grid_intensity g ON g.country_code = c.country_code
INNER JOIN elec_yearly   e ON e.country_code = c.country_code
WHERE c.country_code IN ('CH', 'DE', 'FR');
