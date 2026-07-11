# Explicación Detallada — Alternativa TO BE 2
## EMPI Federado con Domain-Driven Design (DDD) y Event Sourcing
### Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada

---

## 1. Descripción General de la Arquitectura

La Alternativa 2 adopta un enfoque de **EMPI federado**, basado en los principios de **Domain-Driven Design (DDD)**, el patrón **CQRS** (Command Query Responsibility Segregation) y **Event Sourcing**. A diferencia de la Alternativa 1 (que centraliza todo en una base de datos Aurora con un modelo de escritura y lectura unificado), esta alternativa separa radicalmente las operaciones de **escritura** (comandos que modifican la identidad del paciente) de las operaciones de **lectura** (proyecciones optimizadas para distintos casos de uso).

El principio central es que **la identidad del paciente es un dominio de negocio autónomo** con sus propias reglas, su propio lenguaje (el Golden Record) y su propia integridad. Los sistemas clínicos (HCE, LIS, PACS, ERP) son consumidores de ese dominio, no co-propietarios de la identidad.

Esta arquitectura aprovecha la infraestructura **Azure** ya presente en SanaRed (Azure App Service para el portal de pagos, Azure SQL Managed Instance para el LIS, Azure Cosmos DB como candidato natural para el Event Store) y la extiende para soportar el EMPI.

---

## 2. Fundamentos Conceptuales

### 2.1 Domain-Driven Design (DDD) aplicado al EMPI

El DDD establece que el dominio de negocio debe guiar el diseño del software. En el contexto de SanaRed, el **Dominio de Identidad del Paciente** tiene un lenguaje propio:

| Término del dominio | Significado en el EMPI |
|---|---|
| **PatientAggregate** | La entidad raíz del dominio. Encapsula el Golden Record y todas las reglas de negocio de identidad. |
| **EMPI-ID** | El identificador único del agregado. Inmutable una vez asignado. |
| **Golden Record** | El estado actual y canónico del paciente, derivado de todos los eventos históricos. |
| **Command** | Una intención de cambio: `RegisterPatient`, `MergeRecords`, `UpdateContact`, `DeactivateRecord`. |
| **Domain Event** | Lo que ocurrió como resultado: `PatientRegistered`, `RecordsMerged`, `ContactUpdated`. |
| **Bounded Context** | El límite del dominio de identidad. Otros dominios (clínico, financiero, de canales) interactúan con él solo a través de eventos publicados. |

### 2.2 CQRS — Separación de Escrituras y Lecturas

El problema de la Alternativa 1 (EMPI centralizado con una sola base de datos) es que la misma base de datos que soporta las escrituras transaccionales de alta concurrencia (5,200 citas + 780 urgencias diarias = ~250 escrituras/hora en pico) también debe servir las lecturas de la vista longitudinal 360° (que requieren joins complejos entre múltiples tablas). Esto crea contención y puede degradar la latencia en horas pico.

CQRS resuelve esto separando:
- **Write Side (Commands):** El `PatientAggregate` procesa comandos y persiste eventos en el Event Store. El modelo de escritura es simple y optimizado para consistencia transaccional.
- **Read Side (Queries/Proyecciones):** El sistema mantiene proyecciones especializadas en bases de datos optimizadas para cada tipo de lectura. No hay joins en tiempo de consulta porque las proyecciones se construyen asíncronamente a partir del stream de eventos.

### 2.3 Event Sourcing

En lugar de almacenar el estado actual del Golden Record en una tabla relacional (como hace la Alternativa 1), el Event Sourcing almacena la **secuencia inmutable de todos los eventos** que le ocurrieron al registro desde su creación:

```
t=0: PatientRegistered { empiId: "EMPI-001", dni: "12345678", source: "PORTAL_AWS" }
t=1: ContactUpdated    { empiId: "EMPI-001", field: "celular", newValue: "987654321" }
t=2: RecordsMerged     { empiIdActivo: "EMPI-001", empiIdInactivo: "EMPI-002", score: 0.97 }
```

El estado actual del Golden Record se deriva **reproduciendo** esa secuencia de eventos. Esto tiene implicancias poderosas para SanaRed:

- **Trazabilidad perfecta:** El Anexo señala que no existe correlación única de auditoría entre sistemas. Con Event Sourcing, el log de auditoría no es algo que se genera adicionalmente: es la estructura de datos primaria. Cada cambio en la identidad es un evento con timestamp, autor y sistema de origen (RNF-03.4).
- **Reversibilidad:** Si una fusión fue incorrecta, no se "deshace" con un UPDATE; se agrega un evento `MergeReverted` y se proyecta el estado correcto.
- **Reconstrucción de proyecciones:** Si se necesita una nueva proyección (ej. agregar la vista longitudinal 360° en Fase 3), simplemente se reproduce el stream completo de eventos sobre el nuevo modelo de lectura, sin migración de datos.

