-- Übungsschwerpunkt SW06: materialisierte Zwischenergebnisse (CREATE TABLE … AS SELECT).
-- Nach jedem erneuten Laden von Staging/Zieltabellen (ELT) diese Datei erneut ausführen.
-- Tabellen sind bewusst mit Präfix `analytics_mv_` benannt (kein Konflikt mit 3NF-Zieltabellen).
USE ev_project;

DROP TABLE IF EXISTS analytics_mv_grid_co2_intensity_2022;

CREATE TABLE analytics_mv_grid_co2_intensity_2022 AS
SELECT
  CASE e.area
    WHEN 'France' THEN 'FR'
    WHEN 'Germany' THEN 'DE'
    WHEN 'Switzerland' THEN 'CH'
  END AS country_code,
  CAST(e.value AS DECIMAL(10, 4)) AS co2_g_per_kwh
FROM stg_ember_electricity e
WHERE e.category = 'Power sector emissions'
  AND e.subcategory = 'CO2 intensity'
  AND e.variable = 'CO2 intensity'
  AND e.unit = 'gCO2/kWh'
  AND e.area IN ('France', 'Germany', 'Switzerland')
  AND e.year = 2022;

-- Gleiche Kollation wie Zieltabellen (sonst JOIN-Fehler 1267 zu `country`)
ALTER TABLE analytics_mv_grid_co2_intensity_2022
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE analytics_mv_grid_co2_intensity_2022
  ADD PRIMARY KEY (country_code);

DROP TABLE IF EXISTS analytics_mv_elec_yearly_2022;

CREATE TABLE analytics_mv_elec_yearly_2022 AS
SELECT
  ep.country_code,
  ROUND(AVG(ep.price_eur_per_kwh), 4) AS price_eur_per_kwh
FROM electricity_price ep
WHERE ep.year = 2022
GROUP BY ep.country_code;

ALTER TABLE analytics_mv_elec_yearly_2022
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE analytics_mv_elec_yearly_2022
  ADD PRIMARY KEY (country_code);
