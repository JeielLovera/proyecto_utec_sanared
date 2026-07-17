# Documento Comparativo de Alternativas de Arquitectura EMPI
## Alternativa 1 (Hito 2) — *EMPI Centralizado en AWS* vs. Alternativa 3 Mejorada (Hito 3) — *EMPI Multicloud Concordante*
### Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada | Hito 4

---

## 0. Propósito y alcance del documento

Este documento compara las **dos alternativas de arquitectura EMPI** que el proyecto ha producido en distintos momentos:

- **Alternativa 1 (Hito 2):** *EMPI Centralizado con API Gateway y Bus de Integración (ESB)* — una solución **mono-nube (AWS)**, con un núcleo de identidad centralizado sobre base de datos relacional maestra.
- **Alternativa 3 Mejorada (Hito 3):** *EMPI Multicloud Concordante* — una solución **tri-nube (AWS + Azure + GCP)** que ubica cada componente en la nube que ya aloja su dominio de negocio afín, con Event Sourcing, matching escalable e imágenes vinculadas por EMPI-ID.

El análisis se organiza en tres bloques:
1. **Qué propone cada alternativa** (§1 y §2): descripción autocontenida de cada diseño.
2. **Comparación funcional** (§3): qué hace cada una desde la perspectiva del negocio y los requerimientos funcionales.
3. **Comparación técnica** (§4): cómo lo hace cada una en términos de tecnología, patrones, despliegue, escalabilidad y operación.

Cierra con una **matriz consolidada** (§5), un análisis de **madurez y riesgo** (§6) y una **conclusión con recomendación** (§7).

> **Nota de contexto:** ambas alternativas resuelven el mismo problema de negocio —los **126,000 duplicados** históricos, la fragmentación de identidad entre las sedes y los tres riesgos tecnológicos del Anexo (Seguridad, Integridad, Disponibilidad)— y cumplen el mismo conjunto de RF/RNF. Difieren en **cómo** distribuyen, implementan y evolucionan la solución.

---

## 1. Qué propone la Alternativa 1 (Hito 2) — EMPI Centralizado en AWS

### 1.1 Idea central

Un **EMPI completamente centralizado**: existe **un único punto de verdad** para la identidad del paciente, alojado íntegramente en **AWS**. Todos los canales de entrada (Portal, Admisión, Agenda, App, Call Center) convergen hacia un **API Gateway único** que autentica y enruta al núcleo del EMPI. Los cambios en el Golden Record se propagan de forma **asíncrona** a los sistemas clínicos mediante un **Bus de Integración (ESB)** basado en eventos.

La consigna de diseño es **simplicidad operativa y control**: una sola nube, un solo perímetro, un solo servicio de dominio desplegable.

### 1.2 Componentes principales

| Capa | Componente | Tecnología | Rol |
|---|---|---|---|
| **Perímetro** | API Gateway | AWS API Gateway | Único punto de entrada. Autenticación JWT/OAuth2, rate limiting, logging centralizado |
| **Identidad y acceso** | IAM Centralizado (INI-03) | OAuth2 / OIDC / JWT federado | Emite tokens válidos en todo el ecosistema; RBAC por claims |
| **Núcleo** | EMPI Core Service | AWS ECS Fargate (servicio único) | 4 módulos internos: Motor de Matching & Scoring, Golden Record Engine, Deduplication Service, Lifecycle Manager |
| **Persistencia maestra** | Master DB | Aurora PostgreSQL Multi-AZ | Golden Records **relacionales** + tabla de relaciones (fusiones, dependientes). Failover < 30 s |
| **Cache** | Cache Layer | ElastiCache Redis | Lookups por DNI/EMPI-ID, TTL 5 min, absorbe ~80% del tráfico de lectura |
| **Auditoría** | Audit Log Store | CloudWatch + S3 Glacier | 12 meses activos + histórico a 10 años |
| **Propagación** | Event Bus + Cola | AWS EventBridge + Amazon SQS | Publica `PATIENT_CREATED`, `PATIENT_MERGED`, `CONTACT_UPDATED`; retry backoff + DLQ |
| **Interoperabilidad** | Transformador HL7v2↔FHIR R4 | AWS Lambda (Adapter) | Convierte el recurso FHIR `Patient` a HL7 v2 ADT para el HCE Oracle |
| **Batch** | Scheduler Batch | AWS Step Functions | Deduplicación nocturna 00:00–05:00 (INI-01), con checkpointing |
| **Gobierno** | Dashboard Calidad + Alertas | INI-06a + CloudWatch Alarms | Métricas de RF-07; alerta si duplicados > 2% |

