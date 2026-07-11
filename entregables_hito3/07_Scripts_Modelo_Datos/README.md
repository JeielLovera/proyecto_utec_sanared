# Scripts de Base de Datos y Schemas de Eventos — EMPI Alt. 3 Mejorada

> Materializa en **artefactos ejecutables** el modelo descrito en
> [`../07_Alternativa3_Mejorada_Modelo_Datos.md`](../07_Alternativa3_Mejorada_Modelo_Datos.md).
> No inventa nada nuevo: traduce a DDL/JSON Schema/Avro/mappings los **cinco planos**
> (escritura, lectura, índice, referencia y analítico) y el **contrato de eventos** del bus.

## Correspondencia con el documento

| Plano (doc §) | Motor (producción) | Motor (demo/lab) | Artefacto en esta carpeta |
|---|---|---|---|
| **1 · Escritura** (Event Store) — §2 | AWS RDS PostgreSQL (append-only) | Postgres contenedor | [`sql/02_event_store.sql`](sql/02_event_store.sql) |
| **2 · Lectura** (proyecciones CQRS) — §3 | AWS RDS PostgreSQL | Postgres contenedor | [`sql/03_projections.sql`](sql/03_projections.sql) |
| **3 · Índice / caché** — §4 | OpenSearch + ElastiCache Redis | `pg_trgm` + Redis | [`opensearch/`](opensearch/), [`sql/04_indexes.sql`](sql/04_indexes.sql), [Redis §4.2](#claves-de-redis-42) |
| **4 · Referencia** (catálogos) — §5 | RDS + SSM Parameter Store | RDS + `.env`/tfvars | [`sql/01_catalogs.sql`](sql/01_catalogs.sql) |
| **5 · Analítico** (Vista 360°) — §7 | BigQuery (GCP) | DuckDB / BigQuery sandbox | [`bigquery/patient_360.sql`](bigquery/patient_360.sql) |
| **Contrato de eventos** (bus) — §2.2/§6 | Kafka/Confluent | Redpanda | [`schemas/`](schemas/) |

## Estructura

```
07_Scripts_Modelo_Datos/
├── README.md                      ← este archivo
├── sql/                           ← PostgreSQL (planos 1, 2, 4 + índices demo)
│   ├── 00_extensions.sql          ← extensiones + uuid_generate_v7() (fallback)
│   ├── 01_catalogs.sql            ← plano 4: source_system, event_type, ... (§5)
│   ├── 02_event_store.sql         ← plano 1: patient_events append-only (§2)
│   ├── 03_projections.sql         ← plano 2: golden_record, crosswalk, ... (§3)
│   ├── 04_indexes.sql             ← blocking demo (pg_trgm/metaphone) + lookups (§4/§11)
│   ├── 05_views.sql               ← audit_trail + golden_record_view compat MVP (§3.7)
│   └── 99_seed_demo.sql           ← datos 100% sintéticos (es_PE) para la demo (§10)
├── schemas/                       ← contrato de eventos (JSON Schema + Avro)
│   ├── README.md
│   ├── json-schema/               ← 1 payload por evento del catálogo (§2.2)
│   ├── bus/                       ← envelope cross-cloud identity.patient.* (§6)
│   └── examples/                  ← instancias de ejemplo (validables)
├── opensearch/                    ← mapping del índice de blocking (§4.1)
│   └── golden-record-idx.mapping.json
└── bigquery/                      ← DDL de la vista 360° desnormalizada (§7)
    └── patient_360.sql
```

## Cómo ejecutar (perfil demo)

Requiere PostgreSQL 14+ (probado hasta 16; PG18 trae `uuidv7()` nativo).

```bash
# 1. Levantar Postgres (ejemplo)
docker run -d --name empi-pg -e POSTGRES_PASSWORD=empi -p 5432:5432 postgres:16

# 2. Aplicar el esquema en orden
export PGPASSWORD=empi
for f in sql/00_extensions.sql sql/01_catalogs.sql sql/02_event_store.sql \
         sql/03_projections.sql sql/04_indexes.sql sql/05_views.sql sql/99_seed_demo.sql; do
  psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f "$f"
done
```

En PowerShell:

```powershell
$env:PGPASSWORD = "empi"
Get-ChildItem sql\*.sql | Sort-Object Name | ForEach-Object {
  psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f $_.FullName
}
```

## Validar los schemas de eventos

```bash
# con ajv-cli (npm i -g ajv-cli ajv-formats)
ajv validate -c ajv-formats \
  -s schemas/json-schema/PatientRegistered.schema.json \
  -d schemas/examples/PatientRegistered.example.json

# registrar en Confluent Schema Registry (Avro, plano bus §6)
# curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
#   --data @schemas/bus/identity-patient-event.avsc \
#   http://localhost:8081/subjects/identity.patient-value/versions
```

## Claves de Redis (§4.2)

El caché **no es fuente de verdad** (se reconstruye desde las proyecciones). Claves reutilizadas del Hito 2:

| Clave | Valor | TTL | Uso |
|---|---|---|---|
| `empi:dni:{sha256(dni)}` | `EMPI-ID` | 5 min (24 h offline) | Paso 1 — lookup exacto (~80% admisiones) |
| `empi:id:{source}:{value}` | `EMPI-ID` | 5 min | Lookup por identificador local (HIST/PID) |
| `empi:match:{token_biografico}` | `{score, candidatos[]}` | 30 s | Anti-recálculo de scoring concurrente |

> El DNI se **hashea** (SHA-256) como clave: nunca se guarda en claro en Redis (minimización, §10).

## Garantías clave que refuerzan estos scripts

- **Append-only real en la BD** (no solo en la app): `REVOKE UPDATE, DELETE` + trigger `BEFORE UPDATE/DELETE` sobre `patient_events` (§2.1, ADR-A3M-007).
- **Duplicado imposible por diseño**: índice único parcial `UNIQUE(source_system, identifier_type, identifier_value) WHERE status='ACTIVE'` sobre el crosswalk (§3.2, CA-01.2).
- **Concurrencia optimista**: `UNIQUE(empi_id, version)` en el Event Store (§2.1, escenario E2).
- **Dos estados separados**: `record_status` (vida/merge/deceso) + `verification_status` (completitud) (§3.1).
- **Auditoría que no puede desincronizarse**: `audit_trail` es una **vista** derivada del Event Store, no una tabla paralela (§3.7).

---
*Complementa `07_Alternativa3_Mejorada_Modelo_Datos.md` · Hito 3 · Clínica SanaRed Integrada*
