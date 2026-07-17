# Hacksheet de Infraestructura — Alternativa 3 Mejorada (EMPI Multicloud)
## Hoja de referencia rápida para el equipo | Perfiles Demo y Producción | Hito 3

> **Qué es este documento:** una **hoja de referencia (cheatsheet)** para el equipo, que lista **todas las piezas de infraestructura** de la Alternativa 3 Mejorada en sus dos perfiles (Demo/Lab y Producción), qué hace cada una, por qué existe y por qué se eligió esa tecnología (no otra).
>
> **Cómo leer la columna "Ambiente":**
> - **Demo + Prod** → la misma pieza se usa en ambos perfiles.
> - **Prod** / **Demo** → pieza específica de ese perfil. Cuando una capacidad cambia de tecnología entre perfiles (p. ej. OpenSearch en prod ↔ pg_trgm en demo), aparecen **como filas emparejadas** para ver el intercambio.
>
> **Convención clave (M3, "complejidad graduada"):** la demo **no es una arquitectura falsa**: respeta la misma topología tri-cloud, solo sustituye servicios gestionados por equivalentes OSS/ligeros. El contrato (protocolos, eventos, flujo) es idéntico al de producción.

**Leyenda de ADRs referenciados:** A3M-001 concordancia de dominio · A3M-002 identidad en AWS RDS · A3M-003 perímetro por dirección · A3M-004 integración clínica en Azure · A3M-005 imágenes/analítica en GCP · A3M-006 PACS depende del EMPI-ID · A3M-007 Event Sourcing sobre PostgreSQL · A3M-008 bus Kafka neutral · A3M-009 batch Splink backend-swappable · A3M-010 demo IaC tri-cloud · A3M-011 índice OpenSearch en prod.

---

## 1. AWS — Núcleo del Paciente (dominio de identidad)

| Componente Infra | Ambiente | Para qué sirve | Razón de ser | Por qué se escogió |
|---|---|---|---|---|
| **EMPI Core (FastAPI)** | Demo + Prod | Servicio de dominio: recibe altas/consultas, ejecuta commands (Register/Merge/…), matching en tiempo real | Es el corazón del EMPI: donde vive la lógica de identidad y el PatientAggregate | Python/FastAPI: rápido de desarrollar, contenerizable, portable a cualquier nube; alinea con el equipo |
| **ECS Fargate** | Demo + Prod | Cómputo serverless que corre el contenedor del EMPI Core | Ejecutar el core sin gestionar servidores/EC2 | Serverless, autoscaling nativo para picos de campaña (RNF-05), paga por uso; en demo basta 1 tarea |
| **Amazon RDS PostgreSQL (Event Store)** | Prod | Almacena `patient_events` (append-only) + proyección `golden_record_view` | Persistencia de la identidad con Event Sourcing; es la fuente de verdad y la auditoría nativa | A3M-002/007: el dominio paciente ya vive en AWS (Portal+RDS); Event Sourcing relacional = menos complejo que Cosmos Change Feed |
| **PostgreSQL (contenedor / RDS free-tier)** | Demo | Mismo Event Store, en versión ligera | Demostrar el patrón append-only sin costo de producción | Mismo motor Postgres → el esquema y el código son idénticos a producción |
| **Amazon OpenSearch / Elasticsearch** | Prod | Índice de *blocking* fuzzy: acota candidatos de match a alta volumetría | El matching a millones de registros necesita un índice dedicado, no un LIKE de SQL | A3M-011: **garantiza rendimiento a escala** (picos ×2, alta concurrencia); pg_trgm no sostiene la concurrencia |
| **pg_trgm (extensión Postgres)** | Demo | Blocking fuzzy "suficiente" para el volumen de demo | Demostrar la funcionalidad de matching sin levantar OpenSearch | Ya viene en Postgres, cero infra extra; a volumen de demo es imperceptible la diferencia |
| **jellyfish (scoring)** | Demo + Prod | Calcula similitud (fonética/distancia) sobre los candidatos del blocking | Convertir candidatos en un score 0–100 para decidir merge/revisión/descarte | Librería probada de algoritmos fonéticos (Soundex/Metaphone/Jaro); mismo scoring en ambos perfiles |
| **ElastiCache Redis** | Prod | Cache de identidad: lookup por DNI de baja latencia (Paso 1 del matcher) | Cumplir P95 ≤ 500 ms (RNF-01) sin golpear la BD en cada admisión | Redis gestionado, HA; absorbe el grueso de lecturas repetidas |
| **Redis (contenedor)** | Demo | Mismo cache, en contenedor | Demostrar el paso de cache | Mismo protocolo; **la app degrada sola** si no está (cache opcional) |