### 1.3 Modelo de datos

**Golden Record relacional clásico**: una tabla de Golden Records (EMPI-ID, estado, atributos biográficos cifrados, referencias a fuentes) y una tabla de relaciones. El ciclo de vida se modela con una **máquina de estados** (`INCOMPLETO → VERIFICADO → POSIBLE_DUPLICADO → INACTIVO_FUSIONADO / INACTIVO_FALLECIDO → Archivado`). **No usa Event Sourcing**: el estado se actualiza en sitio y el log de auditoría es una escritura secundaria.

### 1.4 Patrones aplicados

API Gateway · Master Data Management (MDM) · Cache-Aside · Event-Driven Architecture (Pub/Sub) · Adapter (HL7↔FHIR) · Retry con Backoff / DLQ · Orchestration (Saga centralizada, Step Functions) · Strangler Fig · Repository.

### 1.5 Fortalezas y límites propios (según su propio ADR)

- **Fortalezas:** control centralizado y auditable, latencia predecible (Redis), propagación desacoplada (ESB), transición gradual (Strangler + transformador HL7), operación sobre servicios AWS gestionados y maduros.
- **Límites reconocidos:** el EMPI Core es un **punto único de fallo** lógico; latencia de red On-Prem→AWS para el HCE; la migración inicial de 5 fuentes heterogéneas es compleja; dependencia del IAM Centralizado (INI-03). Además, **no aprovecha** las otras dos nubes de SanaRed (Azure, GCP) y **no aborda** la unificación de imágenes PACS inter-sede.

---

## 2. Qué propone la Alternativa 3 Mejorada (Hito 3) — EMPI Multicloud Concordante

### 2.1 Idea central

Un **EMPI distribuido por concordancia de dominio**: cada componente se despliega en **la nube que ya aloja la funcionalidad de negocio afín** de SanaRed. *La identidad del paciente vive donde vive el paciente; la integración clínica donde vive lo clínico; las imágenes donde viven las imágenes.* Añade un principio que la Alt. 1 no tiene: aprovechar el parque multinube existente **por afinidad, no por inercia**.

Introduce además dos ejes que la Alt. 1 no cubre:
- **Vinculación de imágenes PACS al EMPI-ID** (unificación inter-sede, imposible hoy).
- **Dos perfiles de entrega**: *Producción* (concordante, a escala) y *Demo/Lab* (IaC Terraform tri-cloud, funcional end-to-end con datos sintéticos).

### 2.2 Asignación por concordancia de dominio (el principio nuevo — ADR-A3M-001)

| Nube | Dominio AS-IS que ya aloja | Componentes EMPI asignados |
|---|---|---|
| **AWS** | Paciente / experiencia digital (Portal + RDS) | Núcleo de identidad, Event Store, Golden Record, matcher tiempo real + **índice OpenSearch**, cache; **perímetro de entrada** (público paciente + interno mTLS) |
| **Azure** | Clínico-diagnóstico + cobros (LIS Azure SQL + Portal de Pagos) | **Integración de salida** a legados: APIM mTLS, adaptadores HCE/LIS/ERP/Pagos |
| **GCP** | Imágenes + analítica + salud ocupacional (PACS réplica) | Cloud Healthcare API (FHIR+DICOM), Vista 360° y batch matching (BigQuery) |
| **On-premises** | Historia clínica (HCE Oracle + Admisión) | HCE sin cambios; Admisión consulta el EMPI **en AWS** por mTLS/Direct Connect |
| **Neutral (transversal)** | — | **Bus de eventos Kafka** (Confluent/Redpanda), anti-lock-in |

