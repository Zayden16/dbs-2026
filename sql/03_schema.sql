-- ============================================================================
-- DBS Project: "Are EVs Really Better?"
-- SQL Schema (MySQL) — 3rd Normal Form
-- ============================================================================

DROP DATABASE IF EXISTS ev_project;
CREATE DATABASE ev_project CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ev_project;

-- ============================================================================
-- 1. COUNTRY — central reference entity
-- ============================================================================
CREATE TABLE country (
    country_code    CHAR(2)         NOT NULL,
    country_name    VARCHAR(100)    NOT NULL,
    petrol_price_eur_per_l  DECIMAL(5,3)    NULL,
    diesel_price_eur_per_l  DECIMAL(5,3)    NULL,
    PRIMARY KEY (country_code)
) ENGINE=InnoDB;

-- ============================================================================
-- 2. VEHICLE — unified catalog for ICE and EV
-- ============================================================================
CREATE TABLE vehicle (
    vehicle_id      INT             NOT NULL AUTO_INCREMENT,
    make            VARCHAR(50)     NOT NULL,
    model           VARCHAR(100)    NOT NULL,
    fuel_type       VARCHAR(30)     NOT NULL,
    vehicle_class   VARCHAR(50)     NULL,
    price_usd       DECIMAL(12,2)   NULL,
    horsepower      INT             NULL,
    seats           INT             NULL,
    PRIMARY KEY (vehicle_id),
    INDEX idx_vehicle_make (make),
    INDEX idx_vehicle_fuel_type (fuel_type)
) ENGINE=InnoDB;

-- ============================================================================
-- 3. ICE_EMISSION — fuel consumption & CO2 for ICE vehicles
-- ============================================================================
CREATE TABLE ice_emission (
    ice_emission_id         INT             NOT NULL AUTO_INCREMENT,
    vehicle_id              INT             NOT NULL,
    engine_size_l           DECIMAL(3,1)    NULL,
    cylinders               TINYINT         NULL,
    transmission            VARCHAR(10)     NULL,
    fuel_consumption_city   DECIMAL(4,1)    NULL,   -- L/100km
    fuel_consumption_hwy    DECIMAL(4,1)    NULL,   -- L/100km
    fuel_consumption_comb   DECIMAL(4,1)    NULL,   -- L/100km
    co2_emissions_gkm       INT             NULL,   -- g/km tailpipe
    PRIMARY KEY (ice_emission_id),
    FOREIGN KEY (vehicle_id) REFERENCES vehicle(vehicle_id),
    INDEX idx_ice_vehicle (vehicle_id)
) ENGINE=InnoDB;

-- ============================================================================
-- 4. EV_SPEC — battery, range, consumption for EVs
-- ============================================================================
CREATE TABLE ev_spec (
    ev_spec_id              INT             NOT NULL AUTO_INCREMENT,
    vehicle_id              INT             NOT NULL,
    battery_capacity_kwh    DECIMAL(5,1)    NULL,
    range_wltp_km           INT             NULL,
    energy_consumption_kwh_100km DECIMAL(4,1) NULL, -- derived
    dc_charge_power_kw      INT             NULL,
    ac_charge_power_kw      DECIMAL(4,1)    NULL,
    release_year            INT             NULL,
    PRIMARY KEY (ev_spec_id),
    FOREIGN KEY (vehicle_id) REFERENCES vehicle(vehicle_id),
    INDEX idx_ev_vehicle (vehicle_id)
) ENGINE=InnoDB;

-- ============================================================================
-- 5. CHARGING_STATION — individual stations (filtered to CH/DE/FR)
-- ============================================================================
CREATE TABLE charging_station (
    station_id      INT             NOT NULL,
    name            VARCHAR(255)    NULL,
    city            VARCHAR(100)    NULL,
    state_province  VARCHAR(100)    NULL,
    country_code    CHAR(2)         NOT NULL,
    latitude        DECIMAL(10,6)   NULL,
    longitude       DECIMAL(10,6)   NULL,
    ports           INT             NULL,
    power_kw        DECIMAL(7,1)    NULL,
    power_class     VARCHAR(30)     NULL,
    is_fast_dc      BOOLEAN         NULL,
    PRIMARY KEY (station_id),
    FOREIGN KEY (country_code) REFERENCES country(country_code),
    INDEX idx_station_country (country_code),
    INDEX idx_station_power_class (power_class)
) ENGINE=InnoDB;

