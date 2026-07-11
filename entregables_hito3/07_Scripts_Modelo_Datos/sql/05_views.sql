-- =============================================================================
-- 05_views.sql — audit_trail (§3.7) + compatibilidad con el golden_record_view del MVP
-- Ref: 07_Alternativa3_Mejorada_Modelo_Datos.md §3.7, §13
-- =============================================================================
SET search_path TO empi, public;

-- -----------------------------------------------------------------------------
-- audit_trail — proyección de auditoría (§3.7)
-- Es una RE-LECTURA del Event Store, NO una tabla paralela: por diseño no puede
-- desincronizarse de lo que realmente pasó (cumple CA-05.2). El evento ES la auditoría.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW audit_trail AS
SELECT
    e.event_id,
    e.empi_id,
    e.actor,
    e.source_system,
    e.event_type        AS action,
    e.correlation_id,
    e.occurred_at
FROM patient_events e;

COMMENT ON VIEW audit_trail IS 'Auditoría inmutable derivada del Event Store (§3.7). No puede desincronizarse.';

-- -----------------------------------------------------------------------------
-- golden_record_view — compatibilidad con el MVP (doc 01 §9), que colapsaba los
-- dos estados en un único campo `estado`. Se reconstruye desde las dos dimensiones
-- separadas de producción (§3.1, §13) para no romper consumidores del MVP.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW golden_record_view AS
SELECT
    gr.empi_id,
    gr.dni,
    gr.given_name,
    gr.family_name,
    gr.birth_date,
    gr.gender,
    gr.primary_phone,
    gr.primary_email,
    -- Campo `estado` colapsado del MVP: VERIFICADO / INCOMPLETO / INACTIVO.
    -- Se basa en la bandera is_active del catálogo (no en un literal), para no
    -- contradecirlo: EN_REVISION es is_active=true -> conserva su verification_status.
    CASE
        WHEN NOT rs.is_active THEN 'INACTIVO'
        ELSE gr.verification_status
    END                          AS estado,
    gr.active_empi_id            AS empi_id_activo,   -- nombre del MVP
    gr.record_status,
    gr.verification_status,
    gr.updated_at
FROM golden_record gr
JOIN record_status rs ON rs.code = gr.record_status;

COMMENT ON VIEW golden_record_view IS 'Compatibilidad MVP (doc 01 §9): expone el `estado` colapsado sobre el modelo de 2 estados (§13).';

-- -----------------------------------------------------------------------------
-- patient_crosswalk_view — vista legible del crosswalk: todos los IDs de un paciente
-- (útil para construir el par retired_identifiers <-> survivor del ADT^A40, §6/§8)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW patient_crosswalk_view AS
SELECT
    pi.empi_id,
    gr.record_status,
    gr.active_empi_id,
    pi.source_system,
    pi.identifier_type,
    pi.identifier_value,
    pi.assigning_sede,
    pi.use,
    pi.status,
    it.fhir_system
FROM patient_identifier pi
JOIN golden_record   gr ON gr.empi_id = pi.empi_id
JOIN identifier_type it ON it.code    = pi.identifier_type;

COMMENT ON VIEW patient_crosswalk_view IS 'Crosswalk legible por EMPI-ID con URI FHIR de cada identificador (§8).';

GRANT SELECT ON audit_trail, golden_record_view, patient_crosswalk_view
    TO empi_app, empi_projector, empi_readonly;
