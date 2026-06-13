-- ============================================================================
-- Metabase — MySQL dashboard queries (database: ev_project)
-- New Question -> Native query -> Database: MySQL (ev_project)
-- Variables use Metabase {{...}} syntax; [[ ... ]] marks an optional clause.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1: EV-vs-ICE Decision KPI per country (canonical; matches MongoDB to 4dp).
-- Reads the view analytics_view (defined in sql/07_create_analytics_view.sql),
-- the SQL analogue of MongoDB's mv_ev_decision. Optional {{country}} dropdown.
-- ----------------------------------------------------------------------------
SELECT
  country_code,
  ice_eur_per_km,
  ev_eur_per_km,
  ev_co2_g_per_km,
  ice_co2_g_per_km,
  recommend_ev,
  ratio_cost,
  ratio_co2
FROM analytics_view
[[ WHERE country_code = {{country}} ]]
ORDER BY country_code;

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
