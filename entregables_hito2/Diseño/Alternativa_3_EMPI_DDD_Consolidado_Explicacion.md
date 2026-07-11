# Explicación Detallada — Alternativa TO BE 3
## EMPI DDD Consolidado: Event Sourcing Completo + Perímetro AWS + Infraestructura de Producción Dual-Cloud
### Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada

---

## 1. Punto de partida y decisión de diseño

La **Alternativa 2** es arquitectónicamente correcta en su núcleo: DDD + CQRS + Event Sourcing resuelven de raíz los problemas de trazabilidad, reversibilidad y escalabilidad de lectura. Sin embargo, tiene dos vacíos operativos que la Alt. 1 resuelve mejor:

1. **No tiene capa de caché de alta velocidad.** En Alt. 2, el matching en tiempo real empieza con una consulta Elasticsearch (~200 ms). En admisión de urgencias (780 pacientes/día), el 80% son pacientes conocidos que podrían resolverse en < 50 ms con un cache Redis antes de tocar cualquier proyección.

2. **El batch usa solo Databricks** (Alt. 2) o solo Step Functions (Alt. 1). Ninguna de las dos aprovecha lo mejor de ambas: Databricks para el procesamiento paralelo masivo del corpus inicial, Step Functions para la orquestación con checkpointing y retry que garantiza que un fallo a las 3 AM no obligue a reiniciar desde cero.

3. **El perímetro de seguridad externo** en Alt. 2 (solo Azure APIM con mTLS) es correcto para sistemas internos pero no tiene el WAF ni el rate limiting granular por canal que AWS API Gateway ofrece nativamente para los canales digitales externos (Portal, App Móvil, Teleconsulta).

La **Alternativa 3** parte del modelo de dominio puro de la Alt. 2 (sin concesiones: Cosmos DB como Event Store real, Elasticsearch como índice de matching, Synapse para la vista 360°, Azure Service Bus con topics semánticos) e incorpora estas tres capacidades de la Alt. 1 como capas adicionales — no como sustitutos.

### Principios de diseño

| Principio | Aplicación |
|---|---|
| **Event Sourcing completo** | Cosmos DB es el Event Store primario. El estado del Golden Record se deriva siempre de los eventos, nunca de un UPDATE directo. |
| **Cache como acelerador, no como fuente de verdad** | Redis absorbe el 80% de lookups en < 50 ms. Si el cache falla, el sistema degrada elegantemente a la proyección Cosmos DB — no hay pérdida de corrección. |
| **Dual-cloud sin dependencia cruzada crítica** | AWS es el perímetro de entrada (API Gateway, Step Functions, Lambda, ElastiCache). Azure es el motor de dominio (Cosmos DB, Databricks, Synapse, Service Bus, Elasticsearch). Los dos planos pueden degradarse independientemente. |
| **Orquestación híbrida del batch** | Step Functions maneja la lógica de workflow (retry, checkpoints, notificaciones de reporte). Databricks ejecuta el cómputo paralelo. Cada uno hace lo que mejor sabe hacer. |
| **Sin cambio en el HCE en Fase 1** | La Lambda transformadora HL7v2↔FHIR R4 es la única interfaz con el HCE Oracle. El equipo clínico no sufre interrupciones durante la adopción. |

---

## 2. Capas de la Arquitectura

### 2.1 Perímetro de Seguridad Unificado — Dual Gateway

La Alt. 2 usaba solo Azure APIM con mTLS. La Alt. 1 usaba solo AWS API Gateway con JWT. La Alt. 3 diferencia los dos tipos de tráfico:

