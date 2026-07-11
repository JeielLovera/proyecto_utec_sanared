#!/usr/bin/env bash
set -euo pipefail

# Migraciones opcionales (perfil demo / arranque en VPC). Aplica el esquema canónico
# desde 07_Scripts_Modelo_Datos/sql/ (copiado a /app/sql en la imagen).
# DSN para psql: URL completa si se dio, o compuesta de las partes (ECS/SSM/Secrets).
DB_URL="${EMPI_DATABASE_URL:-}"
if [ -z "${DB_URL}" ] && [ -n "${EMPI_DB_HOST:-}" ]; then
  DB_URL="postgresql://${EMPI_DB_USER}:${EMPI_DB_PASSWORD}@${EMPI_DB_HOST}:${EMPI_DB_PORT:-5432}/${EMPI_DB_NAME:-empi}"
fi

if [ "${EMPI_MIGRATE:-false}" = "true" ]; then
  for f in 00_extensions 01_catalogs 02_event_store 03_projections 04_indexes 05_views; do
    echo "migrate: ${f}"
    psql "${DB_URL}" -v ON_ERROR_STOP=1 -f "/app/sql/${f}.sql"
  done
  if [ "${EMPI_SEED:-false}" = "true" ]; then
    echo "seed: 99_seed_demo (idempotente/ignorable)"
    psql "${DB_URL}" -f "/app/sql/99_seed_demo.sql" || echo "seed omitido (quizá ya sembrado)"
  fi
fi

exec uvicorn app.main:app --host 0.0.0.0 --port 8000
