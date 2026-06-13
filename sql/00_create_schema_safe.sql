USE ev_project;

CREATE TABLE IF NOT EXISTS country (
  country_code        CHAR(2)        NOT NULL,
  country_name        VARCHAR(100)   NOT NULL,
  petrol_price_eur_per_l DECIMAL(5,3)  DEFAULT NULL,
  diesel_price_eur_per_l DECIMAL(5,3)  DEFAULT NULL,
  PRIMARY KEY (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vehicle (
  vehicle_id   INT            NOT NULL AUTO_INCREMENT,
  make         VARCHAR(50)    NOT NULL,
  model        VARCHAR(100)   NOT NULL,
  fuel_type    VARCHAR(30)    NOT NULL,
  vehicle_class VARCHAR(50)   DEFAULT NULL,
  price_usd    DECIMAL(12,2)  DEFAULT NULL,
  horsepower   INT            DEFAULT NULL,
  seats        INT            DEFAULT NULL,
  PRIMARY KEY (vehicle_id),
  KEY idx_vehicle_make (make),
  KEY idx_vehicle_fuel_type (fuel_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ice_emission (
  ice_emission_id      INT          NOT NULL AUTO_INCREMENT,
  vehicle_id           INT          NOT NULL,
  engine_size_l        DECIMAL(3,1) DEFAULT NULL,
  cylinders            TINYINT      DEFAULT NULL,
  transmission         VARCHAR(10)  DEFAULT NULL,
  fuel_consumption_city DECIMAL(4,1) DEFAULT NULL,
  fuel_consumption_hwy DECIMAL(4,1) DEFAULT NULL,
  fuel_consumption_comb DECIMAL(4,1) DEFAULT NULL,
  co2_emissions_gkm    INT          DEFAULT NULL,
  PRIMARY KEY (ice_emission_id),
  KEY idx_ice_vehicle (vehicle_id),
  CONSTRAINT ice_emission_ibfk_1
    FOREIGN KEY (vehicle_id) REFERENCES vehicle (vehicle_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ev_spec (
  ev_spec_id                 INT          NOT NULL AUTO_INCREMENT,
  vehicle_id                 INT          NOT NULL,
  battery_capacity_kwh       DECIMAL(5,1) DEFAULT NULL,
  range_wltp_km              INT          DEFAULT NULL,
  energy_consumption_kwh_100km DECIMAL(4,1) DEFAULT NULL,
  dc_charge_power_kw         INT          DEFAULT NULL,
  ac_charge_power_kw         DECIMAL(4,1) DEFAULT NULL,
  release_year               INT          DEFAULT NULL,
  PRIMARY KEY (ev_spec_id),
  KEY idx_ev_vehicle (vehicle_id),
  CONSTRAINT ev_spec_ibfk_1
    FOREIGN KEY (vehicle_id) REFERENCES vehicle (vehicle_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS charging_station (
  station_id      INT           NOT NULL,
  name            VARCHAR(255)  DEFAULT NULL,
  city            VARCHAR(100)  DEFAULT NULL,
  state_province  VARCHAR(100)  DEFAULT NULL,
  country_code    CHAR(2)       NOT NULL,
  latitude        DECIMAL(10,6) DEFAULT NULL,
  longitude       DECIMAL(10,6) DEFAULT NULL,
  ports           INT           DEFAULT NULL,
  power_kw        DECIMAL(7,1)  DEFAULT NULL,
  power_class     VARCHAR(30)   DEFAULT NULL,
  is_fast_dc      TINYINT(1)    DEFAULT NULL,
  PRIMARY KEY (station_id),
  KEY idx_station_country (country_code),
  KEY idx_station_power_class (power_class),
  CONSTRAINT charging_station_ibfk_1
    FOREIGN KEY (country_code) REFERENCES country (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS charging_country_summary (
  country_code       CHAR(2)      NOT NULL,
  station_count      INT          DEFAULT NULL,
  port_count         INT          DEFAULT NULL,
  fast_station_share DECIMAL(5,4) DEFAULT NULL,
  fast_port_share    DECIMAL(5,4) DEFAULT NULL,
  PRIMARY KEY (country_code),
  CONSTRAINT charging_country_summary_ibfk_1
    FOREIGN KEY (country_code) REFERENCES country (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS electricity_price (
  elec_price_id    INT          NOT NULL AUTO_INCREMENT,
  country_code     CHAR(2)      NOT NULL,
  year             INT          NOT NULL,
  half_year        TINYINT      DEFAULT NULL,
  price_eur_per_kwh DECIMAL(6,4) NOT NULL,
  PRIMARY KEY (elec_price_id),
  UNIQUE KEY idx_elec_price_unique (country_code, year, half_year),
  KEY idx_elec_price_country_year (country_code, year),
  CONSTRAINT electricity_price_ibfk_1
    FOREIGN KEY (country_code) REFERENCES country (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS grid_mix (
  grid_mix_id        INT           NOT NULL AUTO_INCREMENT,
  country_code       CHAR(2)       NOT NULL,
  year               INT           NOT NULL,
  source_type        VARCHAR(30)   NOT NULL,
  generation_twh     DECIMAL(10,2) DEFAULT NULL,
  share_pct          DECIMAL(5,2)  DEFAULT NULL,
  co2_intensity_gkwh DECIMAL(7,2)  DEFAULT NULL,
  PRIMARY KEY (grid_mix_id),
  UNIQUE KEY idx_grid_mix_unique (country_code, year, source_type),
  KEY idx_grid_mix_country_year (country_code, year),
  CONSTRAINT grid_mix_ibfk_1
    FOREIGN KEY (country_code) REFERENCES country (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ev_adoption (
  ev_adoption_id     INT          NOT NULL AUTO_INCREMENT,
  country_code       CHAR(2)      NOT NULL,
  year               INT          NOT NULL,
  powertrain         VARCHAR(10)  NOT NULL,
  ev_sales           INT          DEFAULT NULL,
  ev_stock           INT          DEFAULT NULL,
  ev_sales_share_pct DECIMAL(6,3) DEFAULT NULL,
  ev_stock_share_pct DECIMAL(6,3) DEFAULT NULL,
  PRIMARY KEY (ev_adoption_id),
  UNIQUE KEY idx_ev_adoption_unique (country_code, year, powertrain),
  KEY idx_ev_adoption_country_year (country_code, year),
  CONSTRAINT ev_adoption_ibfk_1
    FOREIGN KEY (country_code) REFERENCES country (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