**AWS API Gateway** — para canales externos y canal digital:
Portal Pacientes, App Móvil, Agenda SaaS, CRM Call Center, Teleconsulta y los módulos de admisión web de las sedes se conectan por HTTPS público. AWS API Gateway gestiona:
- WAF (Web Application Firewall) integrado: protege contra inyecciones, fuerza bruta y scrapers sobre el endpoint de búsqueda de pacientes.
- Rate limiting por canal y por operación: el Portal no puede enviar más de 100 req/s; el batch nocturno tiene su propio throttle separado del tráfico diurno.
- Circuit breaker: si el EMPI Core tiene latencia > 2s, el Gateway devuelve respuesta de fallback desde Redis en lugar de propagar el error a los canales de admisión.

**Azure APIM** — para sistemas internos y on-premises:
HCE Oracle (on-premises Lima), LIS Azure SQL y ERP Facturación se comunican con el EMPI a través de APIM con mTLS (autenticación bidireccional por certificado). Esto elimina la posibilidad de que un sistema comprometido en la red interna invoque el EMPI sin credenciales de máquina válidas, resolviendo el Riesgo #1 del Anexo (accesos heterogéneos sin correlación de identidad).

Ambos gateways validan contra el mismo **IAM Centralizado (INI-03)**: los tokens contienen claims de rol, sede y sistema de origen, lo que permite al PatientAggregate tomar decisiones de autorización de dominio (ej. solo el rol OPERADOR_DATOS puede enviar un MergeRecords Command).

### 2.2 Dominio de Identidad del Paciente — PatientAggregate completo

El núcleo del dominio sigue el modelo de la Alt. 2 sin simplificaciones. Se despliega en **AWS ECS Fargate multi-AZ** (sin gestión de servidores, escalamiento automático por métricas de CPU y latencia de cola).

**Seis Commands** cubren el 100% de las mutaciones de identidad:

| Command | Evento resultante | RF asociado |
|---|---|---|
| `RegisterPatient` | `PatientRegistered` | RF-01 |
| `MergeRecords` | `RecordsMerged` | RF-02, RF-03 |
| `UpdateContact` | `ContactUpdated` | RF-04 |
| `DeactivateRecord` | `RecordDeactivated` | RF-06 |
| `RevertMerge` | `MergeReverted` | RF-06 Scenario 2 |
| `ConfirmDistinct` | `NoMatchConfirmed` | RF-02 Scenario 3 |

El `RevertMerge` Command es un añadido explícito respecto a la Alt. 2 original. Genera un evento `MergeReverted` que el proyector usa para reactivar el registro secundario. Nunca se hace un UPDATE en el Event Store — el estado correcto se obtiene reproduciendo la secuencia de eventos incluyendo la reversión.

**Domain Rules configurables en caliente** (RNF-06.2): los umbrales de scoring (85%, 95%) y las reglas de precedencia por sistema fuente se almacenan en AWS Systems Manager Parameter Store. El PatientAggregate los lee en cada invocación con un cache TTL de 60 segundos. Cambiar un umbral no requiere redespliegue.

### 2.3 Event Store — Azure Cosmos DB con Change Feed

Cosmos DB se usa como Event Store por razones técnicas concretas, no por preferencia de cloud:

**Append-only por diseño**: la colección `patient_events` tiene una política de indexación que no permite `PATCH` ni `DELETE` a nivel de aplicación. Cada documento es inmutable una vez escrito. Los índices de Cosmos DB están optimizados para lectura secuencial por `empi_id` + `timestamp` (el patrón de acceso del proyector).

**Change Feed nativo**: cuando se escribe un nuevo evento en la colección, Cosmos DB emite automáticamente ese cambio al Change Feed, que es consumido por el proyector de proyecciones y por el Bus de Eventos. Esto elimina el polling y garantiza que ningún evento se pierda entre el Event Store y los consumidores — cada evento tiene exactamente una entrega al Change Feed (al menos una vez con deduplicación por `event_id`).

**Multi-región opcional en Fase 3**: si SanaRed expande a nuevas regiones, Cosmos DB soporta escritura multi-región sin cambios en la aplicación. Aurora PostgreSQL (usada en la Alt. 1) requeriría replicación manual para ese escenario.