---

## 2. AWS — Red, seguridad y perímetros de entrada

| Componente Infra | Ambiente | Para qué sirve | Razón de ser | Por qué se escogió |
|---|---|---|---|---|
| **VPC + subredes públicas/privadas (2 AZ)** | Demo + Prod | Aislamiento de red; RDS/Redis/OpenSearch viven en subredes privadas sin IP pública | Postura de seguridad (RNF-03) y base para alta disponibilidad (RNF-02) | Estándar de aislamiento cloud; 2 AZ para HA |
| **NAT Gateway** | Demo + Prod | Salida a internet de las subredes privadas (parches, SDKs) sin exponerlas | Las subredes privadas necesitan egreso controlado | Es la forma más simple; la alternativa "privada pura" agrega más recursos, no menos |
| **Security Groups por servicio (app/rds/redis)** | Demo + Prod | Firewall de menor privilegio: solo el SG de la app alcanza datos | Principio de menor privilegio en el plano de datos | Granular por servicio; colapsarlos abriría el plano de datos |
| **KMS CMK (clave gestionada por el cliente)** | Prod | Cifra en reposo el PII (RDS, Redis, secretos) con rotación controlada | Cumplimiento Ley 29733: una sola CMK para todo el PII, auditable | A3M / RNF-03: control explícito de la llave; en demo se puede usar la clave gestionada por AWS |
| **API Gateway + WAF + NLB (perímetro público)** | Prod | Entrada del **canal de paciente** (público): autenticación, throttling, protección de borde | El tráfico web público necesita WAF y control de abuso | A3M-003: perímetro por dirección; el canal público es el único que necesita WAF |
| **ALB o API GW (perímetro público, simplificado)** | Demo | Misma entrada pública, sin VPC Link/NLB intermedios | Demostrar el borde público sin toda la cadena | ALB soporta WAFv2 directo; menos recursos para la demo |
| **ALB privado + mTLS (perímetro interno)** | Demo + Prod | Entrada de **sistemas internos** (Módulo de Admisión on-prem, Agenda) autenticados por certificado | Los sistemas internos deben llegar al core (AWS) **sin salto cross-cloud** (RNF-01) | A3M-003: mTLS directo al core; **no** enrutar admisión por Azure (evita latencia y viola RNF-01) |
| **PKI de mTLS (CA + cert servidor + cert cliente + trust store S3)** | Demo + Prod | Emite y valida los certificados del canal interno mTLS | Sin PKI no hay identidad mutua entre admisión y el core | En demo, PKI generada localmente por Terraform (costo $0); en prod, PKI corporativa |
| **ECR (registro de imágenes)** | Demo + Prod | Aloja las imágenes de contenedor del EMPI Core | Fargate necesita de dónde jalar la imagen | Registro nativo de AWS, integrado con ECS |
| **SSM Parameter Store** | Demo + Prod | Config y descubrimiento (endpoints, umbrales de scoring `threshold_auto/review`, `model_version`) | Configuración *hot-reload* sin redesplegar (RNF-06.2) | Free tier; los umbrales son configuración real, no constantes en código |

---

## 3. Azure — Integración Clínica y Financiera (perímetro de salida)

| Componente Infra | Ambiente | Para qué sirve | Razón de ser | Por qué se escogió |
|---|---|---|---|---|
| **Azure API Management (APIM) mTLS** | Prod | **Perímetro de salida** del EMPI hacia legados (HCE/LIS/ERP), gobernado con mTLS | La propagación a sistemas clínicos/financieros necesita un punto de salida controlado | A3M-003/004: concordancia clínica (LIS y Pagos ya en Azure); mTLS a legados |
| **Azure Functions (Adaptador Clínico)** | Prod | Traduce eventos de identidad a HL7v2↔FHIR para HCE y vincula resultados en LIS | Los legados hablan HL7 v2; el EMPI habla FHIR/eventos | A3M-004: adaptador desacoplado, serverless, en la nube del dominio clínico |
| **Azure Functions (Adaptador Financiero)** | Prod | Propaga `patient.merged` al ERP y Portal de Pagos (EMPI-ID activo para facturar) | Facturar bajo el EMPI-ID correcto elimina inconsistencias de cobro | Mismo patrón adaptador; concordancia financiera (Pagos en Azure) |
| **Azure Container Instance / Function HTTP (mTLS simplificado)** | Demo | Consumidor que **simula** la propagación a HCE/LIS/ERP | Demostrar que el evento cruza a Azure y se consume | APIM deshabilitado en demo (ahorra tiempo/costo); un contenedor 0.5 vCPU basta para el consumidor |

