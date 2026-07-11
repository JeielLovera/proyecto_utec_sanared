-- =============================================================================
-- patient_360.sql — Plano 5: Vista analítica 360° (BigQuery, GCP)
-- Ref: 07_Alternativa3_Mejorada_Modelo_Datos.md §7
-- =============================================================================
-- Modelo DESNORMALIZADO de solo-lectura. Consolida bajo un EMPI-ID datos nacidos en
-- las 3 nubes: identidad + crosswalk + resultados LIS (Azure) + imágenes DICOM (GCP)
-- + episodios HCE. Resuelve el escenario del paciente anticoagulado (E4).
-- Perfil DEMO: mismo esquema en DuckDB / BigQuery sandbox (§12).
--
-- Dialecto: GoogleSQL (BigQuery). Reemplace `sanared_empi` por su dataset.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS `sanared_empi`
  OPTIONS (location = 'us-central1');

-- -----------------------------------------------------------------------------
-- patient_360 — 1 fila por EMPI-ID activo (materializada por el pipeline analítico)
-- Se alimenta de: (a) identity.patient.* del bus, (b) LIS/HCE vía adaptadores,
-- (c) metadatos DICOM de Cloud Healthcare API (§7).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `sanared_empi.patient_360`
(
  empi_id        STRING NOT NULL OPTIONS (description = 'Identidad enterprise canónica.'),

  identity STRUCT<
    dni         STRING,
    name        STRING,
    birth_date  DATE,
    gender      STRING
  > OPTIONS (description = 'Datos de identidad ganadores por survivorship (§5.1).'),

  -- Proyección del crosswalk: dónde existe este paciente (§3.2)
  identifiers ARRAY<STRUCT<
    source_system    STRING,
    identifier_type  STRING,
    identifier_value STRING,
    assigning_sede   STRING,
    status           STRING
  >>,

  -- Resultados de laboratorio desde LIS (Azure) vía evento/adaptador
  lab_results ARRAY<STRUCT<
    test_code   STRING,
    test_name   STRING,
    value       STRING,
    unit        STRING,
    ref_range   STRING,
    abnormal    BOOL,
    resulted_at TIMESTAMP,
    source_mrn  STRING
  >>,

  -- Estudios DICOM inter-sede, ya unificados por EMPI-ID (GCP Healthcare API)
  imaging_studies ARRAY<STRUCT<
    accession   STRING,
    modality    STRING,
    body_part   STRING,
    sede        STRING,
    study_date  DATE,
    study_uid   STRING
  >>,

  -- Episodios desde HCE
  encounters ARRAY<STRUCT<
    encounter_id STRING,
    sede         STRING,
    class        STRING,
    start_at     TIMESTAMP,
    end_at       TIMESTAMP,
    reason       STRING
  >>,

  -- Antecedentes críticos (el flag ANTICOAGULADO del caso E4)
  flags ARRAY<STRING>,

  last_refreshed TIMESTAMP NOT NULL OPTIONS (description = 'Marca de materialización.')
)
PARTITION BY DATE(last_refreshed)
CLUSTER BY empi_id
OPTIONS (
  description = 'Vista 360° desnormalizada del EMPI (§7). Solo-lectura, reconstruible desde eventos + adaptadores.'
);

-- -----------------------------------------------------------------------------
-- Ejemplo de fila (JSON conceptual, §7):
-- {
--   "empi_id": "EMPI-20250115-0A11BB22",
--   "identity": { "dni": "45678912", "name": "Juan Carlos Ramirez Soto", "birth_date": "1988-04-12" },
--   "identifiers": [ /* crosswalk */ ],
--   "lab_results": [ /* LIS (Azure) */ ],
--   "imaging_studies": [ /* DICOM inter-sede (GCP) */ ],
--   "encounters": [ /* HCE */ ],
--   "flags": ["ANTICOAGULADO"],
--   "last_refreshed": "2026-07-11T14:35:00Z"
-- }
-- -----------------------------------------------------------------------------

-- Consulta típica E4 (continuidad clínica): antecedente crítico + últimos labs
--   SELECT empi_id, identity.name, flags,
--          (SELECT AS STRUCT test_name, value, resulted_at
--           FROM UNNEST(lab_results) ORDER BY resulted_at DESC LIMIT 1) AS ultimo_lab
--   FROM `sanared_empi.patient_360`
--   WHERE empi_id = 'EMPI-20250115-0A11BB22';