Estructura del evento:
```json
{
  "event_id":    "uuid-v7",
  "empi_id":     "EMPI-20250115-XXXXXXXX",
  "event_type":  "PatientRegistered | RecordsMerged | ...",
  "payload":     { /* datos del evento en formato FHIR-compatible */ },
  "actor":       "user@sanaRed.pe | SYSTEM:BATCH_INI01",
  "source_sys":  "PORTAL_AWS | ADMISION_SEDE3 | HCE_ORACLE | ...",
  "timestamp":   "2025-01-15T08:32:11.423Z",
  "version":     1,
  "correlation_id": "uuid-del-request-original"
}
```

El `correlation_id` permite correlacionar el evento con el request HTTP original en los logs del API Gateway — capacidad de trazabilidad end-to-end que responde directamente al hallazgo del Anexo sobre la imposibilidad de correlacionar logs entre sistemas.

### 2.4 Capa de Caché — ElastiCache Redis (incorporado de Alt. 1)

Esta es la incorporación más impactante en términos de latencia operativa. La Alt. 2 no tenía cache; la Alt. 3 lo añade como capa entre el API Gateway y el dominio.

**Estrategia write-through**: en cada nuevo `PatientRegistered` exitoso, el PatientAggregate escribe en Redis antes de responder al canal. El cache nunca está frío para un paciente recién registrado.

**Tres tipos de clave**:
- `empi:dni:{sha256(dni)}` → EMPI-ID (TTL 5 min): para el 80% de las admisiones que ya conocen el DNI.
- `empi:id:{empiId}` → resumen del Golden Record (TTL 5 min): para consultas de médicos que ya tienen el EMPI-ID.
- `empi:match:{token_biográfico}` → score + candidatos (TTL 30 s): para evitar recalcular el scoring cuando el mismo conjunto de atributos llega desde múltiples canales en un intervalo corto (ej. Portal y Admisión enviando datos del mismo paciente simultáneamente).

**Modo degradado offline** (RNF-02.3): cuando una sede pierde conectividad, el Redis local extiende el TTL a 24 horas. Las admisiones de urgencias continúan con los últimos datos sincronizados. Al reconectar, las admisiones offline se procesan con matching prioritario contra el EMPI central. Los eventos generados durante la contingencia quedan en la DLQ del Service Bus hasta que la conectividad se restaura.

**Redis como fallback del circuit breaker**: el AWS API Gateway está configurado para que, si el EMPI Core responde con latencia > 2 s o devuelve error 5xx, el Gateway consulte Redis directamente para lookups de lectura. El canal recibe una respuesta aunque el servicio de escritura esté degradado.

### 2.5 Proyecciones CQRS — cuatro vistas especializadas

Las proyecciones se construyen asíncronamente desde el Change Feed de Cosmos DB. Un servicio proyector (ECS Fargate, desplegado independientemente del EMPI Core) consume el Change Feed y actualiza cada proyección según el tipo de evento.

**golden_record_view (Cosmos DB)**: proyección optimizada para lookup por EMPI-ID o DNI. Contiene solo los campos activos del Golden Record: datos biográficos, estado, fecha de última actualización, referencias a sistemas fuente y relaciones familiares. Latencia de actualización: < 1 segundo desde el evento. Sirve las consultas de admisión cuando hay cache miss en Redis.

**duplicate_candidates_index (Elasticsearch)**: índice fuzzy sobre nombre fonético (Soundex + Metaphone para variaciones del español: "Jhuan"/"Juan", "Ramos"/"Ramoz"), fecha de nacimiento (rango ±1 año para errores de transcripción), y número de celular (coincidencia parcial). El servicio de matching en tiempo real consulta este índice en el paso 2 del flujo (si hay miss en Redis). El batch nocturno también lo usa para identificar candidatos antes de ejecutar el scoring completo en Databricks.

