# ADRs — Alternativa 3 Mejorada (EMPI Multicloud Concordante)
## Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada | Hito 3

> **Qué es este documento:** los **Architecture Decision Records** de la Alternativa 3 Mejorada y su explicación, extraídos de `03_Alternativa3_Mejorada_Multicloud_Concordante.md`. No sustituyen los ADR de la Alt. 3 del Hito 2 (`ADR_Tablas_Resumen.md`, `ADR_Matriz_Comparativa.md`); **evolucionan** esa decisión hacia el modelo multicloud concordante. Los ADR llevan el prefijo **`ADR-A3M-`** (Alternativa 3 Mejorada).

---

## Guía de lectura — ADRs agrupados por tema

| Tema | ADRs | Idea central |
|---|---|---|
| **Placement por concordancia de dominio** | A3M-001, 002, 003, 004, 005, 006 | Cada componente vive en la nube que ya aloja la funcionalidad afín de SanaRed |
| **Tecnología y reducción de complejidad** | A3M-007, 008, 009 | Event Sourcing en PostgreSQL, bus neutral Kafka, Splink backend-swappable |
| **Escala / volumetría** | A3M-011 | Índice OpenSearch para garantizar rendimiento a alta volumetría |
| **Implementación / demo** | A3M-010 | Perfil demo tri-cloud por IaC, funcional end-to-end |

---

## Tabla de ADRs

| ID | Decisión | Por qué | Opción(es) rechazada(s) |
|---|---|---|---|
| **ADR-A3M-001** | **Concordancia de dominio** como principio de asignación de componentes a nubes | Evita que funcionalidad de paciente caiga en una nube de facturación; co-loca por afinidad de negocio | Reparto por preferencia técnica; nube única |
| **ADR-A3M-002** | Núcleo de identidad + Event Store en **AWS RDS PostgreSQL** | El dominio del paciente ya vive en AWS (Portal + RDS); reutiliza base existente y reduce complejidad | Cosmos DB (Azure) — concuerda con diagnóstico/pagos, no con paciente; DynamoDB |
| **ADR-A3M-003** | **Perímetro por dirección de tráfico:** (a) canal **público de paciente** → AWS API GW **+ WAF**; (b) **entrada de sistemas internos** (Módulo de Admisión on-prem, Agenda) → **API GW privado / ALB con mTLS en AWS**, alcanzado por **Direct Connect/VPN** (sin WAF y **sin pasar por Azure**); (c) **salida** del EMPI hacia legados (HCE/LIS/ERP) → **Azure APIM mTLS** | El tráfico web público necesita WAF; los sistemas internos necesitan mTLS y deben llegar al **core (AWS)** sin salto cross-cloud (RNF-01); la propagación a legados se gobierna desde Azure por concordancia clínica | **Enrutar la entrada de admisión por Azure APIM** (añade un salto cross-cloud en el *hot path* y viola RNF-01); un solo gateway |
| **ADR-A3M-004** | Plano de **integración clínica y financiera en Azure** | Concuerda con LIS (Azure SQL) y Portal de Pagos (Azure) ya existentes | Integración en AWS (rompe concordancia clínica) |
| **ADR-A3M-005** | **Imágenes y analítica en GCP** (Cloud Healthcare API + BigQuery) | Concuerda con PACS réplica y Salud Ocupacional ya en GCP; FHIR/DICOM nativos | Synapse+Databricks en Azure (rompe concordancia de imágenes) |
| **ADR-A3M-006** | **El PACS depende del EMPI-ID** para consolidación inter-sede (complemento Fase 2) | Sin identificador común, las imágenes siguen fragmentadas por sede | Mantener PACS con IDs locales |
| **ADR-A3M-007** | **Event Sourcing sobre PostgreSQL relacional** (tabla append-only + proyecciones) | Conserva el patrón de la Alt. 3 con menor complejidad operativa que Cosmos Change Feed | Cosmos DB Change Feed; EventStoreDB |
| **ADR-A3M-008** | **Bus de eventos neutral (Kafka-compatible)** para propagación cross-cloud | Evita lock-in de Service Bus/EventBridge y simplifica el modelo mental multicloud | Service Bus + EventBridge + SQS (3 tecnologías) |
| **ADR-A3M-009** | **Matching batch backend-swappable con Splink** (DuckDB en demo, BigQuery en prod) | **QUÉ** = reducir complejidad + portabilidad: mismo código de linkage probabilístico en demo y producción, serverless (sin clúster Spark). El **DÓNDE** (BigQuery/GCP) es por concordancia analítica → ver ADR-A3M-005 | Databricks-only (sin checkpointing); linkage por reglas fijas sin modelo probabilístico |
| **ADR-A3M-010** | **Perfil Demo/Lab con IaC (Terraform) tri-cloud** y datos sintéticos | El trabajo final exige implementar la solución en laboratorio cloud, funcional end-to-end | Demo mono-nube (no probaría multicloud); solo diagramas |
| **ADR-A3M-011** | **Índice de matching en tiempo real con OpenSearch/Elasticsearch en producción** (pg_trgm solo en el perfil demo) | **Garantiza** el rendimiento del blocking a **alta volumetría** (millones de Golden Records, picos de campaña ×2, alta concurrencia de admisión); prioriza la mejor solución a escala sobre la reducción de complejidad | pg_trgm/DB-only en producción (no escala en concurrencia); matching sin índice dedicado |

