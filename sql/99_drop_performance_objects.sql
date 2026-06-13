-- Entfernt die optionalen Performance-Objekte (z. B. für Tests auf einer Kopie der DB).
-- Vorsicht auf Railway: Index `idx_ember_analytics_co2` weglassen, wenn er produktiv bleiben soll.
USE ev_project;

DROP TABLE IF EXISTS analytics_mv_elec_yearly_2022;
DROP TABLE IF EXISTS analytics_mv_grid_co2_intensity_2022;

-- Auskommentiert, damit ein versehentliches Ausführen den produktiven Index nicht löscht:
-- ALTER TABLE stg_ember_electricity DROP INDEX idx_ember_analytics_co2;