**patient_360_longitudinal (Azure Synapse Analytics)**: la proyección más rica. Combina los eventos de identidad del EMPI con datos provenientes de los consumidores (HCE, LIS, PACS, Agenda) a través de pipelines de Azure Synapse. El médico consulta una vista única materializada, no un join en tiempo real sobre 6 sistemas distribuidos con latencias distintas. Esto resuelve el problema raíz del AS IS donde los médicos esperaban mientras el sistema intentaba correlacionar datos de fuentes lentas. Latencia de la vista: < 2 segundos desde que el médico la solicita.

**audit_trail_projection (Azure Monitor Logs)**: proyección de todos los eventos de dominio en formato de log estructurado consultable. Cada entrada tiene: EMPI-ID, actor, sistema de origen, tipo de acción, timestamp, correlation_id. Consultable en < 10 segundos por rango de fechas y EMPI-ID (RNF-03.4). La auditoría no es un efecto secundario de la aplicación — es una proyección derivada del Event Store que existe si y solo si el evento existe. Es imposible que ocurra una operación sobre un Golden Record sin que quede reflejada en el audit trail.

### 2.6 Matching Distribuido — Elasticsearch + Redis + Databricks/Step Functions

**Real-Time Matcher**: estrategia en tres pasos progresivos con early exit:
1. Consulta Redis: si hay hit exacto por DNI, responde en < 10 ms sin continuar.
2. Si hay miss, consulta Elasticsearch con búsqueda fuzzy por nombre fonético + fecha de nacimiento. Responde con candidatos en < 200 ms.
3. Sobre los candidatos de Elasticsearch, ejecuta el scoring probabilístico completo (todos los atributos biográficos ponderados). Respuesta total P95 < 500 ms.

**Batch Deduplication (INI-01)** — orquestación híbrida:
- **AWS Step Functions** maneja el workflow de alto nivel: inicio del batch, división en particiones por rango de fechas, espera de Databricks, actualización del checkpoint, generación del reporte, notificación al operador. Si el batch falla a las 3 AM, Step Functions retoma desde la última partición completada gracias al checkpointing — no se pierde el trabajo previo (diferencia clave respecto a Alt. 2 que usaba Databricks standalone).
- **Azure Databricks** ejecuta el cómputo paralelo: lee particiones del índice Elasticsearch de candidatos, aplica el scoring probabilístico con paralelismo distribuido sobre múltiples workers. La tasa resultante es significativamente mayor que los 50,000 registros/hora del umbral mínimo (RNF-01.3) — el corpus inicial de 126,000 duplicados puede resolverse en una sola ventana nocturna.

**Manual Review Queue (SQS FIFO)**: los casos con score 85%–94% se encolan con prioridad por score descendente (los más cercanos al umbral 95% se revisan primero, minimizando el riesgo clínico). La UI de revisión muestra el historial completo de eventos de cada registro desde el Event Store — el operador puede ver en qué sistema fue creado cada registro, cuándo y por quién, antes de tomar una decisión de fusión.

### 2.7 Bus de Eventos — Change Feed + Azure Service Bus + AWS SQS DLQ

El flujo de propagación tiene tres etapas bien separadas:

**Cosmos DB Change Feed → Azure Service Bus**: el Change Feed emite cada nuevo evento al Service Bus en < 500 ms post-commit. Los topics tienen nombres semánticos de dominio (`identity.patient.created`, `identity.patient.merged`, etc.) — no nombres técnicos. Cada consumidor suscribe solo a los topics que le son relevantes.

**Azure Service Bus → AWS SQS DLQ por sistema**: para los consumidores que están en la infraestructura AWS o en la nube privada (ERP), los mensajes del Service Bus se traducen a colas SQS dedicadas (`queue-hce`, `queue-lis`, `queue-erp`, etc.). Cada cola tiene su propia DLQ con retry backoff 30s → 60s → 120s (RNF-02.4). Si el HCE Oracle está temporalmente no disponible, los eventos quedan encolados sin pérdida.

