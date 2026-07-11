# Servicio EMPI — Alternativa 3 Mejorada (capa 2)

Servicio **mínimo y directo** que ejecuta el dominio del EMPI: comando → matching →
evento(s) append-only → proyección CQRS. Es la app que despliega ECS (Fase 1) y la que
corre el **golden path**. Encaja directo con `entregables_hito3/07_Scripts_Modelo_Datos/`
(esquema `sql/` + contrato `schemas/`).

## Qué implementa

| Pieza | Archivo | Rol |
|---|---|---|
| API HTTP | `app/main.py` | `POST /patients`, `GET /patients/{id}`, `GET /health` (ECS/ALB) |
| Comando + orquestación | `app/service.py` | RegisterPatient → decisión → eventos + proyección **inline** |
| Matcher | `app/matcher.py` | Paso 1 (DNI exacto), Paso 2 (blocking pg_trgm), scoring, umbrales |
| Event Store | `app/service.py` (`_append_event`) | `patient_events` append-only, versión por agregado |
| Bus | `app/bus.py` | envelope `identity.patient.*` (NoOp/log; Kafka en Fase 2/3) |
| Config | `app/config.py` | env `EMPI_*` (en AWS inyectado desde SSM/Secrets) |

**Decisiones de registro** (fieles a doc §2.2, §9):

| Situación | Decisión | Evento(s) |
|---|---|---|
| DNI ya existe (Paso 1) | `LINKED` | `IdentifierLinked` (enriquece crosswalk) |
| Sin candidato / score < 0.85 | `REGISTERED` | `PatientRegistered` (Flujo A) |
| Score ≥ 0.95 (B2) | `MERGED` | `PatientRegistered` + `PatientMerged` |
| Score 0.85–0.95 (B3) | `REVIEW` | `PatientRegistered` (EN_REVISION) + `PatientMatchPending` |

> **Simplificación consciente:** la proyección es **síncrona** (inline tras el append, misma
> transacción). En producción el proyector es un consumidor separado, pero el **contrato de
> datos y los eventos son idénticos** — no cambia el modelo, solo el acoplamiento temporal.

## Correr en local

```bash
# 1) Postgres con el esquema aplicado (usa los sql/ canónicos)
docker run -d --name empi-pg -e POSTGRES_PASSWORD=empi -p 5432:5432 postgres:16
for f in 00_extensions 01_catalogs 02_event_store 03_projections 04_indexes 05_views; do
  docker exec -i empi-pg psql -U postgres -d postgres -f - \
    < ../../entregables_hito3/07_Scripts_Modelo_Datos/sql/${f}.sql
done

# 2) App
python -m venv .venv && ./.venv/Scripts/pip install -r requirements.txt
export EMPI_DATABASE_URL="postgresql://postgres:empi@localhost:5432/postgres"
./.venv/Scripts/python -m uvicorn app.main:app --port 8000

# 3) Probar
curl localhost:8000/health
curl -X POST localhost:8000/patients -H 'content-type: application/json' \
  -d '{"dni":"45678999","given_name":"Rosa","family_name":"Mendoza Cruz","source_system":"PORTAL"}'
```

## Contenedor (para ECS)

```bash
# Construir DESDE LA RAÍZ del repo (incluye los sql/ canónicos)
docker build -f services/empi-service/Dockerfile -t empi-service .
docker run -p 8000:8000 \
  -e EMPI_DATABASE_URL=postgresql://... -e EMPI_MIGRATE=true -e EMPI_SEED=true empi-service
```

`EMPI_MIGRATE=true` aplica el esquema al arranque (desde `/app/sql`, útil en la VPC);
`EMPI_SEED=true` carga datos sintéticos.

## Variables de entorno

| Var | Default | Uso |
|---|---|---|
| `EMPI_DATABASE_URL` | `postgresql://postgres:empi@localhost:5432/postgres` | RDS |
| `EMPI_REDIS_URL` | — | caché (§4.2, opcional) |
| `EMPI_BUS_BACKEND` | `noop` | `kafka` en Fase 2/3 |
| `EMPI_THRESHOLD_AUTO` / `EMPI_THRESHOLD_REVIEW` | `0.95` / `0.85` | umbrales (SSM en prod) |
| `EMPI_MODEL_VERSION` | `fs-2026.1` | versión del modelo |

## Estado

Verificado end-to-end contra Postgres 16 (Docker): `pytest` (Flujo A + B1) y API HTTP
(REGISTERED / LINKED / MERGED / REVIEW), con proyecciones, `merge_link` y `audit_trail`
correctos. Pendiente: publicador Kafka real (Fase 2) y caché Redis (opcional).
