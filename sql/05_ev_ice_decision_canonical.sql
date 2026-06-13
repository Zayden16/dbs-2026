-- ============================================================================
-- DBS Project: "Are EVs Really Better?" — Canonical EV vs ICE Decision Query
-- ============================================================================
-- Reconciled with MongoDB (mongodb/04_analytics.js) on 2026-05-15.
-- Canonical methodology (MUST stay identical to MongoDB):
--   * Fuel prices : real fuel_prices.csv (country table, CSV values)
--   * ICE fleet   : stg_co2 fuel_type IN ('X','D')  -> Petrol + Diesel only
--   * ICE cost/km : avg_consumption/100 * (petrol+diesel)/2
--   * EV avg      : AVG(ROUND(battery/range*100,1)) over stg_ev_specs
--   * Elec 2022   : CH = (stg_ch avg_price/100)*0.94 ; DE/FR = AVG eurostat 2022
--   * CO2 int 2022: analytics_mv_grid_co2_intensity_2022
--
-- Expected output (must match MongoDB mv_ev_decision):
--   CH | 0.1740 | 0.0375 | 6.91  | 235 | 1
--   DE | 0.1810 | 0.0684 | 77.84 | 235 | 1
--   FR | 0.1775 | 0.0470 | 14.57 | 235 | 1
--
-- This query reads directly from the (correct) staging tables so it does NOT
-- depend on the partially-loaded vehicle / ice_emission tables.
-- ============================================================================
USE ev_project;

WITH ice AS (   -- fleet-average ICE consumption + CO2 (Petrol X + Diesel D)
  SELECT AVG(fuel_comb) AS avg_l,
         AVG(co2_gkm)   AS avg_co2
  FROM stg_co2
  WHERE fuel_type IN ('X','D') AND fuel_comb > 0 AND co2_gkm > 0
),
ev AS (         -- fleet-average EV consumption (kWh/100km)
  SELECT AVG(ROUND(battery_capacity_kwh / autonomy_wltp_km * 100, 1)) AS avg_kwh
  FROM stg_ev_specs
  WHERE battery_capacity_kwh > 0 AND autonomy_wltp_km > 0
),
elec AS (       -- 2022 electricity price per country (EUR/kWh), Mongo-aligned
  SELECT 'CH' AS country_code,
         ROUND((SELECT avg_price FROM stg_ch_elec_prices WHERE year = 2022) / 100 * 0.94, 4) AS price
  UNION ALL
  SELECT country_code, ROUND(AVG(price_eur_per_kwh), 4)
  FROM stg_eurostat_elec_prices
  WHERE period LIKE '2022%'
  GROUP BY country_code
),
co2int AS (     -- 2022 grid CO2 intensity per country (gCO2/kWh)
  SELECT country_code, co2_g_per_kwh AS co2_intensity
  FROM analytics_mv_grid_co2_intensity_2022
)
SELECT
  c.country_code                                                       AS country,
  ROUND(ice.avg_l / 100 *
        (c.petrol_price_eur_per_l + c.diesel_price_eur_per_l) / 2, 4)   AS ice_cost,
  ROUND(ev.avg_kwh / 100 * e.price, 4)                                  AS ev_cost,
  ROUND(ev.avg_kwh / 100 * ci.co2_intensity, 2)                         AS ev_co2,
  ROUND(ice.avg_co2, 0)                                                 AS ice_co2,
  CASE WHEN ROUND(ev.avg_kwh / 100 * e.price, 4)
            <= ROUND(ice.avg_l / 100 *
               (c.petrol_price_eur_per_l + c.diesel_price_eur_per_l) / 2, 4) * 1.10
        AND ROUND(ev.avg_kwh / 100 * ci.co2_intensity, 2)
            <= ROUND(ice.avg_co2, 0)
       THEN 1 ELSE 0 END                                                AS recommend_ev
FROM country c
JOIN ice
JOIN ev
JOIN elec   e  ON e.country_code  = c.country_code
JOIN co2int ci ON ci.country_code = c.country_code
WHERE c.country_code IN ('CH','DE','FR')
ORDER BY c.country_code;
