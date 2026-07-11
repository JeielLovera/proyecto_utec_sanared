-- =============================================================================
-- 01_catalogs.sql — Plano 4: Datos de referencia (catálogos del propio EMPI)
-- Ref: 07_Alternativa3_Mejorada_Modelo_Datos.md §5
-- =============================================================================
-- Datos maestros del EMPI (NO de pacientes). En producción los umbrales viven en
-- SSM Parameter Store; aquí `match_config` los replica para el perfil demo (§12).
SET search_path TO empi, public;

-- -----------------------------------------------------------------------------
-- source_system — catálogo de sistemas fuente + PRECEDENCIA de survivorship (§5.1)
-- Doble propósito: identifica el origen Y define qué fuente "gana" un campo en merge.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS source_system (
    code               varchar(24)  PRIMARY KEY,
    cloud_as_is        varchar(40)  NOT NULL,   -- ubicación actual (AS-IS)
    identifier_emitted varchar(12)  NOT NULL,   -- identifier_type que emite (FK lógica)
    precedence         smallint     NOT NULL,   -- 1 = mayor precedencia (gana)
    description        varchar(160) NOT NULL,
    CONSTRAINT ck_source_precedence CHECK (precedence BETWEEN 1 AND 9)
);
COMMENT ON TABLE source_system IS 'Catálogo de sistemas fuente + precedencia de survivorship (§5.1).';

INSERT INTO source_system (code, cloud_as_is, identifier_emitted, precedence, description) VALUES
    ('RENIEC', 'Externo (RENIEC)',        'DNI',       1, 'Registro nacional. Dato legal, máxima precedencia.'),
    ('HCE',    'On-prem Oracle',          'HIST',      2, 'Historia clínica electrónica (por sede). Dato clínico.'),
    ('LIS',    'Azure SQL MI',            'MRN',       3, 'Laboratory Information System.'),
    ('PORTAL', 'AWS / RDS',               'PID',       4, 'Portal de pacientes (autoservicio, menos confiable).'),
    ('PACS',   'Local por sede + GCP',    'ACCESSION', 5, 'Imágenes DICOM (accession por sede).'),
    ('ERP',    'Nube privada',            'ACC',       5, 'ERP de facturación (cuenta).'),
    ('AGENDA', 'SaaS',                    'SCHED-ID',  6, 'Agenda de citas (SaaS).')
ON CONFLICT (code) DO UPDATE
    SET cloud_as_is = EXCLUDED.cloud_as_is,
        identifier_emitted = EXCLUDED.identifier_emitted,
        precedence = EXCLUDED.precedence,
        description = EXCLUDED.description;

-- -----------------------------------------------------------------------------
-- identifier_type — tipos del crosswalk (§5.2)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS identifier_type (
    code        varchar(12)  PRIMARY KEY,
    fhir_system varchar(64)  NOT NULL,   -- URI canónico FHIR (§8)
    description varchar(120) NOT NULL
);

INSERT INTO identifier_type (code, fhir_system, description) VALUES
    ('DNI',       'urn:pe:reniec:dni',   'Documento Nacional de Identidad (RENIEC).'),
    ('HIST',      'urn:sanared:hce',     'Número de historia clínica (por sede).'),
    ('MRN',       'urn:sanared:lis',     'Medical Record Number (LIS).'),
    ('PID',       'urn:sanared:portal',  'Patient ID del Portal.'),
    ('ACCESSION', 'urn:sanared:pacs',    'Accession number de estudio DICOM (por sede).'),
    ('ACC',       'urn:sanared:erp',     'Cuenta de facturación (ERP).'),
    ('SCHED-ID',  'urn:sanared:agenda',  'Identificador de la Agenda SaaS.'),
    ('EMPI',      'urn:sanared:empi',    'Identidad enterprise canónica (el propio EMPI).')
ON CONFLICT (code) DO UPDATE
    SET fhir_system = EXCLUDED.fhir_system, description = EXCLUDED.description;