### 2.3 Componentes principales (perfil producción)

| Capa | Componente | Tecnología | Nube |
|---|---|---|---|
| **Perímetro público** | API Gateway + WAF (canal paciente) | AWS API Gateway | AWS |
| **Perímetro interno** | API GW privado / ALB + mTLS (admisión, agenda) | AWS ALB, Direct Connect/VPN | AWS |
| **Núcleo** | EMPI Core / PatientAggregate | FastAPI · ECS Fargate | AWS |
| **Índice matching RT** | Blocking fuzzy a escala | Amazon OpenSearch/Elasticsearch + jellyfish | AWS |
| **Cache** | Lookup de identidad | ElastiCache Redis | AWS |
| **Persistencia** | Event Store append-only + Golden Record view | Amazon RDS PostgreSQL (Event Sourcing relacional) | AWS |
| **Salida a legados** | APIM mTLS + adaptadores clínicos/financieros | Azure API Management + Azure Functions | Azure |
| **Imágenes** | FHIR Store + DICOM Store (PACS↔EMPI-ID) | GCP Cloud Healthcare API | GCP |
| **Analítica / Batch** | Vista 360° + batch dedup | BigQuery + Splink | GCP |
| **Bus** | Propagación cross-cloud | Kafka neutral (Confluent/Redpanda) | Transversal |

### 2.4 Modelo de datos

**Event Sourcing sobre PostgreSQL relacional** (ADR-A3M-007): una tabla `patient_events` **append-only** más proyecciones (`golden_record_view`). La auditoría es **nativa** (el log de eventos *es* la fuente de verdad, no una escritura secundaria). Conserva el patrón DDD + CQRS + Event Sourcing de la Alt. 3 original, pero con menor complejidad operativa que Cosmos DB Change Feed.

### 2.5 Perímetro por dirección de tráfico (ADR-A3M-003 — diferencial clave)

- **(a)** Canal público de paciente → **AWS API GW + WAF**.
- **(b)** Entrada de sistemas internos (Admisión on-prem, Agenda) → **AWS ALB con mTLS**, alcanzado por Direct Connect/VPN, **sin pasar por Azure** (evita salto cross-cloud en el *hot path*, cumple RNF-01).
- **(c)** Salida del EMPI hacia legados (HCE/LIS/ERP) → **Azure APIM mTLS**, por concordancia clínica.

### 2.6 Patrones aplicados

Concordancia de Dominio (co-locación por afinidad) · DDD + CQRS + Event Sourcing · Blocking Index (OpenSearch) · Probabilistic Record Linkage (Splink / Fellegi-Sunter, backend-swappable) · Perímetro por dirección · Bus neutral Kafka (anti-lock-in) · FHIR/DICOM nativos · IaC (Terraform) tri-cloud.

### 2.7 Fortalezas y límites propios

- **Fortalezas:** aprovecha las 3 nubes por afinidad real; matching escalable a millones de registros; imágenes inter-sede unificadas; auditoría nativa por eventos; anti-lock-in en la mensajería; **demostrable end-to-end** por IaC.
- **Límites reconocidos:** el bus cross-cloud añade latencia/egreso (mitigado: propagación asíncrona fuera del camino crítico); 3 nubes = 3 credenciales/regiones (mitigado por IaC y `terraform destroy`); mayor superficie operativa y curva de aprendizaje (DDD/CQRS/ES son avanzados para el equipo).

---

## 3. Comparación funcional

> Ambas alternativas cubren el **mismo conjunto de RF/RNF** del caso. La comparación funcional se centra en **cobertura, alcance y experiencia de uso**, no en si "hace o no hace" cada requisito.

### 3.1 Cobertura de requerimientos funcionales