-- ============================================================================
-- 6. CHARGING_COUNTRY_SUMMARY — aggregated infra per country
-- ============================================================================
CREATE TABLE charging_country_summary (
    country_code        CHAR(2)         NOT NULL,
    station_count       INT             NULL,
    port_count          INT             NULL,
    fast_station_share  DECIMAL(5,4)    NULL,
    fast_port_share     DECIMAL(5,4)    NULL,
    PRIMARY KEY (country_code),
    FOREIGN KEY (country_code) REFERENCES country(country_code)
) ENGINE=InnoDB;

-- ============================================================================
-- 7. ELECTRICITY_PRICE — household prices over time
-- ============================================================================
CREATE TABLE electricity_price (
    elec_price_id   INT             NOT NULL AUTO_INCREMENT,
    country_code    CHAR(2)         NOT NULL,
    year            INT             NOT NULL,
    half_year       TINYINT         NULL,       -- 1=S1, 2=S2, NULL=annual
    price_eur_per_kwh DECIMAL(6,4)  NOT NULL,
    PRIMARY KEY (elec_price_id),
    FOREIGN KEY (country_code) REFERENCES country(country_code),
    UNIQUE INDEX idx_elec_price_unique (country_code, year, half_year),
    INDEX idx_elec_price_country_year (country_code, year)
) ENGINE=InnoDB;

-- ============================================================================
-- 8. GRID_MIX — electricity generation mix per country/year/source
-- ============================================================================
CREATE TABLE grid_mix (
    grid_mix_id     INT             NOT NULL AUTO_INCREMENT,
    country_code    CHAR(2)         NOT NULL,
    year            INT             NOT NULL,
    source_type     VARCHAR(30)     NOT NULL,   -- Coal, Gas, Nuclear, Hydro, Wind, Solar, etc.
    generation_twh  DECIMAL(10,2)   NULL,
    share_pct       DECIMAL(5,2)    NULL,
    co2_intensity_gkwh DECIMAL(7,2) NULL,       -- gCO2 per kWh for this source
    PRIMARY KEY (grid_mix_id),
    FOREIGN KEY (country_code) REFERENCES country(country_code),
    UNIQUE INDEX idx_grid_mix_unique (country_code, year, source_type),
    INDEX idx_grid_mix_country_year (country_code, year)
) ENGINE=InnoDB;

-- ============================================================================
-- 9. EV_ADOPTION — EV sales, stock, market share per country/year
-- ============================================================================
CREATE TABLE ev_adoption (
    ev_adoption_id      INT             NOT NULL AUTO_INCREMENT,
    country_code        CHAR(2)         NOT NULL,
    year                INT             NOT NULL,
    powertrain          VARCHAR(10)     NOT NULL,   -- BEV, PHEV, EV
    ev_sales            INT             NULL,
    ev_stock            INT             NULL,
    ev_sales_share_pct  DECIMAL(6,3)    NULL,
    ev_stock_share_pct  DECIMAL(6,3)    NULL,
    PRIMARY KEY (ev_adoption_id),
    FOREIGN KEY (country_code) REFERENCES country(country_code),
    UNIQUE INDEX idx_ev_adoption_unique (country_code, year, powertrain),
    INDEX idx_ev_adoption_country_year (country_code, year)
) ENGINE=InnoDB;

-- ============================================================================
-- STAGING TABLES — for raw data import (ELT approach)
-- These hold the raw CSV data before transformation into target schema
-- ============================================================================

CREATE TABLE stg_cars_2025 (
    company_name    VARCHAR(100)    NULL,
    car_name        VARCHAR(200)    NULL,
    engine          VARCHAR(200)    NULL,
    cc_battery      VARCHAR(100)    NULL,
    horsepower      VARCHAR(100)    NULL,
    total_speed     VARCHAR(50)     NULL,
    performance     VARCHAR(50)     NULL,
    price           VARCHAR(100)    NULL,
    fuel_type       VARCHAR(50)     NULL,
    seats           VARCHAR(20)     NULL,
    torque          VARCHAR(100)    NULL
) ENGINE=InnoDB;