---

## 3. Capas de la Arquitectura

### 3.1 Seguridad Perimetral (Azure APIM + IAM Federado)

Se usa **Azure API Management (APIM)** como API Gateway, aprovechando la infraestructura Azure ya existente en SanaRed. Implementa:
- **mTLS (Mutual TLS):** Autenticación bidireccional entre el API Gateway y los sistemas fuente internos (HCE Oracle, ERP). Esto es más robusto que el JWT unilateral de la Alternativa 1 para conexiones entre sistemas internos.
- **OAuth2 + OIDC:** Para los canales externos (Portal, App Móvil, Call Center).
- **Rate limiting por canal y por rol:** El Portal AWS y la App Móvil tienen límites distintos a los de los módulos de admisión internos.

### 3.2 Dominio de Identidad del Paciente (Identity Bounded Context)

#### Commands (Write Side)

Los cuatro comandos del dominio cubren el 100% de las operaciones que modifican la identidad de un paciente:

| Comando | Cuándo se usa | RF relacionado |
|---|---|---|
| `RegisterPatient` | Alta de paciente nuevo desde cualquier canal | RF-01 |
| `MergeRecords` | Fusión de duplicados (automática o manual) | RF-02, RF-03 |
| `UpdateContact` | Actualización de datos de contacto | RF-04 |
| `DeactivateRecord` | Fallecimiento, error de fusión o baja del paciente | RF-06 |

Cada comando es validado por el `PatientAggregate` antes de ser aceptado. Si las reglas de dominio no se cumplen (ej. intentar fusionar un registro INACTIVO_FALLECIDO), el comando es rechazado con un error de dominio específico, no un error técnico genérico.

#### PatientAggregate y Domain Rules

El `PatientAggregate` es el guardián de la consistencia del dominio. Contiene:
- **Validación de DNI:** Algoritmo de verificación del formato del DNI peruano (8 dígitos).
- **Reglas de precedencia:** Tabla configurable que define qué sistema fuente tiene prioridad para cada campo (Portal AWS para datos de contacto, HCE Oracle para datos clínicos como alergias).
- **Scoring thresholds:** Los umbrales del algoritmo de matching son reglas de dominio, no parámetros técnicos. Esto cumple RNF-06.2 (configurabilidad sin redespliegue): se cambian como reglas de negocio, no como configuración de infraestructura.

#### Event Store (Azure Cosmos DB)

Azure Cosmos DB se usa como Event Store por tres razones:
1. **Ya está en el ecosistema Azure de SanaRed:** Reduce la curva de adopción operativa.
2. **Escritura append-only nativa:** El modelo de Cosmos DB de documentos JSON es natural para persistir eventos como `{ eventType, payload, timestamp, version }`.
3. **Change Feed:** Cosmos DB tiene una funcionalidad nativa (Change Feed) que emite en tiempo real cualquier nuevo documento insertado en el contenedor. El ESB (Azure Service Bus + Event Grid) se subscribe a este Change Feed para distribuir los eventos a los consumidores sin polling.

### 3.3 Read Side — Proyecciones CQRS

Las proyecciones son vistas materializadas, construidas asíncronamente a partir del stream de eventos. Cada una está optimizada para su caso de uso específico:

**Proyección 1: Golden Record View (Azure Cosmos DB)**
Es la proyección para búsqueda rápida por EMPI-ID o por DNI. Contiene solo los campos de identidad activos del Golden Record. Se actualiza en tiempo cuasi-real (< 2 segundos de latencia desde el evento). Sirve las consultas de admisión y del portal.

**Proyección 2: Vista Longitudinal 360° (Azure Synapse Analytics)**
Es la proyección más rica. Combina los eventos de identidad del EMPI con los datos clínicos de HCE, resultados del LIS y citas de la Agenda para construir la vista completa del paciente. Al ser una proyección materializada (no una consulta en tiempo real sobre múltiples bases de datos), la latencia de la vista 360° es < 2 segundos independientemente de cuántos sistemas fuente tenga el paciente. Este era el problema raíz del AS IS: los médicos debían esperar mientras el sistema hacía joins en tiempo real sobre sistemas distribuidos con latencias distintas.

**Proyección 3: Duplicates Index (Elasticsearch)**
Es el índice optimizado para el matching probabilístico en tiempo real. Elasticsearch soporta búsquedas fuzzy sobre texto (nombres con variaciones ortográficas), búsquedas por similitud (fechas de nacimiento con ±1 año de tolerancia) y scoring de relevancia nativo. La consulta de matching en tiempo real trabaja sobre esta proyección, no sobre la base de datos transaccional, lo que garantiza P95 <= 500 ms (RNF-01.1) incluso bajo carga alta.