---

## 4. GCP — Imágenes y Analítica

| Componente Infra | Ambiente | Para qué sirve | Razón de ser | Por qué se escogió |
|---|---|---|---|---|
| **Cloud Healthcare API (FHIR Store + DICOM Store)** | Prod | Etiqueta estudios DICOM con el EMPI-ID → unifica imágenes inter-sede | A3M-006: sin identificador común, las imágenes siguen fragmentadas por sede | A3M-005: FHIR/DICOM nativos; concordancia (PACS réplica ya en GCP) |
| **Orthanc (DICOM OSS) + HAPI FHIR** | Demo | Mismos FHIR + DICOM store, en versión OSS | Demostrar el vínculo imagen↔EMPI-ID sin el costo de Healthcare API | OSS de referencia en salud; misma topología, bajo costo |
| **BigQuery (Vista 360° + Batch Matching)** | Prod | Vista 360° materializada + ejecuta el batch Splink de deduplicación | La analítica y la deduplicación masiva son workloads analíticos | A3M-005/009: concordancia analítica (Data Lakehouse en GCP); Splink serverless sobre BigQuery |
| **DuckDB** | Demo | Mismo backend analítico + Splink, embebido | Correr el batch de deduplicación en local/lab | A3M-009: Splink es **backend-swappable** → mismo código en DuckDB (demo) y BigQuery (prod) |
| **Splink (record linkage)** | Demo + Prod | Deduplicación batch probabilística (modelo Fellegi-Sunter) sobre el corpus | Resolver los 126k duplicados históricos (INI-01) con precisión/recall medibles | A3M-009: librería de linkage ya hecha, serverless, sin clúster Spark que operar |
| **Cloud Run (consumidor)** | Demo + Prod | Mantiene vivo el hilo consumidor de Kafka que alimenta Healthcare API/BigQuery | GCP necesita un consumidor de los eventos de identidad | Serverless con `min_instances=1` (para no perder el hilo Kafka) |
| **Conector VPC Access** | Prod | Permite a Cloud Run alcanzar el bus por red privada | Consumo cross-cloud por enlace privado, no público | Necesario para que Cloud Run llegue al bus sin exponerlo |

---

## 5. Bus de eventos (backbone neutral)

| Componente Infra | Ambiente | Para qué sirve | Razón de ser | Por qué se escogió |
|---|---|---|---|---|
| **Confluent Cloud (Kafka gestionado)** | Prod | Propaga eventos `identity.patient.*` a los 3 dominios (Azure/GCP/legados) de forma asíncrona | La identidad debe llegar a todos los dominios sin acoplar el core a ellos | A3M-008: Kafka **neutral anti-lock-in**; el acoplamiento es al protocolo, no a la nube; PrivateLink a 3 nubes |
| **Redpanda (1 contenedor)** | Demo | Mismo bus Kafka, self-hosted en un contenedor | Demostrar la propagación cross-cloud sin el costo de Confluent | **Mismo protocolo Kafka** → el contrato de la demo es el de producción (solo cambia el broker) |
| **Topics + DLQ por consumidor** | Demo + Prod | Encolan eventos y capturan los no procesables tras reintentos | Garantía de entrega ante consumidores caídos (equivalente a SQS DLQ) | Patrón estándar Kafka; tolerancia a fallos de Azure/GCP |

---

## 6. Conectividad cross-cloud

| Componente Infra | Ambiente | Para qué sirve | Razón de ser | Por qué se escogió |
|---|---|---|---|---|
| **Direct Connect / VPN (on-prem ↔ AWS)** | Prod | Enlace privado para que Admisión on-prem llegue al core en AWS por mTLS | El hot path de admisión no debe ir por internet público ni cruzar nubes | A3M-003: entrada interna directa al core (RNF-01) |
| **VPN Gateways cross-cloud (stack `40-xcloud-net`)** | Prod | Enlazan AWS↔Azure↔GCP de forma privada | Propagar eventos entre nubes sin exponerlos a internet | Enlaces privados (PrivateLink/PSC) para el consumo cross-cloud |
| **Bus público con TLS (sin VPN)** | Demo | Misma propagación cross-cloud, por conectividad pública cifrada | Evitar el gateway VPN de Azure (~27 min de creación) en la demo | El C4 lo contempla: "en el lab basta conectividad pública con TLS"; el flujo funcional es idéntico |

