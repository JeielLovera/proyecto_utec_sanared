-- =============================================================================
-- 00_extensions.sql — Extensiones y utilidades base
-- EMPI Alt. 3 Mejorada · Plano de escritura/lectura (RDS PostgreSQL)
-- Ref: 07_Alternativa3_Mejorada_Modelo_Datos.md §2, §4
-- =============================================================================
-- Idempotente: puede re-ejecutarse sin error.

-- pgcrypto  -> gen_random_uuid(), digest() (SHA-256 para claves de caché §4.2)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- pg_trgm   -> blocking difuso en modo DEMO, sustituto de OpenSearch (§4.1, §12)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- fuzzystrmatch -> metaphone/dmetaphone y levenshtein para el scoring fonético (§4.1)
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

-- -----------------------------------------------------------------------------
-- Esquema lógico del EMPI (todo el modelo vive aquí para aislarlo del resto)
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS empi;
SET search_path TO empi, public;

-- -----------------------------------------------------------------------------
-- uuid_generate_v7() — UUID v7 (ordenable por tiempo), útil para el proyector (§2.1)
-- NOTA: PostgreSQL 18+ trae uuidv7() nativo. Esta función es el FALLBACK para
--       PG 14–17. Si tu servidor es PG18+, puedes reemplazar el DEFAULT por uuidv7().
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION empi.uuid_generate_v7()
RETURNS uuid
LANGUAGE sql
VOLATILE
AS $$
  -- Toma un UUID aleatorio y sobreescribe los primeros 48 bits con el timestamp
  -- Unix en milisegundos, fijando el nibble de versión a 7 (RFC 9562).
  SELECT encode(
    set_bit(
      set_bit(
        overlay(
          uuid_send(gen_random_uuid())
          PLACING substring(int8send((extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3)
          FROM 1 FOR 6
        ),
        52, 1
      ),
      53, 1
    ),
    'hex'
  )::uuid;
$$;

COMMENT ON FUNCTION empi.uuid_generate_v7() IS
  'UUID v7 ordenable por tiempo (fallback PG14-17). PG18+ usa uuidv7() nativo.';

-- -----------------------------------------------------------------------------
-- Roles de aplicación (opcional pero recomendado para reforzar append-only §2.1)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'empi_app') THEN
    CREATE ROLE empi_app NOLOGIN;      -- servicio (INSERT en eventos, SELECT en todo)
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'empi_projector') THEN
    CREATE ROLE empi_projector NOLOGIN; -- proyector CQRS (escribe proyecciones §3)
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'empi_readonly') THEN
    CREATE ROLE empi_readonly NOLOGIN; -- consultas 360°/reportes (solo SELECT)
  END IF;
END $$;

GRANT USAGE ON SCHEMA empi TO empi_app, empi_projector, empi_readonly;