CREATE TABLE stg_co2 (
    make            VARCHAR(50)     NULL,
    model           VARCHAR(100)    NULL,
    vehicle_class   VARCHAR(50)     NULL,
    engine_size_l   DECIMAL(3,1)    NULL,
    cylinders       TINYINT         NULL,
    transmission    VARCHAR(10)     NULL,
    fuel_type       CHAR(1)         NULL,
    fuel_city       DECIMAL(4,1)    NULL,
    fuel_hwy        DECIMAL(4,1)    NULL,
    fuel_comb       DECIMAL(4,1)    NULL,
    fuel_comb_mpg   INT             NULL,
    co2_gkm         INT             NULL
) ENGINE=InnoDB;

CREATE TABLE stg_ev_specs (
    car_model               VARCHAR(200)    NULL,
    autonomy_wltp_km        INT             NULL,
    dc_connector            VARCHAR(200)    NULL,
    dc_protocol             VARCHAR(200)    NULL,
    dc_charge_power_kw      INT             NULL,
    release_year            INT             NULL,
    ac_connector            VARCHAR(200)    NULL,
    ac_charge_power         VARCHAR(50)     NULL,
    ac_protocol             VARCHAR(200)    NULL,
    car_type                VARCHAR(50)     NULL,
    price_k_usd             VARCHAR(50)     NULL,
    battery_capacity_kwh    DECIMAL(5,1)    NULL,
    source                  VARCHAR(200)    NULL
) ENGINE=InnoDB;

CREATE TABLE stg_iea_ev (
    region          VARCHAR(100)    NULL,
    category        VARCHAR(50)     NULL,
    parameter       VARCHAR(50)     NULL,
    mode            VARCHAR(20)     NULL,
    powertrain      VARCHAR(10)     NULL,
    year            INT             NULL,
    unit            VARCHAR(20)     NULL,
    value           DECIMAL(15,4)   NULL
) ENGINE=InnoDB;

CREATE TABLE stg_charging_station (
    id              INT             NULL,
    name            VARCHAR(255)    NULL,
    city            VARCHAR(200)    NULL,
    state_province  VARCHAR(200)    NULL,
    country_code    CHAR(2)         NULL,
    latitude        DECIMAL(10,6)   NULL,
    longitude       DECIMAL(10,6)   NULL,
    ports           INT             NULL,
    power_kw        DECIMAL(7,1)    NULL,
    power_class     VARCHAR(30)     NULL,
    is_fast_dc      VARCHAR(10)     NULL
) ENGINE=InnoDB;

CREATE TABLE stg_country_summary (
    country_code        CHAR(2)     NULL,
    country             VARCHAR(100) NULL,
    station_count       INT         NULL,
    port_count          INT         NULL,
    fast_station_share  DECIMAL(10,8) NULL,
    fast_port_share     DECIMAL(10,8) NULL
) ENGINE=InnoDB;

CREATE TABLE stg_ember_electricity (
    area            VARCHAR(100)    NULL,
    iso3_code       CHAR(3)         NULL,
    year            INT             NULL,
    area_type       VARCHAR(50)     NULL,
    continent       VARCHAR(50)     NULL,
    ember_region    VARCHAR(50)     NULL,
    eu              DECIMAL(2,1)    NULL,
    oecd            DECIMAL(2,1)    NULL,
    g20             DECIMAL(2,1)    NULL,
    g7              DECIMAL(2,1)    NULL,
    asean           DECIMAL(2,1)    NULL,
    category        VARCHAR(50)     NULL,
    subcategory     VARCHAR(50)     NULL,
    variable        VARCHAR(50)     NULL,
    unit            VARCHAR(30)     NULL,
    value           DECIMAL(15,4)   NULL,
    yoy_abs_change  DECIMAL(15,4)   NULL,
    yoy_pct_change  DECIMAL(10,4)   NULL
) ENGINE=InnoDB;

CREATE TABLE stg_ch_elec_prices (
    year            INT             NULL,
    avg_price       DECIMAL(10,4)   NULL,   -- Rappen/kWh
    min_price       DECIMAL(10,4)   NULL,
    max_price       DECIMAL(10,4)   NULL,
    num_providers   INT             NULL
) ENGINE=InnoDB;

CREATE TABLE stg_eurostat_elec_prices (
    country_code        CHAR(2)     NULL,
    period              VARCHAR(10) NULL,
    price_eur_per_kwh   DECIMAL(6,4) NULL
) ENGINE=InnoDB;
