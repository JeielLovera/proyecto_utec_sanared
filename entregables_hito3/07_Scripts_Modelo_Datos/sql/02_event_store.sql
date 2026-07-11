-- =============================================================================
-- 02_event_store.sql — Plano 1: Modelo de Escritura (Event Store)
-- Ref: 07_Alternativa3_Mejorada_Modelo_Datos.md §2
-- =============================================================================
-- Única tabla en la que se escribe el estado de identidad. Inmutable (ADR-A3M-007):
-- sin UPDATE ni DELETE. Los planos 2, 3 y 5 son proyecciones reconstruibles de aquí.
SET search_path TO empi, public;

-- -----------------------------------------------------------------------------
-- patient_events (append-only) — el "sobre" del evento (§2.1)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patient_events (
    event_id        uuid         NOT NULL DEFAULT empi.uuid_generate_v7(),  -- PK, v7 ordenable
    empi_id         varchar(32)  NOT NULL,   -- formato EMPI-YYYYMMDD-XXXXXXXX
    event_type      varchar(40)  NOT NULL,   -- FK -> event_type (catálogo §2.2)
    event_version   smallint     NOT NULL DEFAULT 1,   -- versión del ESQUEMA del payload
    version         bigint       NOT NULL,   -- nº de secuencia del agregado (concurrencia)
    payload         jsonb        NOT NULL,   -- datos del evento (FHIR-compatible §2.2)
    actor           varchar(64)  NOT NULL,   -- 'ADMISIONISTA:u123', 'SISTEMA:portal'
    source_system   varchar(24)  NOT NULL,   -- FK -> source_system
    correlation_id  uuid         NOT NULL,   -- trazabilidad end-to-end
    causation_id    uuid,                     -- event_id que causó este (linaje causal)
    occurred_at     timestamptz  NOT NULL,   -- momento del hecho de negocio
    recorded_at     timestamptz  NOT NULL DEFAULT now(),  -- momento de persistencia

    CONSTRAINT pk_patient_events            PRIMARY KEY (event_id),
    -- Concurrencia optimista: dos escrituras concurrentes sobre el mismo agregado
    -- no pueden compartir versión -> soporta el escenario E2 sin duplicar (§2.1).
    CONSTRAINT uq_patient_events_aggregate  UNIQUE (empi_id, version),
    CONSTRAINT fk_patient_events_type       FOREIGN KEY (event_type)    REFERENCES event_type (code),
    CONSTRAINT fk_patient_events_source     FOREIGN KEY (source_system) REFERENCES source_system (code),
    CONSTRAINT ck_patient_events_empi_fmt   CHECK (empi_id ~ '^EMPI-[0-9]{8}-[0-9A-F]{8}$'),
    CONSTRAINT ck_patient_events_version    CHECK (version >= 0),
    CONSTRAINT ck_patient_events_payload    CHECK (jsonb_typeof(payload) = 'object')
);
COMMENT ON TABLE  patient_events IS 'Event Store append-only. Única fuente de verdad (§2.1, ADR-A3M-007).';
COMMENT ON COLUMN patient_events.version IS 'Secuencia del agregado; UNIQUE(empi_id,version) = concurrencia optimista.';

-- Índices de lectura del proyector y de auditoría (§2.1)
CREATE INDEX IF NOT EXISTS ix_patient_events_aggregate    ON patient_events (empi_id, version);
CREATE INDEX IF NOT EXISTS ix_patient_events_correlation  ON patient_events (correlation_id);
CREATE INDEX IF NOT EXISTS ix_patient_events_type_time    ON patient_events (event_type, occurred_at);
CREATE INDEX IF NOT EXISTS ix_patient_events_causation    ON patient_events (causation_id) WHERE causation_id IS NOT NULL;
-- Consultas por payload (p. ej. buscar por identificador dentro del evento)
CREATE INDEX IF NOT EXISTS ix_patient_events_payload_gin  ON patient_events USING gin (payload jsonb_path_ops);

-- -----------------------------------------------------------------------------
-- APPEND-ONLY reforzado EN LA BASE DE DATOS, no solo en la app (§2.1).
-- Equivalente a la política append-only que en el Hito 2 daba Cosmos DB.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION empi.block_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'patient_events es append-only (ADR-A3M-007): la operacion % esta prohibida', TG_OP
        USING ERRCODE = 'restrict_violation',
              HINT = 'Para corregir estado, emita un nuevo evento compensatorio (MergeReverted, ContactUpdated...).';
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_patient_events_append_only ON patient_events;
CREATE TRIGGER trg_patient_events_append_only
    BEFORE UPDATE OR DELETE ON patient_events
    FOR EACH ROW EXECUTE FUNCTION empi.block_event_mutation();

-- Doble cinturón: revocar el privilegio a nivel SQL además del trigger.
REVOKE UPDATE, DELETE, TRUNCATE ON patient_events FROM PUBLIC;

-- El servicio solo puede INSERTAR y LEER eventos.
GRANT INSERT, SELECT ON patient_events TO empi_app;
GRANT SELECT ON patient_events TO empi_projector, empi_readonly;