**Lambda transformadora HL7v2↔FHIR R4**: suscrita a la `queue-hce`, convierte el evento `identity.patient.created` (en formato FHIR R4 Patient resource) al mensaje HL7 ADT^A28 que el HCE Oracle espera. El HCE no requiere ninguna modificación en Fase 1. En Fase 2, cuando el HCE migre a FHIR R4, la Lambda se elimina y la `queue-hce` entrega directamente FHIR — sin cambiar el Event Store ni el PatientAggregate.

---

## 3. Comparación de las tres alternativas finales

| Dimensión | Alt. 1 Centralizada | Alt. 2 Federada DDD | Alt. 3 DDD Consolidada ✅ |
|---|---|---|---|
| **Modelo de datos** | Aurora PostgreSQL (estado actual) | Cosmos DB (Event Store) | **Cosmos DB (Event Store completo)** |
| **Auditoría** | Log secundario CloudWatch | Nativa (Event Store = audit) | **Nativa + correlation_id end-to-end** |
| **Lectura** | Una BD (contención lect/escrit) | Proyecciones especializadas | **Proyecciones independientes por caso de uso** |
| **Cache de latencia** | ElastiCache Redis ✅ | ❌ Sin cache | **ElastiCache Redis ✅ + write-through** |
| **Perímetro externo** | AWS API GW ✅ | Azure APIM solamente | **AWS API GW (externo) + Azure APIM (interno) + mTLS** |
| **Perímetro interno mTLS** | ❌ | Azure APIM mTLS ✅ | **Azure APIM mTLS ✅** |
| **Matching batch** | Step Functions secuencial | Databricks paralelo | **Step Functions (orquesta) + Databricks (cómputo)** |
| **Checkpointing batch** | ✅ Step Functions nativo | ❌ Databricks sin orquestador | **✅ Step Functions + Databricks checkpoint combinado** |
| **Vista longitudinal 360°** | Joins en tiempo real sobre BDs | Azure Synapse ✅ | **Azure Synapse Analytics ✅ materializada** |
| **Reversión de fusión** | UPDATE + log separado | Append MergeReverted ✅ | **Append MergeReverted ✅ + RevertMerge Command explícito** |
| **HL7 v2 en Fase 1** | Lambda transform ✅ | Implícita en consumidor | **Lambda transform ✅ + queue-hce dedicada** |
| **HCE cambio Fase 1** | Ninguno ✅ | Ninguno ✅ | **Ninguno ✅** |
| **Observabilidad dual-cloud** | CloudWatch solo | Azure Monitor solo | **Grafana + CloudWatch + Azure Monitor unificados** |
| **Tiempo estimado Fase 1** | 3–4 meses | 5–6 meses | **4–5 meses** |
| **Complejidad de implementación** | Media | Alta | **Alta — justificada por beneficios a largo plazo** |
| **Escalabilidad** | Buena | Excelente | **Excelente desde Fase 1** |
| **Costo de infraestructura** | Medio | Alto | **Alto — inversión en plataforma correcta** |

---

## 4. Cómo resuelve los problemas del AS IS

