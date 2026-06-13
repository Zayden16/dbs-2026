-- Sekundärindex für die Ember-Staging-Tabelle: ersetzt Full Table Scan bei der CO2-Intensitäts-CTE
-- der Analytik (`grid_intensity` in `03_ev_ice_decision.sql`).
-- Spaltenreihenfolge: Gleichheitsfilter wie in der WHERE-Klausel (year, area, category, …).
--
-- Einmalig ausführen. Wenn der Name schon existiert, meldet MySQL Fehler 1061 — dann überspringen.
USE ev_project;

CREATE INDEX idx_ember_analytics_co2 ON stg_ember_electricity (
  year,
  area,
  category,
  subcategory,
  variable,
  unit
);
