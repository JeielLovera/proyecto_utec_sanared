-- =============================================================================
-- 03_projections.sql — Plano 2: Modelo de Lectura (proyecciones CQRS)
-- Ref: 07_Alternativa3_Mejorada_Modelo_Datos.md §3
-- =============================================================================
-- Un proyector consume patient_events en orden y mantiene estas tablas. TODAS son
-- reconstruibles reproduciendo eventos. Consistencia eventual < 1-5 s (§3).
SET search_path TO empi, public;

-- -----------------------------------------------------------------------------
-- 3.1  golden_record — la identidad canónica (1 fila por EMPI-ID)
--       Separa las DOS dimensiones de estado que el MVP colapsaba (§3.1, §13).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS golden_record (
    empi_id                varchar(32)  PRIMARY KEY,
    dni                    varchar(12),          -- denormalizado desde el xref (lookup rápido)
    given_name             varchar(120),         -- valor GANADOR por survivorship (§5.3)
    family_name            varchar(120),
    birth_date             date,
    gender                 varchar(12),          -- FHIR administrative-gender
    primary_phone          varchar(20),          -- denormalizado; maestro en patient_contact
    primary_email          varchar(120),         -- denormalizado
    record_status          varchar(24)  NOT NULL DEFAULT 'ACTIVO',  -- vida/merge/deceso
    verification_status    varchar(16)  NOT NULL DEFAULT 'INCOMPLETO', -- completitud del dato
    active_empi_id         varchar(32)  NOT NULL, -- si INACTIVO_FUSIONADO -> survivor; si ACTIVO -> =empi_id
    source_precedence_hash varchar(64),          -- huella de qué fuente aportó cada campo
    created_at             timestamptz  NOT NULL DEFAULT now(),
    updated_at             timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT fk_golden_record_status  FOREIGN KEY (record_status) REFERENCES record_status (code),
    CONSTRAINT ck_golden_empi_fmt       CHECK (empi_id ~ '^EMPI-[0-9]{8}-[0-9A-F]{8}$'),
    CONSTRAINT ck_golden_verification   CHECK (verification_status IN ('VERIFICADO','INCOMPLETO')),
    CONSTRAINT ck_golden_gender         CHECK (gender IS NULL OR gender IN ('male','female','other','unknown'))
);
COMMENT ON TABLE  golden_record IS 'Identidad canónica. record_status=vida/merge; verification_status=completitud (§3.1).';
COMMENT ON COLUMN golden_record.active_empi_id IS 'Redirección: si fusionado, apunta al survivor (§9).';

-- Un DNI ACTIVO no puede colgar de dos golden records (refuerza CA-01.2).
CREATE UNIQUE INDEX IF NOT EXISTS uq_golden_dni_active
    ON golden_record (dni)
    WHERE record_status = 'ACTIVO' AND dni IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_golden_active_empi ON golden_record (active_empi_id);
CREATE INDEX IF NOT EXISTS ix_golden_status      ON golden_record (record_status);

-- -----------------------------------------------------------------------------
-- 3.2  patient_identifier — el CROSSWALK (corazón del EMPI) ⭐
--       1 fila por cada identificador conocido de cada paciente en cada sistema.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patient_identifier (
    identifier_id     uuid         NOT NULL DEFAULT gen_random_uuid(),
    empi_id           varchar(32)  NOT NULL,
    source_system     varchar(24)  NOT NULL,
    identifier_type   varchar(12)  NOT NULL,
    identifier_value  varchar(64)  NOT NULL,
    assigning_sede    varchar(24),          -- sede que asignó el ID (clave PACS/HCE por sede)
    use               varchar(12)  NOT NULL DEFAULT 'official', -- official/secondary/old
    status            varchar(12)  NOT NULL DEFAULT 'ACTIVE',   -- ACTIVE/RETIRED
    first_seen_at     timestamptz  NOT NULL DEFAULT now(),
    last_seen_at      timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT pk_patient_identifier      PRIMARY KEY (identifier_id),
    CONSTRAINT fk_identifier_golden       FOREIGN KEY (empi_id)         REFERENCES golden_record (empi_id),
    CONSTRAINT fk_identifier_source       FOREIGN KEY (source_system)   REFERENCES source_system (code),
    CONSTRAINT fk_identifier_type         FOREIGN KEY (identifier_type) REFERENCES identifier_type (code),
    CONSTRAINT ck_identifier_use          CHECK (use    IN ('official','secondary','old')),
    CONSTRAINT ck_identifier_status       CHECK (status IN ('ACTIVE','RETIRED'))
);
COMMENT ON TABLE patient_identifier IS 'Crosswalk: identificadores locales -> EMPI-ID. Convierte "otra base" en índice maestro (§3.2).';