**Proyección 4: Audit Trail (Azure Monitor Logs)**
Proyección de todos los eventos de dominio en formato de log estructurado. Consultable en < 10 segundos por rango de fechas y por EMPI-ID (RNF-03.4). Al ser una proyección derivada del Event Store y no una tabla de auditoría separada, es imposible que una operación ocurra sin quedar registrada: el evento debe existir en el Event Store antes de que el sistema tome cualquier acción.

### 3.4 Servicio de Matching Distribuido

**Real-Time Matcher (INI-13)**
Consulta el índice de Elasticsearch con una estrategia en tres pasos:
1. Búsqueda exacta por DNI (respuesta en < 10 ms si existe).
2. Si no hay exacta, búsqueda fuzzy por nombre + fecha de nacimiento (respuesta en < 200 ms).
3. Scoring probabilístico sobre los candidatos (respuesta total P95 < 500 ms).

**Batch Deduplication (INI-01 — Azure Databricks)**
A diferencia de la Alternativa 1 (que usa AWS Step Functions con procesamiento secuencial), la Alternativa 2 usa **Azure Databricks** para el batch. Databricks permite procesamiento paralelo distribuido: en lugar de procesar 50,000 registros/hora de forma secuencial, puede procesar particiones en paralelo sobre múltiples workers, potencialmente reduciendo el tiempo del batch inicial (126,000 duplicados) a una sola noche de procesamiento.

**Manual Review Queue (Azure Service Bus)**
Los casos con score 85%-94% se encolan en Azure Service Bus con prioridad según el score (los más cercanos al umbral superior se procesan primero). La UI de revisión presenta los dos registros lado a lado con el score y los atributos coincidentes y divergentes. El operador puede ver el historial completo de eventos de cada registro (gracias al Event Sourcing) antes de decidir.

### 3.5 Bus de Eventos de Dominio (Azure Service Bus + Event Grid)

La diferencia clave con la Alternativa 1 es que los eventos publicados por el EMPI son **eventos de dominio** con semántica de negocio, no notificaciones técnicas genéricas:

| Evento | Significado de negocio | Consumidores |
|---|---|---|
| `identity.patient.created` | Nuevo paciente registrado en la red | HCE, LIS, Agenda |
| `identity.patient.merged` | Dos registros fueron unificados | HCE, ERP, Agenda |
| `identity.contact.updated` | Datos de contacto del paciente cambiaron | CRM, Agenda, Portal |
| `identity.record.deactivated` | Registro inactivado (fallecimiento o fusión) | HCE, ERP |

Cada consumidor suscribe solo a los topics que le son relevantes. El ERP, por ejemplo, no necesita saber que un paciente fue registrado (no hay factura todavía), pero sí necesita saber cuando dos registros se fusionan (para consolidar las facturas pendientes bajo el EMPI-ID activo).

La **Dead Letter Queue** captura los eventos que no pudieron ser procesados por el consumidor después de 3 reintentos (backoff exponencial: 30s, 60s, 120s). Esto cumple RNF-02.4 y permite análisis forense sin pérdida de eventos.

### 3.6 Consumidores de Dominio (por Bounded Context)

La arquitectura organiza los consumidores por **dominios de negocio** (no por tecnología), siguiendo los mismos dominios identificados en el Mapa de Dominios de Datos del Hito 1:

- **Dominio Clínico (HCE Oracle):** Consume eventos de creación y fusión de pacientes para mantener la vinculación de historias clínicas al EMPI-ID correcto.
- **Dominio Diagnóstico (LIS + PACS):** Consume eventos de creación para vincular resultados e imágenes al EMPI-ID desde el primer examen.
- **Dominio Financiero (ERP):** Consume eventos de fusión y actualización de contacto para mantener la coherencia de la facturación y reducir el 13% de expedientes observados.
- **Dominio Canal (Agenda + CRM):** Consume eventos de creación y actualización de contacto para sincronizar disponibilidades y datos de comunicación.

### 3.7 Observabilidad y Gobierno

**Dashboard EMPI (Power BI / Grafana):** Conectado directamente al stream de eventos, puede calcular KPIs en tiempo casi real: tasa de duplicados, throughput del batch, cola de revisión manual, latencia P95 del matching.

**Alerting Service:** Suscrito al stream de eventos, detecta patrones anómalos: si la tasa de `PatientRegistered` sin `EMPI-ID` previo supera el 5% en una hora, es una señal de que un sistema fuente está generando registros sin consultar el EMPI primero.

**Governance Engine:** Gestiona las reglas de retención (RNF-07.2): archiva automáticamente los eventos de registros con más de 10 años de inactividad en Azure Blob Storage (Cool Tier). Genera los reportes de cumplimiento de la Ley 29733 con evidencia directa del Event Store.

---

## 4. Flujo Principal — Deduplicación y Fusión

