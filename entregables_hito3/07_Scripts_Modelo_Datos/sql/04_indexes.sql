-- =============================================================================
-- 04_indexes.sql — Plano 3 (perfil DEMO): blocking difuso con pg_trgm/metaphone
-- Ref: 07_Alternativa3_Mejorada_Modelo_Datos.md §4.1, §11, §12
-- =============================================================================
-- En PRODUCCIÓN el blocking (Paso 2) lo hace OpenSearch (ver opensearch/). En DEMO
-- se sustituye por pg_trgm sobre golden_record: MISMA función de blocking, sin
-- OpenSearch; la lógica del flujo no cambia (§12, doc 06 §7).
SET search_path TO empi, public;

-- -----------------------------------------------------------------------------
-- Índices trigram para fuzzy match sobre nombres (edge-ngram equivalente §4.1)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_golden_given_trgm
    ON golden_record USING gin (given_name gin_trgm_ops)
    WHERE record_status = 'ACTIVO';

CREATE INDEX IF NOT EXISTS ix_golden_family_trgm
    ON golden_record USING gin (family_name gin_trgm_ops)
    WHERE record_status = 'ACTIVO';

-- Rango de año de nacimiento (FN ±1 año, §4.1)
CREATE INDEX IF NOT EXISTS ix_golden_birthyear
    ON golden_record (EXTRACT(YEAR FROM birth_date))
    WHERE record_status = 'ACTIVO';

-- -----------------------------------------------------------------------------
-- Vista de blocking: replica el documento golden-record-idx de OpenSearch (§4.1)
-- Expone las mismas features (fonética + ngram + birth_year + phone_last4).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW golden_record_blocking AS
SELECT
    gr.empi_id,
    gr.dni,
    -- Double Metaphone (español) sobre nombre y apellido
    dmetaphone(gr.given_name)                       AS given_phonetic,
    dmetaphone(gr.family_name)                       AS family_phonetic,
    lower(gr.given_name || ' ' || gr.family_name)    AS name_ngram_src,
    EXTRACT(YEAR FROM gr.birth_date)::int            AS birth_year,
    right(regexp_replace(coalesce(gr.primary_phone,''), '\D', '', 'g'), 4) AS phone_last4,
    gr.record_status
FROM golden_record gr
WHERE gr.record_status = 'ACTIVO';

COMMENT ON VIEW golden_record_blocking IS
    'Perfil DEMO del índice de blocking (§4.1). En prod es el índice golden-record-idx de OpenSearch.';

GRANT SELECT ON golden_record_blocking TO empi_app, empi_projector, empi_readonly;

-- -----------------------------------------------------------------------------
-- Ejemplo de consulta de blocking DEMO (candidatos a matching, Paso 2):
-- -----------------------------------------------------------------------------
--   SELECT empi_id, dni, family_name,
--          similarity(family_name, 'Ramirez Soto') AS sim
--   FROM   golden_record
--   WHERE  record_status = 'ACTIVO'
--     AND  family_name % 'Ramirez Soto'                    -- pg_trgm (edge-ngram)
--     AND  EXTRACT(YEAR FROM birth_date) BETWEEN 1987 AND 1989
--   ORDER BY sim DESC
--   LIMIT 25;
