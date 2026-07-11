# Matriz Comparativa de Decisiones Arquitectónicas
## Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada

> Cada fila es una misma dimensión de decisión resuelta de forma distinta en cada alternativa final. Útil para una diapositiva única que cuente "por qué la Alternativa 3 mejora a la 1 y a la 2", en vez de repetir 30 ADRs.

---

## Matriz por dimensión de decisión

| Dimensión | Alt. 1 — Centralizada (AWS) | Alt. 2 — Federada DDD (Azure) | Alt. 3 — DDD Consolidado (Dual-Cloud) ✅ |
|---|---|---|---|
| **Cloud primario** | AWS (ADR-A1-001) | Azure (ADR-A2-001) | Dual: AWS en el perímetro externo + Azure en el motor de dominio (ADR-A3-003) |
| **Persistencia principal** | Aurora PostgreSQL Multi-AZ, tabla relacional mutable (ADR-A1-002) | Cosmos DB, Event Store con Change Feed (ADR-A2-002) | Cosmos DB, Event Store completo — mismo modelo que la Alt. 2, sin concesiones (ADR-A3-001) |
| **Perímetro / Gateway** | AWS API Gateway único, JWT (ADR-A1-003) | Azure APIM único, mTLS + OAuth2 (ADR-A2-003) | Gateway dual: AWS API GW (WAF, externo) + Azure APIM (mTLS, interno) — toma lo mejor de ambas (ADR-A3-003) |
| **Cache de latencia en admisión** | ElastiCache Redis, TTL 5 min (ADR-A1-004) | ❌ Sin cache — el matching en tiempo real siempre consulta Elasticsearch (~200 ms) | ElastiCache Redis con write-through, incorporado de la Alt. 1 (ADR-A3-002) |
| **Bus de integración / eventos** | EventBridge + SQS (ADR-A1-005) | Azure Service Bus con topics semánticos (ADR-A2-007) | Cosmos Change Feed → Service Bus → SQS DLQ por sistema (ADR-A3-001, sección 2.7) |
| **Batch de deduplicación** | AWS Step Functions, secuencial (ADR-A1-006) | Azure Databricks, paralelo distribuido, sin orquestador de checkpointing (ADR-A2-005) | Step Functions orquesta (checkpointing) + Databricks computa (paralelismo) — combina ambas (ADR-A3-004) |
| **RBAC / Autenticación** | JWT + SSO federado (ADR-A1-007) | mTLS (interno) + OAuth2 (externo), sin MFA explícito | JWT + SSO federado + MFA obligatorio para escritura (ADR-A3-007) |
| **Modelo de auditoría** | Log secundario en CloudWatch, escrito después de la transacción (ADR-A1-008) | Nativo: el Event Store ES el audit log (ADR-A2-006) | Nativo + `correlation_id` end-to-end, trazando el request HTTP original (ADR-A3-008) |
| **Reversión de una fusión incorrecta** | UPDATE sobre el registro + log de reversión | Evento `MergeReverted` append-only, implícito del Event Sourcing | Evento `MergeReverted` + `RevertMerge` como Command explícito de primera clase |
| **Interoperabilidad HL7 v2 (Fase 1)** | Lambda transformadora FHIR→HL7v2 (ADR-A1-009) | Adaptador suscrito al Service Bus (ADR-A2-009) | Lambda transformadora con cola dedicada `queue-hce` (ADR-A3-005) |
| **Retención de datos / Ley 29733** | Cifrado + S3 Glacier a los 12 meses, 10 años (ADR-A1-010) | Cifrado AES-256 + Azure Blob Cool Tier, 10 años (ADR-A2-010) | Cubierto dentro del Event Store (ADR-A3-001/008); prioriza en su lugar Versionado de API (ADR-A3-009) y Modo degradado offline (ADR-A3-010) |
| **Resiliencia ante caída de sede** | Modo cache offline mencionado como consecuencia (RNF-02.3), sin ADR propio | No abordado explícitamente | Modo cache-offline automático con TTL 24h, motivado por incidente real de feb-2024 (ADR-A3-010) |
| **Complejidad de implementación** | Media | Alta (DDD + CQRS + Event Sourcing son avanzados para el equipo) | Alta — justificada por los beneficios combinados a largo plazo |
| **Tiempo estimado Fase 1** | 3–4 meses | 5–6 meses | 4–5 meses |
| **Escalabilidad a largo plazo** | Buena (con sharding manual) | Excelente (proyecciones escalan independientemente) | Excelente desde Fase 1 |

---

## Lectura rápida para la presentación

- **Alt. 1** es la más simple de implementar y la de menor curva de aprendizaje, pero concentra escritura y lectura en una sola base de datos y su auditoría depende de un log secundario.
- **Alt. 2** resuelve la trazabilidad y la escalabilidad de lectura con Event Sourcing + CQRS, pero sacrifica la latencia garantizada (sin cache) y el blindaje perimetral específico para tráfico externo (WAF).
- **Alt. 3** parte del núcleo de dominio de la Alt. 2 (sin concesiones) e incorpora las tres capacidades operativas que la Alt. 1 resuelve mejor — cache, batch orquestado con checkpointing y perímetro con WAF — quedando así como la evolución de ambas, no como una alternativa aislada.

---

*Documento de apoyo para presentación — Hito 2 | Iniciativa EMPI | Clínica SanaRed Integrada*
