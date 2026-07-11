-- =============================================================================
-- 99_seed_demo.sql — Datos 100% SINTÉTICOS (Faker es_PE) para la demo
-- Ref: 07_Alternativa3_Mejorada_Modelo_Datos.md §10 (RNF-07: ningún dato real)
-- =============================================================================
-- Reproduce el caso textual: "un DNI ... tres números de historia" (Caso 3a) y un
-- merge automático B2 (§2.2). Los EMPI-ID y DNI son inventados.
-- NOTA: patient_events es append-only; este script solo INSERTA (nunca UPDATE/DELETE).
SET search_path TO empi, public;

-- IDs fijos para poder referenciarlos entre tablas.
--   survivor : EMPI-20250115-0A11BB22  (existente, sobrevive)
--   merged   : EMPI-20260711-8F3A1C7D  (entrante, queda INACTIVO_FUSIONADO)

-- =====================  PLANO 1 — Eventos (fuente de verdad)  =================
INSERT INTO patient_events
    (event_id, empi_id, event_type, event_version, version, payload, actor, source_system, correlation_id, causation_id, occurred_at)
VALUES
-- (1) Alta del survivor por el Portal
('01920000-0001-7000-8000-000000000001', 'EMPI-20250115-0A11BB22', 'PatientRegistered', 1, 1,
 '{"empi_id":"EMPI-20250115-0A11BB22",
   "identifiers":[
     {"system":"urn:pe:reniec:dni","type":"DNI","value":"45678912","use":"official"},
     {"system":"urn:sanared:portal","type":"PID","value":"PT-99182","use":"secondary"}],
   "name":{"given":"Juan Carlos","family":"Ramirez Soto"},
   "birth_date":"1988-04-12","gender":"male",
   "telecom":[{"system":"phone","value":"+51987654321","use":"mobile"},
              {"system":"email","value":"jc.ramirez@correo.pe"}],
   "verification_status":"VERIFICADO",
   "match_context":{"method":"no-match","score":0.41,"model_version":"fs-2026.1"},
   "source_system":"PORTAL"}'::jsonb,
 'SISTEMA:portal', 'PORTAL', '01920000-0000-0000-0000-0000000000c1', NULL, '2025-01-15T09:12:00Z'),

-- (2) Se enriquece el crosswalk con un nº de historia de otra sede (sin merge)
('01920000-0002-7000-8000-000000000002', 'EMPI-20250115-0A11BB22', 'IdentifierLinked', 1, 2,
 '{"empi_id":"EMPI-20250115-0A11BB22",
   "identifier":{"system":"urn:sanared:hce","type":"HIST","value":"HIST-SEDE1-40021","assigning_sede":"SEDE-CENTRAL","use":"official"},
   "linked_reason":"admission","source_system":"HCE"}'::jsonb,
 'ADMISIONISTA:u123', 'HCE', '01920000-0000-0000-0000-0000000000c2', NULL, '2025-03-02T11:40:00Z'),

-- (3) Alta del registro entrante (llega por HCE de la SEDE-3)
('01920000-0003-7000-8000-000000000003', 'EMPI-20260711-8F3A1C7D', 'PatientRegistered', 1, 1,
 '{"empi_id":"EMPI-20260711-8F3A1C7D",
   "identifiers":[
     {"system":"urn:pe:reniec:dni","type":"DNI","value":"45678912","use":"official"},
     {"system":"urn:sanared:hce","type":"HIST","value":"HIST-SEDE3-77123","assigning_sede":"SEDE-3","use":"official"}],
   "name":{"given":"Juan Carlos","family":"Ramirez"},
   "birth_date":"1988-04-12","gender":"male",
   "verification_status":"INCOMPLETO",
   "match_context":{"method":"pending","score":0.971,"model_version":"fs-2026.1"},
   "source_system":"HCE"}'::jsonb,
 'ADMISIONISTA:u456', 'HCE', '01920000-0000-0000-0000-0000000000c3', NULL, '2026-07-11T14:31:00Z'),

-- (4) Merge automático B2 (score 0.971 >= 0.95): survivor absorbe al entrante
('01920000-0004-7000-8000-000000000004', 'EMPI-20250115-0A11BB22', 'PatientMerged', 1, 3,
 '{"survivor_empi_id":"EMPI-20250115-0A11BB22",
   "merged_empi_id":"EMPI-20260711-8F3A1C7D",
   "decided_by":"AUTO","match_score":0.971,"model_version":"fs-2026.1",
   "survivorship":{"family":{"value":"Ramirez Soto","won_by":"HCE"},
                   "email":{"value":"jc.ramirez@correo.pe","won_by":"PORTAL"}},
   "retired_identifiers":[{"system":"urn:sanared:hce","type":"HIST","value":"HIST-SEDE3-77123"}]}'::jsonb,
 'SISTEMA:matcher', 'HCE', '01920000-0000-0000-0000-0000000000c3', '01920000-0003-7000-8000-000000000003', '2026-07-11T14:31:05Z');

-- =====================  PLANO 2 — Proyecciones (derivadas)  ===================
INSERT INTO golden_record
    (empi_id, dni, given_name, family_name, birth_date, gender, primary_phone, primary_email,
     record_status, verification_status, active_empi_id, source_precedence_hash)
