-- Nach dem Lauf von 02_insert_transform.sql ausführen: ein Ergebnisraster für Screenshots / Bericht.
-- In DBeaver: nur diese Datei öffnen oder den Block markieren → „SQL ausführen“ (ein Statement liefert eine Tabelle).

USE ev_project;

SELECT 'country' AS tabelle, COUNT(*) AS zeilen FROM country
UNION ALL SELECT 'vehicle', COUNT(*) FROM vehicle
UNION ALL SELECT 'ice_emission', COUNT(*) FROM ice_emission
UNION ALL SELECT 'ev_spec', COUNT(*) FROM ev_spec
UNION ALL SELECT 'charging_station', COUNT(*) FROM charging_station
UNION ALL SELECT 'charging_country_summary', COUNT(*) FROM charging_country_summary
UNION ALL SELECT 'electricity_price', COUNT(*) FROM electricity_price
UNION ALL SELECT 'grid_mix', COUNT(*) FROM grid_mix
UNION ALL SELECT 'ev_adoption', COUNT(*) FROM ev_adoption
ORDER BY tabelle;
