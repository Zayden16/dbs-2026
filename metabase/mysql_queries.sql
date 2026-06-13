-- ============================================================================
-- Metabase — MySQL dashboard queries (database: ev_project)
-- New Question -> Native query -> Database: MySQL (ev_project)
-- Variables use Metabase {{...}} syntax; [[ ... ]] marks an optional clause.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1: EV-vs-ICE Decision KPI per country (canonical; matches MongoDB to 4dp).
-- Mirrors sql/03_ev_ice_decision.sql. Optional {{country}} dropdown (CH/DE/FR).
-- ----------------------------------------------------------------------------
WITH ref_year AS (SELECT 2022 AS y),
grid_intensity AS (
  SELECT CASE e.area WHEN 'France' THEN 'FR' WHEN 'Germany' THEN 'DE' WHEN 'Switzerland' THEN 'CH' END AS country_code,
         CAST(e.value AS DECIMAL(10,4)) AS co2_g_per_kwh
  FROM stg_ember_electricity e CROSS JOIN ref_year ry
  WHERE e.category='Power sector emissions' AND e.subcategory='CO2 intensity'
    AND e.variable='CO2 intensity' AND e.unit='gCO2/kWh'
    AND e.area IN ('France','Germany','Switzerland') AND e.year=ry.y
),
elec_yearly AS (
  SELECT ep.country_code, ROUND(AVG(ep.price_eur_per_kwh),4) AS price_eur_per_kwh
  FROM electricity_price ep CROSS JOIN ref_year ry
  WHERE ep.year=ry.y GROUP BY ep.country_code
),
ice_fleet AS (
  SELECT AVG(ie.fuel_consumption_comb) AS l_per_100km, AVG(ie.co2_emissions_gkm) AS co2_gkm
  FROM vehicle v JOIN ice_emission ie ON ie.vehicle_id=v.vehicle_id
  WHERE v.fuel_type IN ('Petrol','Diesel')
    AND ie.fuel_consumption_comb IS NOT NULL AND ie.co2_emissions_gkm IS NOT NULL
),
ev_fleet AS (
  SELECT AVG(es.energy_consumption_kwh_100km) AS kwh_per_100km
  FROM vehicle v JOIN ev_spec es ON es.vehicle_id=v.vehicle_id
  WHERE v.fuel_type='Electric' AND es.energy_consumption_kwh_100km>0
)
SELECT
  c.country_code,
  ROUND((c.petrol_price_eur_per_l + c.diesel_price_eur_per_l)/2.0 * i.l_per_100km/100.0, 4) AS ice_eur_per_km,
  ROUND(e.price_eur_per_kwh * ev.kwh_per_100km/100.0, 4)                                    AS ev_eur_per_km,
  ROUND(g.co2_g_per_kwh * ev.kwh_per_100km/100.0, 2)                                        AS ev_co2_g_per_km,
  ROUND(i.co2_gkm, 0)                                                                       AS ice_co2_g_per_km,
  CASE WHEN (e.price_eur_per_kwh * ev.kwh_per_100km/100.0)
            <= 1.10 * ((c.petrol_price_eur_per_l + c.diesel_price_eur_per_l)/2.0 * i.l_per_100km/100.0)
        AND (g.co2_g_per_kwh * ev.kwh_per_100km/100.0) <= i.co2_gkm
       THEN 1 ELSE 0 END                                                                    AS recommend_ev
FROM country c
CROSS JOIN ice_fleet i
CROSS JOIN ev_fleet ev
JOIN grid_intensity g ON g.country_code=c.country_code
JOIN elec_yearly   e ON e.country_code=c.country_code
WHERE c.country_code IN ('CH','DE','FR')
  [[ AND c.country_code = {{country}} ]]
ORDER BY c.country_code;

-- ----------------------------------------------------------------------------
-- Q2: TCO over N years (line chart). X=year, Y=total cost, series=ICE vs EV.
-- Reads the pre-built view v_ev_tco_base. Parameters:
--   {{country}}      Text  (CH/DE/FR)
--   {{km_per_year}}  Number (e.g. 15000)
--   {{years}}        Number (1..15)
-- CAVEAT: ice/ev_purchase_usd are fleet-median USD prices (same for all
-- countries); cost/km is EUR. The total mixes currencies -> indicative only.
-- ----------------------------------------------------------------------------
SELECT
  b.country_code                                                              AS country,
  ys.yr                                                                       AS year,
  ROUND(b.ice_purchase_usd + {{km_per_year}} * ys.yr * b.ice_cost_per_km, 2)  AS ice_total,
  ROUND(b.ev_purchase_usd  + {{km_per_year}} * ys.yr * b.ev_cost_per_km,  2)  AS ev_total
FROM v_ev_tco_base b
JOIN (
  SELECT 1 AS yr UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
  UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10
  UNION SELECT 11 UNION SELECT 12 UNION SELECT 13 UNION SELECT 14 UNION SELECT 15
) ys ON ys.yr <= {{years}}
WHERE b.country_code = {{country}}
ORDER BY ys.yr;
