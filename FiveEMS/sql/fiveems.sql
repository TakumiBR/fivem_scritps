CREATE TABLE IF NOT EXISTS fiveems_departments (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(120) NOT NULL,
    code VARCHAR(32) NOT NULL,
    type VARCHAR(24) NOT NULL DEFAULT 'ems',
    blip_x DOUBLE NULL,
    blip_y DOUBLE NULL,
    blip_z DOUBLE NULL,
    settings LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_fiveems_department_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_ranks (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    department_id INT UNSIGNED NOT NULL,
    name VARCHAR(100) NOT NULL,
    grade INT NOT NULL DEFAULT 0,
    permissions LONGTEXT NULL,
    PRIMARY KEY (id),
    KEY idx_fiveems_ranks_department (department_id),
    CONSTRAINT fk_fiveems_rank_department FOREIGN KEY (department_id) REFERENCES fiveems_departments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_members (
    identifier VARCHAR(96) NOT NULL,
    display_name VARCHAR(120) NULL,
    department_id INT UNSIGNED NULL,
    rank_id INT UNSIGNED NULL,
    xp INT NOT NULL DEFAULT 0,
    level INT NOT NULL DEFAULT 1,
    on_duty TINYINT(1) NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (identifier),
    KEY idx_fiveems_member_department (department_id),
    KEY idx_fiveems_member_rank (rank_id),
    CONSTRAINT fk_fiveems_member_department FOREIGN KEY (department_id) REFERENCES fiveems_departments(id) ON DELETE SET NULL,
    CONSTRAINT fk_fiveems_member_rank FOREIGN KEY (rank_id) REFERENCES fiveems_ranks(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_points (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    department_id INT UNSIGNED NOT NULL,
    type VARCHAR(40) NOT NULL,
    label VARCHAR(120) NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    heading DOUBLE NOT NULL DEFAULT 0,
    data LONGTEXT NULL,
    PRIMARY KEY (id),
    KEY idx_fiveems_points_department (department_id),
    KEY idx_fiveems_points_type (type),
    CONSTRAINT fk_fiveems_point_department FOREIGN KEY (department_id) REFERENCES fiveems_departments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_vehicles (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    department_id INT UNSIGNED NOT NULL,
    label VARCHAR(100) NOT NULL,
    model VARCHAR(100) NOT NULL,
    min_level INT NOT NULL DEFAULT 1,
    settings LONGTEXT NULL,
    PRIMARY KEY (id),
    KEY idx_fiveems_vehicle_department (department_id),
    CONSTRAINT fk_fiveems_vehicle_department FOREIGN KEY (department_id) REFERENCES fiveems_departments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_supplies (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    department_id INT UNSIGNED NOT NULL,
    item_name VARCHAR(100) NOT NULL,
    label VARCHAR(120) NOT NULL,
    category VARCHAR(60) NULL,
    quantity INT NOT NULL DEFAULT 0,
    min_level INT NOT NULL DEFAULT 1,
    advanced TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uq_fiveems_supply_item (department_id, item_name),
    CONSTRAINT fk_fiveems_supply_department FOREIGN KEY (department_id) REFERENCES fiveems_departments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_stretcher_profiles (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    department_id INT UNSIGNED NOT NULL,
    vehicle_model VARCHAR(100) NOT NULL,
    stretcher_model VARCHAR(100) NOT NULL,
    inside_transform LONGTEXT NULL,
    outside_transform LONGTEXT NULL,
    patient_transform LONGTEXT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_fiveems_stretcher_vehicle (department_id, vehicle_model),
    CONSTRAINT fk_fiveems_stretcher_department FOREIGN KEY (department_id) REFERENCES fiveems_departments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_vehicle_equipment_profiles (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    department_id INT UNSIGNED NOT NULL,
    vehicle_model VARCHAR(100) NOT NULL,
    transform LONGTEXT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (id),
    UNIQUE KEY uq_fiveems_vehicle_equipment (department_id, vehicle_model),
    CONSTRAINT fk_fiveems_vehicle_equipment_department FOREIGN KEY (department_id) REFERENCES fiveems_departments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_patient_state (
    identifier VARCHAR(96) NOT NULL,
    medical_state LONGTEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_reports (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    patient_identifier VARCHAR(96) NULL,
    provider_identifier VARCHAR(96) NOT NULL,
    department_id INT UNSIGNED NULL,
    report_type VARCHAR(40) NOT NULL,
    payload LONGTEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_fiveems_reports_patient (patient_identifier),
    KEY idx_fiveems_reports_provider (provider_identifier),
    KEY idx_fiveems_reports_department (department_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_xp_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    identifier VARCHAR(96) NOT NULL,
    amount INT NOT NULL,
    reason VARCHAR(120) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_fiveems_xp_identifier (identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_calls (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    external_id VARCHAR(64) NOT NULL,
    title VARCHAR(160) NOT NULL,
    description TEXT NULL,
    x DOUBLE NULL,
    y DOUBLE NULL,
    z DOUBLE NULL,
    priority INT NOT NULL DEFAULT 2,
    status VARCHAR(32) NOT NULL DEFAULT 'open',
    assigned_identifier VARCHAR(96) NULL,
    payload LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_fiveems_call_external (external_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_evidence (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    external_id VARCHAR(64) NOT NULL,
    evidence_type VARCHAR(64) NOT NULL,
    x DOUBLE NULL,
    y DOUBLE NULL,
    z DOUBLE NULL,
    state VARCHAR(32) NOT NULL DEFAULT 'scene',
    source_identifier VARCHAR(96) NULL,
    victim_identifier VARCHAR(96) NULL,
    collector_identifier VARCHAR(96) NULL,
    payload LONGTEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_fiveems_evidence_external (external_id),
    KEY idx_fiveems_evidence_state (state),
    KEY idx_fiveems_evidence_victim (victim_identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_csi_cases (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    department_id INT UNSIGNED NULL,
    title VARCHAR(160) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'open',
    lead_identifier VARCHAR(96) NULL,
    payload LONGTEXT NULL,
    final_report LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP NULL,
    PRIMARY KEY (id),
    KEY idx_fiveems_csi_department (department_id),
    KEY idx_fiveems_csi_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_settings (
    setting_key VARCHAR(80) NOT NULL,
    setting_value LONGTEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_audit_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    actor_identifier VARCHAR(96) NULL,
    action VARCHAR(120) NOT NULL,
    entity_type VARCHAR(60) NULL,
    entity_id VARCHAR(100) NULL,
    payload LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_fiveems_audit_actor (actor_identifier),
    KEY idx_fiveems_audit_action (action)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_schema_migrations (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    version VARCHAR(40) NOT NULL,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_fiveems_schema_version (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_medical_bags (
    identifier VARCHAR(96) NOT NULL,
    contents LONGTEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiveems_encounters (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    patient_identifier VARCHAR(96) NOT NULL,
    provider_identifier VARCHAR(96) NOT NULL,
    department_id INT UNSIGNED NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    patient_kind VARCHAR(16) NOT NULL DEFAULT 'player',
    payload LONGTEXT NULL,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP NULL,
    PRIMARY KEY (id),
    KEY idx_fiveems_encounter_patient (patient_identifier),
    KEY idx_fiveems_encounter_provider (provider_identifier),
    KEY idx_fiveems_encounter_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