-- RESTRICCIÓN CLAVE (§3.2): un mismo identificador ACTIVO no puede colgar de dos EMPI-ID
-- => imposibilita el duplicado por diseño a nivel de datos (CA-01.2).
CREATE UNIQUE INDEX IF NOT EXISTS uq_identifier_active
    ON patient_identifier (source_system, identifier_type, identifier_value)
    WHERE status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS ix_identifier_empi ON patient_identifier (empi_id);
CREATE INDEX IF NOT EXISTS ix_identifier_dni
    ON patient_identifier (identifier_value)
    WHERE identifier_type = 'DNI';

-- -----------------------------------------------------------------------------
-- 3.3  Atributos multivaluados: nombres, contactos, direcciones (§3.3)
--       Se guardan TODAS las variantes vistas (alimentan matching, evitan pérdidas).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patient_name (
    name_id        uuid         NOT NULL DEFAULT gen_random_uuid(),
    empi_id        varchar(32)  NOT NULL REFERENCES golden_record (empi_id),
    given_name     varchar(120) NOT NULL,
    family_name    varchar(120) NOT NULL,
    use            varchar(12)  NOT NULL DEFAULT 'official',  -- official/alias/previous
    source_system  varchar(24)  NOT NULL REFERENCES source_system (code),
    valid_from     date,
    valid_to       date,
    CONSTRAINT pk_patient_name PRIMARY KEY (name_id),
    CONSTRAINT ck_name_use     CHECK (use IN ('official','alias','previous'))
);
CREATE INDEX IF NOT EXISTS ix_name_empi ON patient_name (empi_id);

CREATE TABLE IF NOT EXISTS patient_contact (
    contact_id     uuid         NOT NULL DEFAULT gen_random_uuid(),
    empi_id        varchar(32)  NOT NULL REFERENCES golden_record (empi_id),
    system         varchar(8)   NOT NULL,  -- PHONE/EMAIL
    value          varchar(160) NOT NULL,
    use            varchar(12)  NOT NULL DEFAULT 'mobile', -- mobile/home/work
    source_system  varchar(24)  NOT NULL REFERENCES source_system (code),
    verified       boolean      NOT NULL DEFAULT false,
    CONSTRAINT pk_patient_contact PRIMARY KEY (contact_id),
    CONSTRAINT ck_contact_system  CHECK (system IN ('PHONE','EMAIL')),
    CONSTRAINT ck_contact_use     CHECK (use    IN ('mobile','home','work'))
);
CREATE INDEX IF NOT EXISTS ix_contact_empi ON patient_contact (empi_id);

CREATE TABLE IF NOT EXISTS patient_address (
    address_id     uuid         NOT NULL DEFAULT gen_random_uuid(),
    empi_id        varchar(32)  NOT NULL REFERENCES golden_record (empi_id),
    line           varchar(160),
    city           varchar(80),
    district       varchar(80),
    postal_code    varchar(12),
    use            varchar(12)  NOT NULL DEFAULT 'home',
    source_system  varchar(24)  NOT NULL REFERENCES source_system (code),
    CONSTRAINT pk_patient_address PRIMARY KEY (address_id)
);
CREATE INDEX IF NOT EXISTS ix_address_empi ON patient_address (empi_id);

-- -----------------------------------------------------------------------------
-- 3.4  patient_relationship — dependientes familiares (evita el sobre-merge, E5) (§3.4)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patient_relationship (
    relationship_id  uuid         NOT NULL DEFAULT gen_random_uuid(),
    empi_id          varchar(32)  NOT NULL REFERENCES golden_record (empi_id),   -- titular
    related_empi_id  varchar(32)  NOT NULL REFERENCES golden_record (empi_id),   -- relacionado
    type             varchar(20)  NOT NULL,
    valid_from       date,
    valid_to         date,
    CONSTRAINT pk_patient_relationship PRIMARY KEY (relationship_id),
    CONSTRAINT ck_relationship_type    CHECK (type IN ('DEPENDIENTE_DE','TUTOR_DE','CONYUGE_DE','HERMANO_DE')),
    CONSTRAINT ck_relationship_distinct CHECK (empi_id <> related_empi_id)
);
CREATE INDEX IF NOT EXISTS ix_relationship_empi ON patient_relationship (empi_id);