| RF | Alternativa 1 (Centralizada AWS) | Alternativa 3 Mejorada (Multicloud Concordante) |
|---|---|---|
| **RF-01** Golden Record / EMPI-ID único | ✅ Golden Record Engine sobre Aurora; EMPI-ID canónico | ✅ PatientAggregate + Event Store; EMPI-ID canónico por eventos |
| **RF-02** Deduplicación batch (INI-01) | ✅ Step Functions + Lambdas, 00:00–05:00, ≥50k reg/h | ✅ Splink @ BigQuery (probabilístico Fellegi-Sunter), backend-swappable |
| **RF-03** Matching tiempo real (INI-13) | ✅ Matching probabilístico en Core, cache Redis, P95 ≤ 500 ms | ✅ Matcher RT + índice OpenSearch (blocking) + Redis |
| **RF-04** Integración con sistemas fuente | ✅ ESB EventBridge+SQS; transformador HL7↔FHIR (Lambda) | ✅ Bus Kafka + adaptadores en Azure; HL7↔FHIR gobernado desde Azure |
| **RF-05** Búsqueda / Vista 360° | ✅ Consulta sobre Aurora + cache | ✅ **Vista 360° materializada en BigQuery** (incluye imágenes) |
| **RF-06** Ciclo de vida del registro | ✅ Lifecycle Manager (máquina de estados) | ✅ Proyecciones sobre el flujo de eventos |
| **RF-07** Gobierno y calidad | ✅ Dashboard INI-06a + alertas > 2% | ✅ Métricas nativas por eventos + reporte batch precisión/recall |
| **Imágenes PACS inter-sede** | ❌ **No abordado** (PACS solo recibe EMPI-ID como consumidor pasivo vía ESB) | ✅ **Diferencial**: Healthcare API etiqueta estudios DICOM con EMPI-ID → radiólogo ve imágenes de todas las sedes |

**Lectura funcional:** en los RF "clásicos" del EMPI (identidad, deduplicación, matching, 360°, gobierno) **ambas son funcionalmente equivalentes**. La diferencia funcional decisiva es la **unificación de imágenes inter-sede** (GT-04 / GSI-08 del Hito 1): la Alt. 1 deja el PACS como consumidor pasivo del EMPI-ID sin resolver la fragmentación de imágenes, mientras que la Alt. 3 Mejorada la resuelve explícitamente vía GCP Cloud Healthcare API.

### 3.2 Cobertura de requerimientos no funcionales

| RNF | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **RNF-01** Latencia (P95 ≤ 500 ms) | ✅ Cache Redis; todo en una nube (sin saltos) | ✅ Cache + OpenSearch; perímetro interno en AWS evita salto cross-cloud en el hot path |
| **RNF-02** Disponibilidad 99.9% | ✅ Aurora Multi-AZ, failover < 30 s | ✅ Multi-AZ por servicio; bus con replicación factor 3 |
| **RNF-03** Seguridad (RBAC, cifrado, auditoría) | ✅ API GW + JWT; auditoría en CloudWatch (escritura secundaria) | ✅ RBAC en Core; **mTLS por dirección**; **auditoría nativa por eventos** |
| **RNF-04** Interoperabilidad | ✅ FHIR R4 + HL7 v2 (Lambda adapter) | ✅ FHIR R4 (`$match`) + HL7 v2 + **DICOM** (Healthcare API) |
| **RNF-05** Escalabilidad ante picos | 🟡 Escala Aurora + ElastiCache; matching sin índice dedicado | ✅ **OpenSearch dedicado** + autoscaling + Splink@BigQuery (millones de registros, campañas ×2) |
| **RNF-06** Observabilidad | ✅ CloudWatch centralizado | ✅ Logs + métricas por evento; multi-nube requiere agregación |
| **RNF-07** Ley 29733 (retención, cifrado) | ✅ Cifrado + Glacier 10 años + PIA | ✅ Datos sintéticos en demo; cifrado por nube; PIA pre-producción |