| Problema AS IS | Solución en Alt. 3 |
|---|---|
| **Integrador HL7 SPOF** (11h caída, 18,600 resultados bloqueados) | Reemplazado por Cosmos Change Feed → Service Bus → SQS queue-hce → Lambda HL7v2. DLQ garantiza entrega. HCE no cambia en Fase 1. |
| **126,000 registros duplicados** | Databricks paralelo + Step Functions orquestado. Resolución estimada en 1–2 ventanas nocturnas (vs 3–5 de la Alt. 1). |
| **52 min tiempo espera admisión** | Redis hit en < 50 ms (80% casos). Matching en tiempo real P95 < 500 ms. Circuit breaker evita degradación en cascada. |
| **APIs sin caché ni circuit breaker** (12,000 pacientes afectados) | AWS API GW con WAF + rate limiting + circuit breaker a Redis como fallback. |
| **Sin RTO/RPO documentado** | Cosmos DB multi-región (RTO < 1h). ECS Fargate multi-AZ. Step Functions idempotente con checkpoints. |
| **Sin auditoría correlacionada entre sistemas** | Cosmos DB Event Store = fuente primaria de auditoría. `correlation_id` en cada evento traza desde el request HTTP hasta el sistema destino. |
| **Médicos afiliados con permisos excesivos** | Azure APIM mTLS para sistemas internos + IAM tokens con claims de sede y rol. PatientAggregate valida autorización por dominio antes de ejecutar cada Command. |
| **Vista 360° con joins en tiempo real** | Azure Synapse materializa la vista longitudinal. Médico recibe respuesta en < 2 s independientemente del número de sistemas fuente. |
| **Sincronización Agenda demorada (horas)** | Service Bus entrega `identity.patient.created` en < 30 s. Sin batch nocturno para sincronización de identidad. |
| **ERP: 13% expedientes observados** | ERP consume `identity.patient.merged` en tiempo real. Consolida facturación bajo EMPI-ID activo en < 30 s post-merge. |
| **PACS sin acceso inter-sede garantizado** | PACS vincula imágenes a EMPI-ID desde `identity.patient.created`. La vista 360° en Synapse consolida imágenes de todas las sedes bajo un único identificador. |

---

## 5. Roadmap de implementación por fases

### Fase 1 — Núcleo del EMPI y Perímetro (Q1 2025 | 4–5 meses)
**Objetivo:** EMPI operativo con Event Sourcing completo, perímetro de seguridad dual, y los tres canales de mayor volumen integrados.

1. Cosmos DB — colección `patient_events` con política append-only + Change Feed habilitado
2. PatientAggregate en ECS Fargate — Commands: `RegisterPatient`, `UpdateContact`
3. Proyección `golden_record_view` en Cosmos DB (proyector async)
4. Proyección `audit_trail_projection` en Azure Monitor
5. ElastiCache Redis — cache de lookup con write-through
6. AWS API Gateway — WAF + rate limiting + circuit breaker
7. Azure APIM — mTLS para HCE Oracle y LIS
8. IAM Centralizado (INI-03) — SSO federado + MFA para escritura
9. SQS queue-hce + Lambda HL7v2→FHIR R4 (reemplaza integrador SPOF)
10. Integraciones Fase 1: Portal AWS + Agenda SaaS + Admisión x4 sedes
11. RBAC completo (5 roles) + TLS 1.3 + AES-256 + PIA Ley 29733

**Hito Fase 1:** EMPI activo. Nuevos pacientes sin duplicados desde el día 1. Integrador HL7 SPOF eliminado.

### Fase 2 — Deduplicación y Matching (Q2 2025 | 2 meses adicionales)
**Objetivo:** Resolver corpus de 126,000 duplicados. Integraciones completas. Matching en tiempo real maduro.

1. Elasticsearch — índice `duplicate_candidates` + servicio Real-Time Matcher completo (3 pasos)
2. Commands: `MergeRecords`, `ConfirmDistinct`, `DeactivateRecord` + `RevertMerge`
3. Azure Databricks + AWS Step Functions — batch nocturno con checkpointing
4. SQS FIFO Manual Review Queue + UI de revisión manual
5. Integraciones completas: HCE Oracle (FHIR R4) + LIS Azure + ERP + CRM + PACS
6. Modo degradado offline (Redis TTL extendido + DLQ persistencia eventos)
7. RNF-02: disponibilidad 99.9% + RTO < 4h + RPO < 1h — drill DR programado

**Hito Fase 2:** Tasa de duplicados reducida ≥ 60% (objetivo: ≥ 80%). Todas las integraciones activas.

### Fase 3 — Golden Record 360 y Gobierno Maduro (Q3 2025)
**Objetivo:** Vista longitudinal completa. Escalamiento verificado. Gobierno de datos operativo.