-- -----------------------------------------------------------------------------
-- 3.5  merge_link — linaje de fusión (reversible, RF-06) (§3.5)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS merge_link (
    merge_id          uuid          NOT NULL DEFAULT gen_random_uuid(),
    survivor_empi_id  varchar(32)   NOT NULL REFERENCES golden_record (empi_id),
    merged_empi_id    varchar(32)   NOT NULL REFERENCES golden_record (empi_id),
    match_score       numeric(4,3)  NOT NULL,
    decided_by        varchar(32)   NOT NULL,  -- 'AUTO' | 'OPERADOR:uXXX'
    merged_at         timestamptz   NOT NULL DEFAULT now(),
    reverted          boolean       NOT NULL DEFAULT false,
    reverted_at       timestamptz,
    reverted_by       varchar(32),
    merge_event_id    uuid          NOT NULL REFERENCES patient_events (event_id),
    CONSTRAINT pk_merge_link       PRIMARY KEY (merge_id),
    CONSTRAINT ck_merge_score      CHECK (match_score >= 0 AND match_score <= 1),
    CONSTRAINT ck_merge_distinct   CHECK (survivor_empi_id <> merged_empi_id)
);
CREATE INDEX IF NOT EXISTS ix_merge_survivor ON merge_link (survivor_empi_id);
CREATE INDEX IF NOT EXISTS ix_merge_merged   ON merge_link (merged_empi_id);

-- -----------------------------------------------------------------------------
-- 3.6  match_candidate + review_queue — cola B3 y evidencia del scoring (§3.6)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS match_candidate (
    candidate_pair_id  uuid          NOT NULL DEFAULT gen_random_uuid(),
    empi_id_a          varchar(32)   NOT NULL,   -- existente
    empi_id_b_or_stg   varchar(64)   NOT NULL,   -- existente vs entrante (ref staging STG-...)
    match_score        numeric(4,3)  NOT NULL,
    features           jsonb         NOT NULL,   -- jaro/metaphone/dob/phone/dni (§2.2)
    band               varchar(16)   NOT NULL,   -- AUTO_MERGE/REVIEW/NO_MATCH
    model_version      varchar(24)   NOT NULL,
    correlation_id     uuid          NOT NULL,
    created_at         timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_match_candidate PRIMARY KEY (candidate_pair_id),
    CONSTRAINT ck_candidate_band  CHECK (band IN ('AUTO_MERGE','REVIEW','NO_MATCH')),
    CONSTRAINT ck_candidate_score CHECK (match_score >= 0 AND match_score <= 1)
);
CREATE INDEX IF NOT EXISTS ix_candidate_corr ON match_candidate (correlation_id);

CREATE TABLE IF NOT EXISTS review_queue (
    queue_id           uuid          NOT NULL DEFAULT gen_random_uuid(),
    candidate_pair_id  uuid          NOT NULL REFERENCES match_candidate (candidate_pair_id),
    priority           numeric(4,3)  NOT NULL,   -- = score desc (más cerca de 0.95 primero)
    status             varchar(12)   NOT NULL DEFAULT 'PENDING', -- PENDING/CONFIRMED/REJECTED
    assigned_to        varchar(32),
    enqueued_at        timestamptz   NOT NULL DEFAULT now(),
    resolved_at        timestamptz,
    CONSTRAINT pk_review_queue    PRIMARY KEY (queue_id),
    CONSTRAINT ck_review_status   CHECK (status IN ('PENDING','CONFIRMED','REJECTED')),
    CONSTRAINT uq_review_candidate UNIQUE (candidate_pair_id)
);
-- Prioridad de la cola = score descendente (minimiza riesgo clínico §3.6)
CREATE INDEX IF NOT EXISTS ix_review_pending
    ON review_queue (priority DESC, enqueued_at)
    WHERE status = 'PENDING';

-- -----------------------------------------------------------------------------
-- Permisos: el proyector escribe proyecciones; la app y readonly solo leen.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON
    golden_record, patient_identifier, patient_name, patient_contact,
    patient_address, patient_relationship, merge_link, match_candidate, review_queue
    TO empi_projector;
GRANT SELECT ON
    golden_record, patient_identifier, patient_name, patient_contact,
    patient_address, patient_relationship, merge_link, match_candidate, review_queue
    TO empi_app, empi_readonly;