**Lectura funcional NFR:** la Alt. 1 destaca en **simplicidad de observabilidad y latencia predecible** (una sola nube, un solo panel). La Alt. 3 Mejorada destaca en **escalabilidad a alta volumetría** (índice de blocking dedicado, ADR-A3M-011), **seguridad diferenciada por dirección de tráfico** y **auditoría nativa** (inmutable por diseño, no por escritura secundaria).

### 3.3 Experiencia por actor

| Actor | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **Admisionista** | Registra vía API GW único; respuesta < 500 ms | Registra vía perímetro interno mTLS en AWS; misma latencia |
| **Médico** | Vista 360° sobre Aurora | Vista 360° en BigQuery, **con imágenes inter-sede** |
| **Médico Radiólogo** | Sin cambio real: imágenes siguen fragmentadas por sede | ✅ **Ve todas las imágenes del paciente** unificadas por EMPI-ID |
| **Operador Gobierno de Datos** | Dashboard INI-06a + cola de revisión | Revisión de fusiones + reporte batch con métricas |
| **Auditor** | Consulta CloudWatch/Glacier | Consulta el flujo de eventos (traza completa nativa) |

---

## 4. Comparación técnica

### 4.1 Topología y distribución

| Dimensión | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **Nubes** | 1 (AWS) | 3 (AWS + Azure + GCP) + on-prem + bus neutral |
| **Criterio de ubicación** | Consolidación en la nube del Portal | **Concordancia de dominio** (afinidad de negocio) |
| **Núcleo de identidad** | AWS (ECS Fargate) | AWS (ECS Fargate) — *coinciden* |
| **Punto único de fallo** | EMPI Core centralizado (mitigado Multi-AZ) | Distribuido por dominio; el core sigue siendo crítico pero la propagación está desacoplada por nube |
| **Aprovechamiento del parque multinube** | ❌ No usa Azure ni GCP | ✅ Usa las 3 nubes existentes por afinidad |

### 4.2 Persistencia y modelo de datos

| Dimensión | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **Patrón de datos** | Golden Record **relacional** (estado en sitio) | **Event Sourcing** (append-only + proyecciones) |
| **Motor** | Aurora PostgreSQL Multi-AZ | Amazon RDS PostgreSQL |
| **Auditoría** | Escritura **secundaria** a CloudWatch (ventana teórica de inconsistencia, reconocida en ADR-A1-008) | **Nativa**: el log de eventos es la fuente de verdad (inmutable por diseño) |
| **Ciclo de vida** | Máquina de estados explícita (Lifecycle Manager) | Reconstruido por reproducción de eventos + proyecciones |
| **Complejidad del modelo** | Menor (CRUD relacional conocido) | Mayor (ES/CQRS avanzados para el equipo) |

### 4.3 Matching y deduplicación

| Dimensión | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **Matching tiempo real** | Scorer probabilístico en el Core + cache | Matcher + **índice OpenSearch/Elasticsearch** (blocking dedicado) |
| **Escalabilidad del matching** | 🟡 Limitada por la DB en concurrencia alta | ✅ Índice dedicado garantiza blocking a millones de registros (ADR-A3M-011) |
| **Batch (INI-01)** | Step Functions + Lambdas (paralelismo configurable) | **Splink** (Fellegi-Sunter) serverless, backend-swappable (DuckDB↔BigQuery) |
| **Portabilidad del batch** | Atado a Step Functions (AWS) | ✅ Mismo código en demo y producción (anti-lock-in) |

### 4.4 Integración y mensajería

| Dimensión | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **Bus** | AWS EventBridge + Amazon SQS (nativo AWS) | **Kafka neutral** (Confluent/Redpanda) |
| **Lock-in de mensajería** | 🟡 Alto (3 servicios propietarios AWS) | ✅ Bajo (acoplamiento al protocolo Kafka, broker movible sin tocar código) |
| **Garantía de entrega** | Retry backoff + DLQ (SQS) | Retención de topics + DLQ por consumidor (equivalente Kafka) |
| **Interoperabilidad** | HL7↔FHIR (Lambda) | HL7↔FHIR (Azure Functions) + **DICOM** (Healthcare API) |
| **Propagación cross-cloud** | No aplica (todo en AWS) | Asíncrona por enlaces privados (PrivateLink / Private Service Connect) |

