# Explicación Detallada — Alternativa TO BE 1
## EMPI Centralizado con API Gateway y Bus de Integración (ESB)
### Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada

---

## 1. Descripción General de la Arquitectura

La Alternativa 1 propone un modelo de **EMPI completamente centralizado**, donde existe un único punto de verdad para la identidad del paciente. Todos los canales de entrada (Portal, Admisión, Agenda, App, Call Center) convergen hacia un API Gateway que autentica y enruta las solicitudes al núcleo del EMPI. Los cambios en el Golden Record se propagan de forma asíncrona a los sistemas clínicos a través de un Bus de Integración (ESB) basado en eventos.

Este enfoque responde directamente a los tres riesgos tecnológicos del Anexo: centraliza la identidad para resolver la **Integridad** (Riesgo #2), implementa seguridad perimetral y cifrado para mitigar la **Seguridad** (Riesgo #1), y usa caché y colas con retry para garantizar la **Disponibilidad** (Riesgo #3).

---

## 2. Capas del Arquitectura

### 2.1 Capa de Canales (Entrada de Identidad)

Esta capa agrupa todos los sistemas que hoy generan registros de pacientes de forma independiente y desconectada:

| Sistema | Tecnología actual | Rol en el EMPI TO BE |
|---|---|---|
| Portal de Pacientes | AWS RDS PostgreSQL | Fuente primaria de datos de contacto |
| Agenda Médica | SaaS externo | Fuente de citas y disponibilidad |
| Call Center | CRM SaaS | Fuente de datos biográficos por teléfono |
| Módulos de Admisión | On-Premises x4 clínicas | Fuente de admisiones presenciales y urgencias |
| App Móvil | GCP Cloud Run | Canal de autogestión del paciente |

En el estado AS IS, cada uno de estos sistemas crea sus propios registros sin validar contra los demás, lo que produjo los 126,000 duplicados identificados. En el TO BE, **ningún canal crea un registro de paciente directamente en su propia base de datos** sin pasar primero por el EMPI. Todos invocan la API del EMPI y reciben de vuelta el EMPI-ID canónico, que deben almacenar como referencia.

### 2.2 Capa de Seguridad y Acceso (API Gateway + IAM)

El **API Gateway** (implementado sobre AWS API Gateway) actúa como el único punto de entrada al EMPI. Sus responsabilidades son:

- **Autenticación:** Valida el token JWT emitido por el IAM Centralizado (INI-03). Sin token válido, ninguna solicitud llega al EMPI Core.
- **Autorización:** Verifica los claims del token para determinar el rol del solicitante (Admisionista, Médico, Operador de Datos, etc.) y si tiene permiso para la operación solicitada.
- **Rate limiting:** Protege al EMPI de sobrecargas en campañas corporativas (el caso documentó que 18,000 citas por lote saturaron los sistemas).
- **Logging centralizado:** Cada solicitud queda registrada con su origen, timestamp y resultado, contribuyendo a la trazabilidad requerida por RNF-03.4.

El **IAM Centralizado** (INI-03) emite tokens federados que son válidos en todos los sistemas del ecosistema: Portal AWS, HCE Oracle, Agenda SaaS. Esto elimina las cuentas compartidas y los permisos heredados por sede que el Anexo señala como riesgo de seguridad crítico.

### 2.3 EMPI Core — Núcleo del Índice Maestro

Es el corazón de la solución. Está compuesto por cuatro microservicios internos:

**Motor de Matching & Scoring**
Implementa el algoritmo de matching probabilístico que evalúa la similitud entre registros usando múltiples atributos: DNI (peso alto), nombre fonético (algoritmo Soundex/Metaphone para variaciones como "Juan" vs "Jhuan"), fecha de nacimiento, número de celular y correo electrónico. Produce un score de confianza entre 0% y 100% que determina la acción:
- Score >= 95%: fusión automática (RF-02, Scenario batch) o flag `POSIBLE_DUPLICADO` en tiempo real.
- Score 85%-94%: cola de revisión manual.
- Score < 85%: registro considerado paciente nuevo.

**Golden Record Engine**
Es el componente que gestiona la creación y actualización del Golden Record canónico. Aplica las **reglas de precedencia** entre sistemas fuente para resolver conflictos de datos (ej. Portal AWS tiene mayor confianza para datos de contacto; HCE Oracle tiene mayor confianza para datos clínicos). Genera el EMPI-ID con formato estándar único no reutilizable.

**Deduplication Service**
Opera en dos modos complementarios que corresponden a los dos proyectos de la iniciativa:
- **Modo batch (INI-01):** Se ejecuta entre 00:00 y 05:00 mediante AWS Step Functions. Procesa el inventario de duplicados históricos a una tasa de >= 50,000 registros/hora para resolver los 126,000 casos en menos de 5 ventanas nocturnas.
- **Modo tiempo real (INI-13):** Se invoca sincrónicamente en cada alta o consulta de paciente. Responde en <= 500 ms (P95) gracias al cache Redis previo al matching.

**Lifecycle Manager**
Controla las transiciones de estado del Golden Record a lo largo del tiempo, tal como se modeló en el Diagrama de Estados: INCOMPLETO → VERIFICADO → POSIBLE_DUPLICADO → INACTIVO_FUSIONADO / INACTIVO_FALLECIDO. Garantiza que un registro inactivo nunca sea eliminado, solo archivado, cumpliendo el requisito de retención de 10 años (RNF-07.2).

### 2.4 Almacenamiento EMPI

El almacenamiento está diseñado en tres capas con propósitos distintos:

**Master DB (Aurora PostgreSQL Multi-AZ)**
Es la base de datos principal de los Golden Records. Se eligió Aurora PostgreSQL Multi-AZ para cumplir RNF-02.1 (disponibilidad 99.9%) con failover automático en menos de 30 segundos. Contiene la tabla de Golden Records (con el EMPI-ID, estado, atributos biográficos cifrados y referencias a sistemas fuente) y la tabla de relaciones entre registros (fusiones, dependientes familiares).

**Cache Layer (ElastiCache Redis)**
Almacena los lookups más frecuentes (búsquedas por DNI y por EMPI-ID) con un TTL de 5 minutos. Este componente es clave para cumplir RNF-01.1 (latencia P95 <= 500 ms en tiempo real): la mayoría de las consultas de admisión resolverán en el cache sin tocar la base de datos. En campañas con picos de demanda, el cache absorbe hasta el 80% del tráfico de lectura.

**Audit Log Store (CloudWatch + S3 Glacier)**
Almacena los registros de auditoría de forma inmutable. CloudWatch retiene los últimos 12 meses para consulta rápida (en < 10 segundos por rango de fechas, RNF-03.4). S3 Glacier almacena el histórico de más de 12 meses hasta los 10 años requeridos por RNF-07.2, a costo mínimo de almacenamiento.

### 2.5 Bus de Integración — ESB (Propagación de Cambios)

El ESB es el mecanismo por el que el EMPI notifica a los sistemas clínicos cuando el Golden Record cambia. Implementa el patrón **Event-Driven Architecture** con tres componentes:

**Event Bus (AWS EventBridge)**
Cuando el EMPI Core completa una operación (alta, fusión, actualización de datos), publica un evento estructurado (ej. `PATIENT_CREATED`, `PATIENT_MERGED`, `CONTACT_UPDATED`). Los sistemas suscriptores reciben solo los eventos relevantes para ellos. Esto resuelve el problema actual donde la sincronización fallaba en cascada porque era punto a punto y síncrona.

**Cola de Mensajería (Amazon SQS)**
Desacopla el EMPI de los sistemas receptores. Si el HCE Oracle o la Agenda SaaS están temporalmente no disponibles, los eventos quedan encolados y se procesan cuando el sistema vuelve a estar activo (retry con backoff exponencial, RNF-02.4). La Dead Letter Queue captura los eventos que no pudieron ser procesados tras 3 reintentos para análisis posterior.

**Transformador HL7v2 ↔ FHIR R4**
Convierte el formato FHIR R4 nativo del EMPI (recurso `Patient`) al formato HL7 v2 que consume el HCE Oracle y el integrador existente (RNF-04.3). Esto permite la coexistencia de ambos estándares durante la transición sin interrumpir las operaciones.

### 2.6 Sistemas Clínicos Core (Consumidores del EMPI)

Estos sistemas **no desaparecen** con el EMPI; cambian su rol: dejan de ser fuentes de identidad para convertirse en consumidores del Golden Record centralizado:

- **HCE Oracle (On-Premises):** Recibe notificaciones de alta y actualización via ESB. Expone historias clínicas vinculadas por EMPI-ID.
- **LIS Azure SQL:** Vincula resultados de laboratorio al EMPI-ID, eliminando el problema actual donde el integrador HL7 fallaba al asociar resultados al episodio correcto.
- **PACS Local + GCP:** Vincula imágenes DICOM al EMPI-ID para la vista longitudinal.
- **ERP Facturación:** Recibe el EMPI-ID como clave de facturación, eliminando las inconsistencias de identidad que generan el 13% de expedientes observados.

### 2.7 Gobierno y Calidad de Datos

**Dashboard de Calidad EMPI (INI-06a):** Muestra en tiempo real los indicadores de RF-07: tasa de duplicados residual, % de registros con DNI validado, fusiones del período, cola de revisión manual.

**Scheduler Batch (AWS Step Functions):** Orquesta el proceso nocturno de deduplicación (RF-02), garantizando que se ejecute dentro de la ventana 00:00-05:00 y que las dependencias entre pasos (matching → clasificación → merge automático → cola manual) se respeten.

**Alertas Automáticas:** Si la tasa de duplicados supera el 2%, se dispara una alerta al equipo de Gobierno de Datos (RF-07, Scenario 1).

---

## 3. Flujo Principal — Alta de Paciente Nuevo en Tiempo Real

El diagrama de secuencia describe el flujo más crítico del sistema: la admisión de un paciente, que ocurre 5,200 veces al día en la red.

1. El admisionista ingresa los datos del paciente en el módulo de admisión de la sede.
2. El módulo invoca `POST /empi/v1/patients` a través del API Gateway.
3. El API Gateway valida el token JWT y los claims de rol.
4. El EMPI consulta primero el **cache Redis** por el hash del DNI (operación en microsegundos).
5. Si hay hit en cache, devuelve el EMPI-ID existente en < 10 ms, sin tocar la base de datos.
6. Si hay miss en cache, consulta la Aurora DB. Si encuentra el registro, lo devuelve y calienta el cache.
7. Si no existe en base de datos, ejecuta el matching probabilístico sobre atributos biográficos.
8. Según el score, puede: devolver un posible duplicado para confirmación (score 85%-94%), o crear un nuevo Golden Record y publicar el evento `PATIENT_CREATED` al ESB.
9. El ESB propaga el evento a HCE Oracle y Agenda SaaS de forma asíncrona, sin bloquear la respuesta al canal de admisión.

Este flujo garantiza que la latencia de respuesta al admisionista sea siempre inferior a 500 ms (P95), incluso en el peor caso (creación de nuevo registro + propagación), porque la propagación a sistemas clínicos es asíncrona.

---

## 4. Diagrama de Estados del Golden Record

El diagrama de estados modela el ciclo de vida completo de un Golden Record, alineado con los escenarios de RF-06:

- **INCOMPLETO:** Estado inicial cuando el alta se hace con datos mínimos (solo DNI y nombre). El paciente puede ser atendido pero el sistema genera una alerta de enriquecimiento pendiente.
- **VERIFICADO:** Estado operativo normal. El registro tiene datos de identidad completos y validados.
- **POSIBLE_DUPLICADO:** Estado transitorio cuando el matching detecta una similitud entre 85% y 94%. Queda en revisión manual.
- **INACTIVO_FUSIONADO:** El registro fue unificado con otro Golden Record. Redirige automáticamente al EMPI-ID activo. Los datos históricos se conservan.
- **INACTIVO_FALLECIDO:** El paciente falleció. El registro queda en solo lectura con acceso auditado.
- **Archivado:** Estado final después de 10 años de inactividad. Cumple RNF-07.2.

---

## 5. Ventajas de la Alternativa 1

| Aspecto | Beneficio |
|---|---|
| Control centralizado | Un único punto de verdad para la identidad; más simple de auditar |
| Latencia predecible | Cache Redis garantiza < 500 ms en el 80% de consultas |
| Propagación desacoplada | El ESB permite que los sistemas clínicos tengan downtime sin perder eventos |
| Transición gradual | El transformador HL7v2 ↔ FHIR R4 permite incorporar sistemas heredados sin refactorización inmediata |
| Escalamiento horizontal | Aurora Multi-AZ + ElastiCache escalan independientemente según la carga |
| Auditabilidad nativa | Cada operación pasa por el API Gateway y queda en CloudWatch de forma automática |

## 6. Limitaciones y Riesgos de la Alternativa 1

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Punto único de fallo del EMPI Core | Si el EMPI no está disponible, todos los canales de admisión se ven afectados | Aurora Multi-AZ + modo cache offline en sedes (RNF-02.3) |
| Latencia de red On-Premises → AWS | El HCE Oracle (Lima) debe atravesar el enlace dedicado para notificaciones | ESB asíncrono: el HCE recibe la notificación cuando procesa la cola, no en tiempo real |
| Complejidad de la migración inicial | Integrar 5 sistemas fuente con tecnologías heterogéneas es alta complejidad | Despliegue incremental documentado en RF-04 |
| Dependencia del IAM Centralizado (INI-03) | Si INI-03 no está maduro, el EMPI no puede operar con RBAC completo | Implementar autenticación básica JWT como fallback en Fase 1 |

---

*Documento generado para Hito 2 — Iniciativa EMPI | Clínica SanaRed Integrada*