---

## 7. Observabilidad (transversal, stack `50-observability`)

| Componente Infra | Ambiente | Para qué sirve | Razón de ser | Por qué se escogió |
|---|---|---|---|---|
| **OpenTelemetry (OTel)** | Demo + Prod | Instrumenta el código para emitir trazas/métricas del flujo alta/merge | Ver el camino de una request a través de las 3 nubes (RNF-06) | Estándar abierto, agnóstico de proveedor; coherente con la neutralidad del diseño |
| **Jaeger** | Demo + Prod | Trazabilidad distribuida: visualiza el recorrido cross-cloud de cada evento | Diagnosticar latencia y fallos en un flujo multicloud | OSS estándar de tracing; corre en 1 tarea Fargate |
| **Grafana** | Demo + Prod | Dashboards de métricas: P95, profundidad de colas, tasa de duplicados (RF-07) | Operar por SLOs y disparar alertas | OSS estándar; misma tarea Fargate que Jaeger (forma mínima) |

---

## 8. Capa de aplicación y datos de prueba (código, no infra cloud)

| Componente | Ambiente | Para qué sirve | Razón de ser | Por qué se escogió |
|---|---|---|---|---|
| **PatientAggregate** | Demo + Prod | Agregado DDD que encapsula las reglas de identidad y emite eventos | Núcleo del Event Sourcing: toda mutación pasa por aquí | A3M-007: DDD + Event Sourcing conservados de la Alt. 3 |
| **Golden Record (proyección)** | Demo + Prod | Vista de lectura del estado actual del paciente, reconstruida de los eventos | Consultar identidad sin reproducir eventos en cada lectura (CQRS) | Proyección materializada; separa lectura de escritura |
| **Seeder de datos sintéticos (Faker `es_PE`)** | Demo | Genera pacientes/duplicados sintéticos peruanos para poblar la demo | Probar sin datos reales de pacientes | Cumple Ley 29733 por diseño (RNF-07/CA-05.4): ningún dato real entra |
| **UI de demo (Streamlit)** | Demo | Interfaz para ejecutar y visualizar el flujo E1–E4 | Demostrar el golden path de punta a punta a evaluadores | Rápida de construir; suficiente para la demo, no es UI de producción |

---

## 9. Resumen de sustituciones Demo ↔ Prod (vista rápida)

| Capacidad | Producción | Demo/Lab | Contrato compartido |
|---|---|---|---|
| Event Store | RDS PostgreSQL | Postgres (contenedor/free-tier) | Mismo esquema append-only |
| Índice de matching | **OpenSearch/Elasticsearch** | pg_trgm | Misma interfaz de blocking |
| Batch dedup | Splink @ BigQuery | Splink @ DuckDB | Mismo código Splink (swappable) |
| Vista 360° | BigQuery | DuckDB / BigQuery sandbox | Misma consulta analítica |
| Imágenes | Cloud Healthcare API | Orthanc + HAPI FHIR | FHIR + DICOM |
| Bus | Confluent Cloud | Redpanda (1 contenedor) | Mismo protocolo Kafka |
| Cache | ElastiCache Redis | Redis (contenedor) | Mismo protocolo Redis |
| Perímetro salida | Azure APIM mTLS | Azure Function/Container HTTP | Mismos eventos consumidos |
| Conectividad cross-cloud | Direct Connect / VPN privada | Bus público con TLS | Mismo flujo de eventos |
| Cifrado | KMS CMK propia | Clave gestionada por AWS | Cifrado en reposo activo |

> **Idea de una línea para recordar:** *la demo cambia el "cómo se implementa" (servicio ligero/OSS), nunca el "qué hace" ni "dónde vive" (misma topología tri-cloud concordante).*

---

*Documento de Hito 3 — Hacksheet de Infraestructura de la Alternativa 3 Mejorada | Iniciativa EMPI | Clínica SanaRed Integrada*
*Hoja de referencia para el equipo. Fuentes: `03_..._Multicloud_Concordante.md` (§5 perfiles), `99_..._Analisis_Optimizacion_Recursos.md` (stacks IaC 10–50) y los ADR-A3M-001…011.*
