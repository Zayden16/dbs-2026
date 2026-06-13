-- ELT transform — clear integrated tables (staging untouched).
-- Run before 02_insert_transform.sql. Execute in DBeaver or: mysql ... < 01_truncate_target.sql
USE ev_project;
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE ice_emission;
TRUNCATE TABLE ev_spec;
TRUNCATE TABLE vehicle;
TRUNCATE TABLE charging_station;
TRUNCATE TABLE charging_country_summary;
TRUNCATE TABLE electricity_price;
TRUNCATE TABLE grid_mix;
TRUNCATE TABLE ev_adoption;
TRUNCATE TABLE country;
SET FOREIGN_KEY_CHECKS = 1;
