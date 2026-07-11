# Schemas de Eventos — EMPI Alt. 3 Mejorada

Contrato de datos del **Event Store** (§2) y del **bus cross-cloud** (§6) del
[modelo de datos](../../07_Alternativa3_Mejorada_Modelo_Datos.md).

## Dos niveles de contrato

1. **`json-schema/`** — validación del `payload` de cada evento **tal como se persiste**
   en `patient_events` (§2.2). Un archivo por tipo de evento del catálogo. Se usa para
   validar en el borde de escritura (antes de hacer `INSERT`) y en tests.
   - [`event-envelope.schema.json`](json-schema/event-envelope.schema.json) — el "sobre" completo (§2.1): metadatos + `payload` polimórfico según `event_type`.
   - `PatientRegistered`, `IdentifierLinked`, `ContactUpdated`, `PatientMatchPending`, `PatientMerged`, `MergeReverted`, `PatientDeactivated`, `PatientAccessed`.

2. **`bus/`** — el **envelope del mensaje** que viaja cross-cloud por Kafka/Confluent
   (§6). Es un **subconjunto** del evento (nunca el registro completo → minimización §10).
   Azure (adaptadores HL7) y GCP (Healthcare API, BigQuery) consumen de aquí.
   - [`identity.patient.envelope.schema.json`](bus/identity.patient.envelope.schema.json) — JSON Schema del envelope de los topics `identity.patient.*`.
   - [`identity-patient-event.avsc`](bus/identity-patient-event.avsc) — el mismo contrato en **Avro** para el Schema Registry de Confluent.

## Catálogo de eventos → topics (§2.2)

| Evento (payload) | Topic bus | Consumidores clave (§6) |
|---|---|---|
| `PatientRegistered`   | `identity.patient.created`      | Azure `ADT^A28`, BigQuery |
| `IdentifierLinked`    | `identity.patient.updated`      | Azure `ADT^A31`, BigQuery |
| `ContactUpdated`      | `identity.patient.updated`      | Azure `ADT^A31` |
| `PatientMatchPending` | *(interno — no cruza)*          | — |
| `PatientMerged`       | `identity.patient.merged`       | Azure `ADT^A40`+`MRG`, GCP re-tag DICOM, ERP, BigQuery |
| `MergeReverted`       | `identity.patient.merged` (revert=true) | Azure, GCP |
| `PatientDeactivated`  | `identity.patient.deactivated`  | Azure |
| `PatientAccessed`     | *(interno)*                     | — |

## Convenciones

- **`event_version`** versiona el *esquema del payload* (evolución de contrato, §2.1).
  Cambios compatibles suben `event_version`; el consumidor tolera campos desconocidos.
- **`payload` FHIR-compatible**: los `identifiers[].system` usan los URI canónicos del
  catálogo `identifier_type` (§8): `urn:pe:reniec:dni`, `urn:sanared:hce`, etc.
- **`empi_id`** formato `EMPI-YYYYMMDD-XXXXXXXX` (`^EMPI-[0-9]{8}-[0-9A-F]{8}$`).
- **IDs**: `event_id`/`correlation_id`/`causation_id` son UUID (v7 para `event_id`).

## Validar

```bash
npm i -g ajv-cli ajv-formats
ajv validate -c ajv-formats \
  -s json-schema/PatientMerged.schema.json \
  -d examples/PatientMerged.example.json
```