### 4.5 Seguridad y perímetro

| Dimensión | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **Perímetro** | **Único** API Gateway para todo el tráfico | **Diferenciado por dirección**: público (WAF), interno (mTLS/ALB), salida (Azure APIM mTLS) |
| **Autenticación** | JWT/OAuth2 federado (IAM INI-03) | RBAC en Core + mTLS entre planos |
| **Tráfico interno (admisión)** | Pasa por el mismo API GW | mTLS directo al core en AWS, sin salto cross-cloud |
| **Superficie de ataque** | Menor (un perímetro) | Mayor (3 nubes), pero segmentada y con mTLS por tramo |

### 4.6 Despliegue, operación y demostrabilidad

| Dimensión | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **IaC** | Implícito (no es el foco del Hito 2) | ✅ **Terraform tri-cloud**, un módulo por nube; `apply`/`destroy` |
| **Demostrabilidad end-to-end** | No definida como entregable ejecutable | ✅ **Demo funcional en 8 pasos** con datos sintéticos (Faker es_PE) |
| **Perfiles** | Uno (producción) | **Dos**: Producción (a escala) y Demo/Lab (OSS ligero, misma topología) |
| **Complejidad operativa** | Menor (una nube, un equipo de skills AWS) | Mayor (3 nubes, 3 credenciales/regiones, más servicios) |
| **Curva de aprendizaje** | Moderada (servicios AWS gestionados) | Alta (DDD/CQRS/ES + multicloud) |

### 4.7 Costos (cualitativo)

| Dimensión | Alternativa 1 | Alternativa 3 Mejorada |
|---|---|---|
| **Modelo de costo** | Consolidado en AWS (previsible, un solo billing) | Distribuido en 3 nubes + egreso cross-cloud |
| **Egreso de datos** | Mínimo (intra-AWS) | Mayor (tráfico AWS↔Azure↔GCP), acotado a propagación asíncrona |
| **Optimización demo** | No aplica | Perfil demo con OSS (Orthanc, HAPI FHIR, DuckDB, Redpanda) reduce costo sin cambiar topología |

---

## 5. Matriz comparativa consolidada

| Criterio | Alternativa 1 (Hito 2) | Alternativa 3 Mejorada (Hito 3) | Ventaja |
|---|---|---|---|
| **Nubes** | 1 (AWS) | 3 (AWS/Azure/GCP) + neutral | Alt.1 = simplicidad · Alt.3M = aprovechamiento |
| **Principio de ubicación** | Consolidación | Concordancia de dominio | Alt.3M |
| **Modelo de datos** | Golden Record relacional | Event Sourcing + CQRS | Alt.3M (auditoría nativa) · Alt.1 (simplicidad) |
| **Matching a escala** | Sin índice dedicado | OpenSearch dedicado | **Alt.3M** |
| **Batch dedup** | Step Functions (AWS) | Splink backend-swappable | **Alt.3M** (portabilidad) |
| **Bus / lock-in** | EventBridge+SQS (alto) | Kafka neutral (bajo) | **Alt.3M** |
| **Imágenes inter-sede** | No abordado | Healthcare API + EMPI-ID | **Alt.3M** |
| **Perímetro** | Único API GW | Por dirección (WAF/mTLS) | Alt.3M (granularidad) · Alt.1 (simplicidad) |
| **Latencia hot path** | Todo intra-AWS | Interno en AWS (evita cross-cloud) | Empate |
| **Observabilidad** | CloudWatch único | Multi-nube (requiere agregación) | **Alt.1** |
| **Complejidad operativa** | Menor | Mayor | **Alt.1** |
| **Curva de aprendizaje** | Moderada | Alta | **Alt.1** |
| **Costo / egreso** | Consolidado, mínimo egreso | Distribuido + egreso cross-cloud | **Alt.1** |
| **IaC / demostrabilidad** | No es el foco | Terraform tri-cloud, demo E2E | **Alt.3M** |
| **Anti-lock-in** | Bajo (atado a AWS) | Alto (portabilidad) | **Alt.3M** |
| **Alineación con Hito 1 (PT-02 multinube gobernada)** | Parcial (no usa las 3 nubes) | Total (usa las 3 por afinidad) | **Alt.3M** |

