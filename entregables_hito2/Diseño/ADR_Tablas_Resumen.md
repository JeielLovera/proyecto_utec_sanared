# Tablas Resumen de ADRs — Alternativas Finales
## Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada

> Cada tabla condensa los 10 ADRs de una alternativa en una sola vista: la decisión tomada, por qué se tomó, y qué opciones se descartaron. El detalle completo (contexto, consecuencias) queda en el documento `Alternativa_X_C4_ADR.md` correspondiente.

---

## Alternativa 1 — EMPI Centralizado (AWS)

| ID | Decisión | Por qué | Opción(es) rechazada(s) |
|---|---|---|---|
| **ADR-A1-001** | AWS como cloud único para el EMPI Core, Master DB, cache, ESB y batch | Portal y App Móvil ya operan en AWS; reduce la complejidad de multi-cloud | Multi-cloud desde el día 1; Azure como cloud único |
| **ADR-A1-002** | Aurora PostgreSQL Multi-AZ como Master DB del Golden Record | Único punto de verdad transaccional con disponibilidad 99.9% y failover automático | DynamoDB; RDS PostgreSQL Single-AZ |
| **ADR-A1-003** | AWS API Gateway como único punto de entrada con JWT/OAuth2 | Todos los canales deben pasar por un perímetro único con rate limiting | Autenticación propia por canal; Service Mesh interno |
| **ADR-A1-004** | ElastiCache Redis como cache de lookup, TTL 5 min | El 80% de las admisiones son pacientes conocidos; evita contención en Aurora | — (sin opciones formales evaluadas) |
| **ADR-A1-005** | EventBridge + SQS como ESB de propagación de cambios | La sincronización síncrona punto a punto causó 11h de caída en el AS IS | REST síncrono punto a punto; Apache Kafka autogestionado |
| **ADR-A1-006** | AWS Step Functions orquesta el batch nocturno de deduplicación | Procesar 126,000 duplicados en la ventana 00:00–05:00 con capacidad de retomar sin reiniciar | — |
| **ADR-A1-007** | RBAC con JWT claims y SSO federado (IAM INI-03) | Cuentas compartidas y permisos heredados por sede eran un riesgo crítico | — |
| **ADR-A1-008** | CloudWatch (12 meses) + S3 Glacier (10 años) como Audit Log Store | Auditoría consultable en menos de 10s y retención de 10 años a costo razonable | — |
| **ADR-A1-009** | Lambda transformadora HL7v2 ↔ FHIR R4 | El HCE Oracle consume HL7 v2; migrarlo a FHIR R4 en Fase 1 retrasaría el valor | — |
| **ADR-A1-010** | Cifrado en Aurora + archivado a S3 Glacier a los 12 meses | Datos personales sensibles sujetos a la Ley 29733, retención de 10 años | — |

---

## Alternativa 2 — EMPI Federado DDD (Azure)

| ID | Decisión | Por qué | Opción(es) rechazada(s) |
|---|---|---|---|
| **ADR-A2-001** | Azure como cloud primario del motor de dominio y proyecciones | LIS y Portal de Pagos ya operan en Azure; Cosmos DB y Databricks son maduros | AWS como cloud primario; GCP como cloud primario |
| **ADR-A2-002** | Azure Cosmos DB como Event Store con Change Feed nativo | Necesita append-only, Change Feed sin polling y retención de 10 años | Aurora PostgreSQL append-only; EventStoreDB |
| **ADR-A2-003** | Azure APIM con mTLS (interno) + OAuth2 (externo) como gateway único | Los sistemas internos necesitan autenticación de máquina, no solo de usuario | AWS API Gateway; Azure APIM solo con OAuth2 |
| **ADR-A2-004** | CQRS con 4 proyecciones especializadas (Golden Record, Duplicates, Vista 360, Audit) | 4 patrones de acceso radicalmente distintos no caben en un solo modelo de datos | — |
| **ADR-A2-005** | Azure Databricks para el batch paralelo de deduplicación | Procesar 126,000 duplicados a más de 50,000 reg/hora en ventana nocturna | Azure Data Factory secuencial; AWS Step Functions + Lambda |
| **ADR-A2-006** | Event Sourcing completo, sin tabla de estado mutable | Necesita trazabilidad nativa y reversión sin UPDATE ni DELETE | — |
| **ADR-A2-007** | Azure Service Bus con topics semánticos por dominio | La sincronización síncrona punto a punto causó 11h de caída en el AS IS | REST síncrono punto a punto; AWS SQS |
| **ADR-A2-008** | PatientAggregate como único validador de las invariantes de negocio | Múltiples canales podrían violar reglas de negocio si cada uno valida por su cuenta | — |
| **ADR-A2-009** | Adaptador HL7v2 suscrito al Service Bus para el HCE Oracle | Migrar el HCE a FHIR R4 en Fase 1 retrasaría el valor 6-12 meses | — |
| **ADR-A2-010** | Cifrado AES-256 + archivado a Azure Blob Cool Tier a los 12 meses | Datos personales sensibles sujetos a la Ley 29733, retención de 10 años | — |

---

## Alternativa 3 — EMPI DDD Consolidado (Dual-Cloud)

| ID | Decisión | Por qué | Opción(es) rechazada(s) |
|---|---|---|---|
| **ADR-A3-001** | Cosmos DB como Event Store completo, partition key `empiId` | Necesita append-only, Change Feed sin polling y retención de 10 años | Aurora PostgreSQL (suficiente para un híbrido, no para Event Sourcing completo); EventStoreDB |
| **ADR-A3-002** | ElastiCache Redis con write-through, TTL 5 min (24h en modo offline) | Sin cache, incluso la búsqueda exacta por DNI tarda 100-300 ms | — |
| **ADR-A3-003** | Gateway dual: AWS API GW (externo, WAF) + Azure APIM (interno, mTLS) | El tráfico externo necesita WAF/rate limiting; el interno necesita autenticación de máquina | Solo AWS API GW; solo Azure APIM |
| **ADR-A3-004** | Step Functions orquesta el workflow, Databricks ejecuta el cómputo paralelo | Ninguna herramienta sola cubre checkpointing + procesamiento paralelo masivo | — |
| **ADR-A3-005** | Lambda transformadora HL7v2, suscrita a cola dedicada `queue-hce` | El HCE Oracle consume HL7 v2 y no debe cambiar en Fase 1 | — |
| **ADR-A3-006** | CQRS completo con 4 proyecciones (Cosmos DB, Elasticsearch, Synapse, Monitor) | 4 patrones de acceso radicalmente distintos no caben en un solo modelo de datos | — |
| **ADR-A3-007** | RBAC con JWT + SSO federado + MFA obligatorio para escritura | Necesita saber rol, sede y sistema de origen antes de cada operación | — |
| **ADR-A3-008** | Event Store = audit log primario, con `correlation_id` end-to-end | La auditoría requiere correlacionar logs de múltiples sistemas sin fuente única | — |
| **ADR-A3-009** | Versionado de API en URL, con soporte mínimo de 6 meses | Necesita evolucionar la API sin romper a los sistemas consumidores | — |
| **ADR-A3-010** | Modo cache-offline automático (TTL 24h) ante pérdida de conectividad de sede | Incidente de feb-2024: pérdida de conectividad generó 1,400 admisiones en contingencia | — |

---

*Documento de apoyo para presentación — Hito 2 | Iniciativa EMPI | Clínica SanaRed Integrada*