---

## Explicaciones ampliadas

### ADR-A3M-003 (perímetro) — entrada al EMPI vs. salida hacia legados

El perímetro **no es "AWS externo / Azure interno" sin más**: se decide por **dirección del tráfico**, y confundirlas lleva a un error de diseño (enrutar la admisión por Azure).

- **Entrada al EMPI (consultar/crear identidad).** Ocurre en el *hot path* del alta (tiempo real, INI-13). Dos canales:
  - **Paciente (público):** Portal / app móvil → **AWS API Gateway + WAF** (protección web).
  - **Sistema interno (Módulo de Admisión on-prem, Agenda):** máquina-a-máquina → **API Gateway privado / ALB con mTLS en AWS**, alcanzado por **Direct Connect/VPN**. **No usa WAF** (no es tráfico web) y **no pasa por Azure** (sería un salto cross-cloud innecesario contra el core que vive en AWS → viola RNF-01).
- **Salida del EMPI (propagar el EMPI-ID a los legados).** HCE (`ADT^A28/A40`), LIS, ERP. Es **asíncrona** y se gobierna desde **Azure APIM mTLS** + adaptadores, por **concordancia clínica** (LIS/Pagos ya viven en Azure).

> **Regla mental:** *entrar a preguntar por identidad* = perímetro del core en **AWS** (WAF si es paciente, mTLS si es sistema interno). *Salir a avisar la identidad* = **Azure APIM**. El error corregido fue tratar la admisión (entrada) como si fuera salida.

### ADR-A3M-008 (bus de eventos) — QUÉ vs. DÓNDE y por qué la concordancia NO aplica

- **QUÉ = Kafka neutral (Confluent/Redpanda)** en lugar de Service Bus/EventBridge → por **neutralidad y portabilidad cross-cloud (anti-lock-in)**: el acoplamiento es al *protocolo Kafka*, no a la mensajería propietaria de una nube. Pasar de 3 tecnologías a 1 es un beneficio *secundario*, no el motivo.
- **DÓNDE = ninguna nube por concordancia.** El bus es la **única pieza transversal**: su función es *cruzar* AWS↔Azure↔GCP para llevar el evento de identidad a todos los dominios. Por eso **no se rige por concordancia** —ponerlo "dentro" de un dominio lo volvería no-neutral—; físicamente se coloca junto al productor principal (EMPI Core en AWS) **solo por latencia de publicación**.

### ADR-A3M-009 (batch de deduplicación) — QUÉ vs. DÓNDE

Son dos decisiones separadas con motivos distintos:
- **QUÉ = Splink** → por **reducir complejidad + portabilidad**: librería de linkage probabilístico ya hecha (Fellegi-Sunter), **serverless** sobre BigQuery (sin clúster Spark que operar) y **backend-swappable** (mismo código en DuckDB para la demo y en BigQuery para producción).
- **DÓNDE = BigQuery/GCP** → por **concordancia de dominio**: la deduplicación es un workload **analítico**, y GCP es el dominio de analítica del diseño (el Hito 1 asignó el Data Lakehouse/BigQuery a GCP en INI-16). Además, la **vista 360° vive en el mismo BigQuery**, así que co-locar el batch evita mover datos entre servicios.

> Contraste con el matcher en tiempo real: ese es *latencia-crítica y ligado al paciente* → va en **AWS**; el batch es *analítico* → va en **GCP**. **Misma capacidad ("matching"), repartida por naturaleza y concordancia.**

### ADR-A3M-011 (índice de matching en tiempo real) — excepción por volumetría

El **índice de matching en tiempo real NO se degrada en producción**. Mientras que pg_trgm es suficiente para *demostrar funcionalidad* en la demo, el perfil de producción **conserva OpenSearch/Elasticsearch** como índice de blocking dedicado, porque a alta volumetría (millones de Golden Records, picos de campaña con volumen ×2) un índice de búsqueda dedicado **garantiza** el rendimiento del blocking que pg_trgm no sostiene en concurrencia. Aquí la prioridad es *garantizar la mejor solución a escala*, no reducir complejidad.

---

## Resumen QUÉ vs. DÓNDE de las decisiones clave

Vista de un vistazo de qué criterio gobierna cada decisión de matching/mensajería:

| Componente | QUÉ (motivo) | DÓNDE (motivo) | ADR |
|---|---|---|---|
| Índice matching tiempo real | OpenSearch — **volumetría** | AWS — **concordancia** (paciente) | A3M-011 |
| Batch de deduplicación | Splink — **complejidad/portabilidad** | GCP/BigQuery — **concordancia** (analítica) | A3M-009 |
| Bus de eventos | Kafka — **neutralidad/anti-lock-in** | **Transversal** — concordancia NO aplica | A3M-008 |

---

*Documento de Hito 3 — ADRs de la Alternativa 3 Mejorada | Iniciativa EMPI | Clínica SanaRed Integrada*
*Extraído de `03_Alternativa3_Mejorada_Multicloud_Concordante.md` · Complementa: `04_Alternativa3_Mejorada_C4_Model.md`*