1. Azure Synapse — pipeline `patient_360_longitudinal` con datos de HCE + LIS + PACS + Agenda
2. RF-07: Governance Engine completo — reporte semanal automático + alertas tasa duplicados
3. RNF-05: escalamiento automático ECS Fargate + Cosmos DB verificado en prueba de campaña corporativa
4. Grafana — dashboard unificado CloudWatch + Azure Monitor para equipo de operaciones
5. Evaluación de Cosmos DB multi-región (si SanaRed expande a nuevas ciudades)
6. Documentación OpenAPI 3.0 completa en portal de desarrolladores interno (RNF-06.3)

**Hito Fase 3:** Vista 360° para ≥ 90% de pacientes activos. Cero nuevos duplicados desde cualquier canal. INI-13 completado.

---

## 6. Ventajas diferenciales sobre Alt. 2

| Aspecto | Mejora sobre Alt. 2 |
|---|---|
| **Latencia garantizada en admisión** | Redis absorbe 80% de lookups en < 50 ms. Alt. 2 siempre consulta Elasticsearch (> 100 ms mínimo). |
| **Resiliencia del circuit breaker** | Si el EMPI Core degrada, AWS API GW devuelve respuesta desde Redis. Alt. 2 no tiene este fallback. |
| **Batch sin riesgo de pérdida de progreso** | Step Functions checkpointing garantiza que un fallo a las 3 AM retoma desde la última partición. Databricks standalone no tiene esto. |
| **Trazabilidad end-to-end** | `correlation_id` en cada evento correlaciona el request HTTP original con todos los sistemas destino. Alt. 2 no lo especifica. |
| **Perímetro dual completo** | AWS API GW para tráfico externo (WAF, rate limiting) + Azure APIM para tráfico interno (mTLS). Alt. 2 solo tenía Azure APIM. |
| **RevertMerge como Command explícito** | Alt. 2 mencionaba la reversión como característica del Event Sourcing pero no la modelaba como Command. Alt. 3 la hace ciudadana de primera clase del dominio. |

## 7. Limitaciones y riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| **Complejidad operacional dual-cloud** | El equipo debe operar Cosmos DB + Elasticsearch + Databricks + Service Bus (Azure) y API GW + ElastiCache + Step Functions + ECS (AWS) | Plan de capacitación obligatorio pre-Fase 1. Contratar un arquitecto de plataforma con experiencia en dual-cloud. Centro de excelencia EMPI desde el inicio. |
| **Consistencia eventual de proyecciones (< 1–5 s)** | Una consulta inmediatamente post-escritura puede ver datos previos en la proyección Cosmos DB | El PatientAggregate devuelve el evento confirmado en la respuesta inmediata. Los canales usan ese dato hasta que el proyector actualiza. Documentar el comportamiento esperado con los consumidores. |
| **Costo de infraestructura Fase 1** | Cosmos DB + Elasticsearch + ECS + ElastiCache tienen costo base significativo sin volumen | Usar Cosmos DB serverless en Fase 1 (pago por RU consumida, no por capacidad provisionada). Elastic Cloud starter tier. Escalar en Fase 2 cuando el volumen esté validado. |
| **IAM Centralizado (INI-03) como dependencia** | Si INI-03 no está listo en Fase 1, el RBAC completo no puede operar | JWT básico con claims de rol como fallback temporal. Migrar a SSO federado completo en Fase 2. |
| **Latencia on-premises → Cosmos DB** | El HCE Oracle (Lima on-prem) no consulta directamente Cosmos DB — lo hace a través de Azure APIM | El HCE consume eventos via SQS queue-hce (modo push). Para consultas activas del HCE al EMPI, Azure APIM con ExpressRoute privado garantiza baja latencia. |

---

*Documento generado para Hito 2 — Iniciativa EMPI | Clínica SanaRed Integrada*