-- -----------------------------------------------------------------------------
-- record_status — ciclo de vida del Golden Record (§5.2, §9)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS record_status (
    code        varchar(24)  PRIMARY KEY,
    is_active   boolean      NOT NULL,
    description varchar(120) NOT NULL
);

INSERT INTO record_status (code, is_active, description) VALUES
    ('ACTIVO',              true,  'Identidad viva y consultable.'),
    ('EN_REVISION',         true,  'Par candidato en cola B3 (revisión manual).'),
    ('INACTIVO_FUSIONADO',  false, 'Absorbida por un survivor; redirige vía active_empi_id.'),
    ('INACTIVO_DECESO',     false, 'Deceso (fuera de MVP, previsto para Fase 2).')
ON CONFLICT (code) DO UPDATE
    SET is_active = EXCLUDED.is_active, description = EXCLUDED.description;

-- -----------------------------------------------------------------------------
-- event_type — contrato de eventos (§2.2, §5.2). FK lógica desde patient_events.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS event_type (
    code         varchar(40)  PRIMARY KEY,
    command_in   varchar(40)  NOT NULL,   -- Command que lo dispara
    topic_bus    varchar(48),             -- topic cross-cloud (NULL = interno, no cruza)
    flujo        varchar(8),              -- flujo de doc 06
    rf           varchar(16),             -- requisito funcional
    description  varchar(160) NOT NULL
);

INSERT INTO event_type (code, command_in, topic_bus, flujo, rf, description) VALUES
    ('PatientRegistered',   'RegisterPatient',   'identity.patient.created',      'A',   'RF-01',    'Alta de identidad nueva (Flujo A).'),
    ('IdentifierLinked',    'LinkIdentifier',    'identity.patient.updated',      'A/B', 'RF-04',    'Enriquecimiento del crosswalk (nuevo ID local).'),
    ('ContactUpdated',      'UpdateContact',     'identity.patient.updated',      '-',   'RF-05',    'Actualización de contacto (correo/celular).'),
    ('PatientMatchPending', 'FlagForReview',     NULL,                            'B3',  'RF-02',    'Par candidato encolado a revisión manual (interno).'),
    ('PatientMerged',       'MergePatient',      'identity.patient.merged',       'B2',  'RF-02/03', 'Fusión de registros (auto o confirmada).'),
    ('MergeReverted',       'RevertMerge',       'identity.patient.merged',       '-',   'RF-06',    'Reversión de fusión (revert=true).'),
    ('PatientDeactivated',  'DeactivatePatient', 'identity.patient.deactivated',  '-',   'RF-06',    'Desactivación (deceso, fuera de MVP).'),
    ('PatientAccessed',     'RecordAccess',      NULL,                            'B1',  'RNF-03',   'Registro de acceso (interno, opcional).')
ON CONFLICT (code) DO UPDATE
    SET command_in = EXCLUDED.command_in, topic_bus = EXCLUDED.topic_bus,
        flujo = EXCLUDED.flujo, rf = EXCLUDED.rf, description = EXCLUDED.description;

-- -----------------------------------------------------------------------------
-- match_config — umbrales/precedencia (§5.2). En prod vive en SSM Parameter Store
-- (configurable en caliente, RNF-06.2, cache TTL 60 s). Aquí, perfil demo.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS match_config (
    key         varchar(40)  PRIMARY KEY,
    value       varchar(64)  NOT NULL,
    updated_at  timestamptz  NOT NULL DEFAULT now(),
    description  varchar(160) NOT NULL
);

INSERT INTO match_config (key, value, description) VALUES
    ('threshold_auto',   '0.95',       'Score >= => merge automático (B2).'),
    ('threshold_review', '0.85',       'Score en [0.85, 0.95) => cola de revisión (B3).'),
    ('model_version',    'fs-2026.1',  'Versión del modelo Fellegi-Sunter en uso.')
ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, description = EXCLUDED.description, updated_at = now();

-- Permisos de lectura de catálogos
GRANT SELECT ON ALL TABLES IN SCHEMA empi TO empi_app, empi_projector, empi_readonly;