VALUES
('EMPI-20250115-0A11BB22', '45678912', 'Juan Carlos', 'Ramirez Soto', '1988-04-12', 'male',
 '+51987654321', 'jc.ramirez@correo.pe', 'ACTIVO', 'VERIFICADO',
 'EMPI-20250115-0A11BB22', 'sha256:hce>portal'),
('EMPI-20260711-8F3A1C7D', '45678912', 'Juan Carlos', 'Ramirez', '1988-04-12', 'male',
 NULL, NULL, 'INACTIVO_FUSIONADO', 'INCOMPLETO',
 'EMPI-20250115-0A11BB22', NULL)   -- active_empi_id redirige al survivor (§9)
ON CONFLICT (empi_id) DO NOTHING;

-- Crosswalk: el survivor concentra DNI + PID + HIST de 2 sedes; el ID del absorbido -> RETIRED
INSERT INTO patient_identifier
    (empi_id, source_system, identifier_type, identifier_value, assigning_sede, use, status)
VALUES
('EMPI-20250115-0A11BB22', 'RENIEC', 'DNI',  '45678912',        NULL,           'official',  'ACTIVE'),
('EMPI-20250115-0A11BB22', 'PORTAL', 'PID',  'PT-99182',        NULL,           'secondary', 'ACTIVE'),
('EMPI-20250115-0A11BB22', 'HCE',    'HIST', 'HIST-SEDE1-40021','SEDE-CENTRAL', 'official',  'ACTIVE'),
-- El HIST de la SEDE-3 se conserva pero apunta al survivor (§3.2)
('EMPI-20250115-0A11BB22', 'HCE',    'HIST', 'HIST-SEDE3-77123','SEDE-3',       'old',       'ACTIVE'),
-- DNI del registro absorbido: RETIRED (por eso no viola el índice único parcial)
('EMPI-20260711-8F3A1C7D', 'RENIEC', 'DNI',  '45678912',        NULL,           'old',       'RETIRED')
ON CONFLICT DO NOTHING;

INSERT INTO patient_name (empi_id, given_name, family_name, use, source_system)
VALUES
('EMPI-20250115-0A11BB22', 'Juan Carlos', 'Ramirez Soto', 'official', 'HCE'),
('EMPI-20250115-0A11BB22', 'Juan Carlos', 'Ramirez',      'previous', 'PORTAL');

INSERT INTO patient_contact (empi_id, system, value, use, source_system, verified)
VALUES
('EMPI-20250115-0A11BB22', 'PHONE', '+51987654321',        'mobile', 'PORTAL', true),
('EMPI-20250115-0A11BB22', 'EMAIL', 'jc.ramirez@correo.pe','home',   'PORTAL', false);

-- Linaje de la fusión (reversible)
INSERT INTO merge_link
    (survivor_empi_id, merged_empi_id, match_score, decided_by, merge_event_id)
VALUES
('EMPI-20250115-0A11BB22', 'EMPI-20260711-8F3A1C7D', 0.971, 'AUTO',
 '01920000-0004-7000-8000-000000000004');

-- Evidencia del scoring que motivó el merge
INSERT INTO match_candidate
    (empi_id_a, empi_id_b_or_stg, match_score, features, band, model_version, correlation_id)
VALUES
('EMPI-20250115-0A11BB22', 'EMPI-20260711-8F3A1C7D', 0.971,
 '{"jaro_winkler_name":0.98,"metaphone_match":true,"dob_equal":true,"phone_equal":false,"dni_equal":true}'::jsonb,
 'AUTO_MERGE', 'fs-2026.1', '01920000-0000-0000-0000-0000000000c3');

-- ======  Ejemplo B3 (revisión manual): un familiar homónimo, NO se fusiona  ==
INSERT INTO golden_record
    (empi_id, dni, given_name, family_name, birth_date, gender,
     record_status, verification_status, active_empi_id)
VALUES
('EMPI-20260711-77AA33BB', '71234567', 'Juan', 'Ramirez Soto', '2010-09-01', 'male',
 'EN_REVISION', 'INCOMPLETO', 'EMPI-20260711-77AA33BB')
ON CONFLICT (empi_id) DO NOTHING;

WITH c AS (
  INSERT INTO match_candidate
    (empi_id_a, empi_id_b_or_stg, match_score, features, band, model_version, correlation_id)
  VALUES
  ('EMPI-20250115-0A11BB22', 'STG-2026-000481', 0.902,
   '{"jaro_winkler_name":0.94,"metaphone_match":true,"dob_equal":false,"phone_equal":false,"dni_equal":false}'::jsonb,
   'REVIEW', 'fs-2026.1', '01920000-0000-0000-0000-0000000000d1')
  RETURNING candidate_pair_id, match_score
)
INSERT INTO review_queue (candidate_pair_id, priority, status)
SELECT candidate_pair_id, match_score, 'PENDING' FROM c;

-- =====================  Verificación rápida  =================================
--   SELECT * FROM golden_record_view;
--   SELECT * FROM patient_crosswalk_view WHERE empi_id = 'EMPI-20250115-0A11BB22';
--   SELECT action, actor, occurred_at FROM audit_trail ORDER BY occurred_at;
--   SELECT * FROM review_queue WHERE status = 'PENDING' ORDER BY priority DESC;