---

## 6. Análisis de madurez, riesgo y evolución

- **Alternativa 1** es la opción de **menor riesgo de ejecución y menor time-to-value inicial**: una sola nube, servicios gestionados maduros, skills concentrados en AWS y un modelo relacional familiar. Su costo es la **infrautilización del parque multinube**, el **lock-in a AWS** en la mensajería, la ausencia de una **estrategia de imágenes inter-sede** y una auditoría por escritura secundaria (con la ventana de inconsistencia que su propio ADR-A1-008 reconoce).

- **Alternativa 3 Mejorada** es la opción de **mayor alineación arquitectónica y mejor posicionamiento a futuro**: usa las 3 nubes por afinidad real (coherente con la visión multinube gobernada del Hito 1), garantiza escalabilidad de matching a alta volumetría, resuelve la unificación de imágenes, tiene auditoría inmutable nativa y es **anti-lock-in**. Además, es la única **demostrable end-to-end por IaC** —requisito del trabajo final—. Su costo es la **mayor complejidad operativa**, la **curva de aprendizaje** (DDD/CQRS/ES + multicloud) y el **egreso cross-cloud**.

- **Relación evolutiva:** no son diseños opuestos, sino un **continuo de madurez**. El núcleo de identidad de ambas coincide en AWS (ECS Fargate). La Alt. 3 Mejorada puede verse como la **evolución natural** de la Alt. 1: mantiene el mismo corazón, sustituye la persistencia relacional por Event Sourcing, promueve el bus a un backbone neutral, distribuye la integración y la analítica por concordancia y **añade** la dimensión de imágenes. El perfil **Demo/Lab** de la Alt. 3M permite validar esta arquitectura sin asumir de golpe todo el costo de producción.

---

## 7. Conclusión y recomendación

| Escenario del proyecto | Alternativa recomendada |
|---|---|
| **Entrega rápida, un solo equipo AWS, alcance acotado a identidad+deduplicación** | **Alternativa 1** — menor riesgo y complejidad |
| **Aprovechar el parque multinube de SanaRed, escalar a alta volumetría, unificar imágenes inter-sede y demostrar end-to-end por IaC** | **Alternativa 3 Mejorada** — mayor alineación y proyección |

**Recomendación para el proyecto EMPI de SanaRed:** dado que (1) el Hito 1 estableció una **estrategia multinube gobernada** (PT-02), (2) el caso exige resolver la **fragmentación de imágenes inter-sede** (GT-04/GSI-08), (3) la volumetría real (126,000 duplicados + picos de campaña ×2) demanda un **índice de matching escalable**, y (4) el trabajo final requiere una **solución demostrable en laboratorio cloud**, la **Alternativa 3 Mejorada** es la más adecuada como **arquitectura objetivo**.

La **Alternativa 1** conserva valor como **línea base de referencia** y como **ruta de adopción incremental**: su núcleo AWS es compartido, por lo que puede desplegarse primero (Fase 1) y evolucionar hacia el modelo concordante tri-cloud (Fases 2–3) sin reescribir el corazón del sistema. Esta lectura evolutiva —**empezar simple (Alt.1), madurar hacia concordante (Alt.3M)**— combina el bajo riesgo inicial de la primera con la proyección estratégica de la segunda.

---

*Documento generado para Hito 4 — Comparativo de Alternativas | Iniciativa EMPI | Clínica SanaRed Integrada*
*Compara: `entregables_hito2/Diseño/Alternativa_1_*` (Hito 2) vs. `entregables_hito3/03_Alternativa3_Mejorada_Multicloud_Concordante.md` (Hito 3)*