El diagrama de secuencia describe el proceso batch nocturno y la revisión manual, que es el flujo más complejo y el que resuelve el problema de los 126,000 duplicados.

El flujo batch opera sobre el stream de eventos del Event Store (no sobre una base de datos relacional), lo que le da ventajas: puede procesar en paralelo por partición de fecha, puede retomar desde el último checkpoint si falla a mitad, y genera eventos inmutables por cada decisión de merge tomada.

El flujo de revisión manual usa la interfaz de la UI de revisión que consume la Manual Review Queue. El operador ve el historial completo de eventos de cada registro gracias al Event Sourcing, lo que le permite tomar decisiones más informadas (ej. saber que el registro A fue creado en el Portal y el registro B en Admisión, y que el registro A tiene más historial).

---

## 5. Diagrama C4 — Nivel Contexto

El diagrama C4 de nivel contexto muestra las interacciones entre los actores humanos, el sistema EMPI y los sistemas externos. Siguiendo el estándar C4:
- **Personas:** Admisionista, Médico y Operador de Gobierno de Datos son los tres actores principales.
- **Sistema:** El EMPI es la caja negra central.
- **Sistemas Externos:** HCE, LIS, Agenda, Portal, ERP e IAM.
- **Relaciones:** Muestran el protocolo de comunicación (FHIR R4, Service Bus, OAuth2).

Este nivel de diagrama es útil para presentar la solución a stakeholders no técnicos: muestra quién usa el sistema y cómo se relaciona con los sistemas existentes, sin entrar en detalles de implementación.

---

## 6. Comparación con la Alternativa 1

| Dimensión | Alternativa 1 (Centralizada) | Alternativa 2 (Federada DDD) |
|---|---|---|
| **Modelo de datos** | Base de datos relacional Aurora (estado actual) | Event Store Cosmos DB (secuencia de eventos) |
| **Lectura** | Única base de datos (contención escritura/lectura) | Proyecciones especializadas por caso de uso |
| **Auditoría** | Log secundario generado por la aplicación | Nativa: el Event Store es el log de auditoría |
| **Reversibilidad** | UPDATE sobre el registro + log de reversión | Append de evento `MergeReverted`; nunca se borra |
| **Matching batch** | AWS Step Functions (secuencial) | Azure Databricks (paralelo distribuido) |
| **Cloud primario** | AWS | Azure (ya presente en SanaRed para LIS y pagos) |
| **Complejidad de implementación** | Media | Alta |
| **Curva de aprendizaje del equipo** | Baja (patrón conocido) | Alta (DDD + CQRS + Event Sourcing son avanzados) |
| **Escalabilidad a largo plazo** | Buena (con sharding manual) | Excelente (proyecciones escalan independientemente) |
| **Tiempo estimado Fase 1** | 3-4 meses | 5-6 meses |

---

## 7. Ventajas Diferenciales de la Alternativa 2

| Aspecto | Detalle |
|---|---|
| Trazabilidad perfecta y nativa | La auditoría no es un add-on: es la estructura de datos. Cada evento tiene autor, timestamp y sistema de origen. |
| Proyecciones sin joins | La vista 360° se materializa asíncronamente. El médico no espera joins entre 6 sistemas en tiempo real. |
| Resiliente a fallos parciales | Si Elasticsearch falla, el matching puede degradarse a búsqueda exacta en Cosmos DB sin perder el historial. |
| Matching paralelo con Databricks | El batch de 126,000 duplicados puede completarse en una sola noche vs múltiples ventanas. |
| Evolución sin migración | Agregar una nueva proyección (ej. analytics clínico) no requiere migrar datos; solo reproducir el stream de eventos. |

## 8. Limitaciones y Riesgos de la Alternativa 2

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Consistencia eventual | Las proyecciones se actualizan con un delay de < 2 s. Una consulta inmediatamente post-escritura puede ver datos desactualizados. | Diseñar la API para devolver el evento confirmado al canal inmediatamente tras el commit en el Event Store. |
| Complejidad operacional | El equipo de SanaRed debe manejar Cosmos DB + Elasticsearch + Databricks + Service Bus. | Plan de capacitación y contratar o asignar un arquitecto de datos con experiencia en Event Sourcing. |
| Latencia de propagación a HCE | El HCE Oracle (On-Premises Lima) recibe eventos via Service Bus pero puede tener delay de red. | Priorizar la cola del HCE y configurar SLA de entrega < 30 s en el Service Bus. |
| Costo de infraestructura Azure | Cosmos DB + Databricks + Elasticsearch tienen costo base significativo. | Evaluar Azure Cosmos DB serverless para el Event Store y Elastic Cloud con instancia mínima en Fase 1. |

---

*Documento generado para Hito 2 — Iniciativa EMPI | Clínica SanaRed Integrada*
