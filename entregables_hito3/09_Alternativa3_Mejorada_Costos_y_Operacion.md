# Documento de Costos y Operación — Alternativa 3 Mejorada (EMPI Multicloud, Perfil Producción)
## Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada | Hito 3

> **Qué es este documento:** el análisis de **costos (CapEx / OpEx)** y el **modelo de operación** de la Alternativa 3 Mejorada, dimensionado sobre el **perfil de producción** (componentes gestionados a escala), **no** sobre el perfil demo/lab.
>
> **Rigor de las cifras (leer antes que nada):** este documento separa dos tipos de números que NO deben mezclarse:
> - **Costos de infraestructura cloud (§5):** anclados en **precios de lista publicados** (AWS/Azure/GCP), con **cálculo unitario auditable** (precio_unitario × cantidad × 730 h) y **fuente + fecha** por línea. Son verificables.
> - **Costos organizacionales (§4 y §5.7):** construcción del sistema y personal de operación. **No son precios cloud y no se pueden "verificar" en ninguna web** — dependen de las tarifas, el equipo y el alcance de SanaRed. Se presentan como **rangos ilustrativos / parámetros a definir**, explícitamente marcados, no como cifras firmes.
>
> **Precios tomados de fuentes públicas en julio 2026, región AWS us-east-1 (ver §10 Fuentes y método).** Los precios cambian; reconfirmar contra la calculadora oficial antes de presupuestar.

---

## 1. Componentes de producción considerados (no demo)

Se costean los componentes del **perfil producción** de la §5 del documento concordante, ubicados por **concordancia de dominio** (ADR-A3M-001):

| Plano / Nube | Componente de producción | Servicio gestionado | Rol |
|---|---|---|---|
| **AWS — Paciente** | EMPI Core / PatientAggregate | ECS Fargate (FastAPI) | Identidad, matching tiempo real, commands |
| | Event Store + Golden Record | Amazon RDS PostgreSQL Multi-AZ | Eventos append-only + proyecciones |
| | Índice de matching (blocking a escala) | **Amazon OpenSearch/Elasticsearch** | Blocking fuzzy a alta volumetría (ADR-A3M-011) |
| | Cache de identidad | ElastiCache Redis (HA) | Lookup DNI de baja latencia |
| | Perímetro público (paciente) | API Gateway + WAF + NLB | Entrada pública con protección de borde |
| | Perímetro interno (admisión/agenda) | ALB privado + mTLS | Entrada de sistemas internos (ADR-A3M-003) |
| | Cifrado / red | KMS CMK, VPC, NAT Gateway | PII cifrado, aislamiento de red |
| **Azure — Clínico/Financiero** | Perímetro de salida a legados | **Azure API Management (mTLS)** | Salida gobernada a HCE/LIS/ERP |
| | Adaptadores clínico y financiero | Azure Functions (Premium/VNET) | HL7v2↔FHIR, ERP/Pagos |
| **GCP — Imágenes/Analítica** | Imágenes (PACS↔EMPI-ID) | **Cloud Healthcare API** (FHIR+DICOM) | Vincula estudios al EMPI-ID |
| | Vista 360° + batch dedup | **BigQuery** + Splink | Analítica materializada + linkage |
| | Cómputo consumidor | Cloud Run (min 1) | Consumidor de eventos cross-cloud |
| **Neutral — Bus** | Bus de eventos | **Confluent Cloud (Kafka gestionado)** | Propagación cross-cloud, anti-lock-in |
| **Cross-cloud** | Enlaces privados | Direct Connect / VPN + PrivateLink / PSC | Conectividad privada AWS↔Azure↔GCP |
| **Transversal** | Observabilidad | OTel + Jaeger + Grafana (Fargate) | Trazas, métricas, logs (RNF-06) |

> **Diferencia con el perfil demo (excluido de este costeo):** el laboratorio usa pg_trgm en vez de OpenSearch, Redpanda de 1 contenedor en vez de Confluent, Orthanc/HAPI FHIR en vez de Cloud Healthcare API, DuckDB en vez de BigQuery, y bus público con TLS en vez de enlaces privados. Esos componentes son **más baratos por diseño** y **no** representan el costo de operar a escala productiva.

---

## 2. Marco de costeo: CapEx vs. OpEx en la nube

En una arquitectura mayormente **PaaS/SaaS gestionada**, el gasto se concentra en **OpEx** (pago por uso y suscripciones). El **CapEx** no desaparece: se traslada a la **inversión inicial de habilitación** (construcción, migración, conectividad, seguridad, capacitación) y a los **prepagos de capacidad reservada**.

| Categoría | Definición aplicada al EMPI | ¿Verificable con precio de lista? |
|---|---|---|
| **CapEx** (inversión, una vez) | Desembolsos iniciales para dejar la plataforma operativa | ❌ Mayormente **no** (es esfuerzo/servicios profesionales, ver §4) |
| **OpEx infra** (recurrente) | Costo mensual de los servicios cloud | ✅ **Sí** — precios de lista, ver §5 |
| **OpEx personal** (recurrente) | Equipo que opera la plataforma | ❌ **No** (depende de SanaRed, ver §5.7) |

---

## 3. Supuestos de dimensionamiento

| Supuesto | Valor | Fuente |
|---|---|---|
| Volumen de admisión | ~6,000 registros/día (5,200 citas + 780 urgencias) | Caso SanaRed |
| Volumen clínico asociado | ~3,400 exámenes/día (LIS) · ~920 estudios/día (PACS) | Caso SanaRed |
| Corpus histórico a deduplicar | 126,000 duplicados (INI-01) | Caso SanaRed |
| Objetivo de escala | Millones de Golden Records; picos de campaña ×2 | ADR-A3M-011 |
| **Región de precios** | **AWS us-east-1 · Azure East US · GCP us-east1** | Pricing estable/documentado; latencia a Perú ~60–80 ms |
| Variante regional | São Paulo / Brazil South / Santiago ≈ **+15–30%** sobre las cifras | Sobreprecio regional típico |
| Modelo de precios base | On-demand; optimizable con Savings Plans/Reserved 1 año | AWS/Azure/GCP |
| Horizonte de análisis | 3 años (TCO) | Planeamiento |
| Moneda / fecha | USD · precios consultados **julio 2026** | §10 Fuentes |

---

## 4. CapEx — Inversión inicial (insumos organizacionales, NO precios cloud)

> ⚠️ **Estas cifras no son precios cloud verificables.** Son estimaciones de **esfuerzo y servicios profesionales** que dependen de las tarifas del proveedor/equipo que ejecute el proyecto. Se dan como **rango ilustrativo** para dimensionar el orden de magnitud; SanaRed debe reemplazarlas con cotizaciones reales.

| # | Ítem | Naturaleza | Rango ilustrativo (USD) |
|---|---|---|---|
| C1 | Diseño e implementación (IaC + servicios + integración + QA) | Esfuerzo de ingeniería | 60,000 – 100,000 |
| C2 | Migración e ingesta inicial (126k duplicados + reconciliación) | Esfuerzo + cómputo puntual | 10,000 – 20,000 |
| C3 | Conectividad cross-cloud (instalación Direct Connect, borde on-prem) | Servicio + equipamiento | 5,000 – 12,000 |
| C4 | Seguridad inicial (PIA Ley 29733, pentest, PKI mTLS) | Servicios especializados | 8,000 – 16,000 |
| C5 | Capacitación (DDD/CQRS/ES + multicloud + FinOps) | Servicio | 6,000 – 14,000 |
| **—** | **Rango CapEx de habilitación** | | **~90,000 – 160,000** |
| C6 *(opcional)* | Prepago de capacidad reservada (Savings Plans 1 año) | Prepago cloud (sí verificable) | según §5, reduce OpEx ~15–20% |

> El grueso (C1) es **esfuerzo de ingeniería**, no hardware — coherente con una arquitectura cloud. La amplitud del rango refleja honestamente la incertidumbre: sin un alcance y un proveedor fijados, no hay un número único defendible.

---

## 5. OpEx de infraestructura — con cálculo unitario y fuente

> Cada línea = **precio_unitario publicado × cantidad × 730 h/mes**. Nivel de confianza: 🟢 precio de lista directo · 🟡 depende del uso real · 🔴 no publicado (rango de mercado).

### 5.1 AWS — Dominio del Paciente (us-east-1, on-demand)

| Componente | Sizing | Precio unitario | Mensual | Conf. |
|---|---|---|---|---|
| EMPI Core (Fargate) | 2 tareas × 2 vCPU/4 GB (baseline) | $0.04048/vCPU-h + $0.004445/GB-h | 2 × $0.0987/h × 730 = **~$144** | 🟢 |
| RDS PostgreSQL Multi-AZ | db.r6g.xlarge Multi-AZ + ~200 GB gp3 | ~$0.95/h Multi-AZ (≈2× single-AZ $0.45–0.48) + storage | ~$693 + ~$50 = **~$745** | 🟢 |
| OpenSearch | 3 × m6g.large.search + ~300 GB | $0.128/h (OD) | 3 × $93.4 + ~$37 = **~$317** | 🟢 |
| ElastiCache Redis | 2 × cache.r6g.large (HA) | $0.206/h | 2 × $150.4 = **~$301** | 🟢 |
| API Gateway (REST) | ~1 M req/mes | $3.50/M req | **~$4** | 🟢 |
| WAF | 1 ACL + ~5 reglas + 1 M req | $5 + $5 + ~$0.60 | **~$11** | 🟢 |
| NLB (perímetro público) | 1 + LCU | $0.0225/h + LCU | **~$25** | 🟢 |
| ALB (perímetro interno mTLS) | 1 + LCU | $0.0225/h + LCU | **~$25** | 🟢 |
| NAT Gateway | 1 + datos | $0.045/h + $0.045/GB | **~$50** | 🟡 |
| KMS | 1 CMK + uso | $1/mes + $0.03/10k req | **~$5** | 🟢 |
| CloudWatch | logs + métricas | $0.50/GB ingesta | **~$50** | 🟡 |
| **Subtotal AWS (baseline)** | | | **~$1,700 /mes** | |

> Con **autoscaling** en picos de campaña (más tareas Fargate, posible upsize de RDS/OpenSearch) el AWS sube a **~$2,000–2,400/mes** durante esos periodos. Con **Reserved/Savings 1 año** sobre RDS/OpenSearch/Redis/Fargate base, el baseline baja a **~$1,400/mes** (OpenSearch RI: $0.088/h; ver §10).

### 5.2 Azure — Integración Clínica y Financiera

| Componente | Sizing | Precio unitario | Mensual | Conf. |
|---|---|---|---|---|
| API Management (mTLS) | Standard (perímetro de salida) | ~$700/mes (tier) | **~$700** | 🟢 |
| Azure Functions (2 adaptadores) | Plan Premium EP1 (VNET/mTLS), compartido | ~$0.202/h (EP1) × 730 + ejecuciones | **~$150–300** | 🟡 |
| **Subtotal Azure** | | | **~$850 – 1,000 /mes** | |

### 5.3 GCP — Imágenes y Analítica

| Componente | Sizing | Precio unitario | Mensual | Conf. |
|---|---|---|---|---|
| Cloud Healthcare API | FHIR + DICOM store (metadatos/tags EMPI-ID) | Blob + Structured Storage por GB + operaciones (usage-driven) | **~$150–400** | 🟡 |
| BigQuery | Vista 360° + batch Splink | Storage $0.02/GB-mes + query on-demand $6.25/TB escaneado | **~$100–300** | 🟡 |
| Cloud Run (consumidor) | min 1 instancia pequeña | vCPU/mem por segundo | **~$50–100** | 🟡 |
| **Subtotal GCP** | | | **~$300 – 800 /mes** | |

> GCP es **usage-driven**: el rango depende del volumen real de imágenes/consultas. No es un precio de lista fijo; requiere validación con datos reales de tráfico.

### 5.4 Bus neutral y conectividad cross-cloud

| Componente | Sizing | Precio unitario | Mensual | Conf. |
|---|---|---|---|---|
| Confluent Cloud (Kafka) | Cluster Standard + throughput + PrivateLink | eCKU $/h + red $/GB + storage (**no itemizado públicamente**) | **~$1,000 – 2,000** | 🔴 |
| Direct Connect + VPN gateways | Puerto DX 1G + VPN Azure/GCP + endpoints | DX ~$0.30/h; VpnGw1 ~$0.19/h; HA VPN GCP ~$0.075/h/túnel | **~$450 – 650** | 🟡 |
| Egreso cross-cloud | Propagación asíncrona de eventos | $/GB egreso | **~$100 – 250** | 🟡 |
| **Subtotal Bus + Red** | | | **~$1,550 – 2,900 /mes** | |

> **Confluent es la línea menos transparente (🔴):** su modelo eCKU no publica la tarifa base exacta; el rango $1,000–3,000/mes para cargas Standard proviene de análisis de mercado, no de la página oficial. Es un candidato prioritario a **cotización directa**.

### 5.5 Observabilidad y soporte

| Componente | Sizing | Precio unitario | Mensual | Conf. |
|---|---|---|---|---|
| Observabilidad (OTel+Jaeger+Grafana) | 1 tarea Fargate (1 vCPU/2 GB) + NLB + storage | Fargate + LB | **~$80 – 150** | 🟢 |
| Planes de soporte | AWS Business (~10% del gasto AWS) + Azure/GCP Standard | % del gasto | **~$300 – 400** | 🟡 |
| **Subtotal Obs + Soporte** | | | **~$400 – 550 /mes** | |

### 5.6 OpEx de infraestructura — consolidado (rango honesto)

| Plano | USD/mes | Driver de incertidumbre |
|---|---|---|
| AWS (paciente) | ~1,700 – 2,400 | Autoscaling en picos |
| Azure (clínico/financiero) | ~850 – 1,000 | Ejecuciones de Functions |
| GCP (imágenes/analítica) | ~300 – 800 | Usage-driven (imágenes/consultas) |
| Bus + conectividad | ~1,550 – 2,900 | **Confluent (no publicado)** |
| Observabilidad + soporte | ~400 – 550 | % del gasto |
| **Total infraestructura** | **~$4,800 – 7,650 /mes** | |
| **Anualizado** | **~$58,000 – 92,000 /año** | |

**Referencia central:** **~$6,000/mes (~$72,000/año)** on-demand. Con Reserved/Savings 1 año sobre los componentes estables, el baseline se acerca a **~$5,000–5,500/mes (~$60,000–66,000/año)**.

> **Corrección vs. versión previa:** una estimación anterior de este documento situaba la infra en ~$6,500–8,300/mes. Tras anclar precios reales, el **baseline verificado es menor** (OpenSearch y Fargate estaban sobreestimados). El nuevo rango es más ancho **a propósito**, para reflejar la incertidumbre real de Confluent y de los servicios usage-driven de GCP en lugar de fingir precisión.

### 5.7 OpEx de operación (personal) — insumo organizacional, NO precio cloud

> ⚠️ **No es un precio verificable.** Depende de sueldos, país y % de dedicación de SanaRed. Rango ilustrativo (costo cargado, referencia Perú).

| Rol | Dedicación | Rango ilustrativo USD/mes |
|---|---|---|
| Ingeniería de plataforma / SRE (multicloud + IaC) | ~1.0–1.5 FTE | 3,500 – 5,000 |
| Operador de Gobierno de Datos (fusiones/calidad) | ~0.5 FTE | 1,500 – 2,000 |
| **Total operación (si es dedicado)** | | **~5,000 – 7,000 /mes** |

> Si se **apalanca el equipo de plataforma existente** de SanaRed, la porción atribuible al EMPI es menor. Este costo suele dominar el OpEx total, por eso se aísla y se marca como insumo del negocio.

---

## 6. Resumen consolidado y TCO a 3 años

> Se separa el **costo cloud verificable** de los **insumos organizacionales** para no mezclar cifras de distinta naturaleza.

| Concepto | Naturaleza | On-demand | Optimizado (Reserved 1 año) |
|---|---|---|---|
| **A. OpEx infra cloud (anual)** | 🟢 Verificable | ~$72,000 | ~$63,000 |
| **B. OpEx personal (anual)** | 🔴 Insumo org. | ~$60,000 – 84,000 | ~$60,000 – 84,000 |
| **C. CapEx habilitación (una vez)** | 🔴 Insumo org. | ~$90,000 – 160,000 | ~$105,000 – 175,000 (con prepago) |
| **TCO 3 años (solo cloud, A)** | 🟢 Verificable | **~$216,000** | **~$189,000** |
| **TCO 3 años (A + B + C, completo)** | Mixto | **~$490,000 – 650,000** | **~$465,000 – 625,000** |

> **Lectura honesta:**
> - Lo **verificable con precios reales** (infra cloud) ronda **~$72k/año / ~$216k a 3 años**. Es la cifra que puedes defender con fuentes.
> - El **TCO completo** (con construcción y personal) cae en **~$490k–650k a 3 años**, pero ese rango está dominado por **insumos organizacionales que SanaRed debe cotizar**, no por precios cloud.
> - Dentro del cloud, las palancas mayores son **Confluent + conectividad** (el precio de la multicloud real) y **RDS + OpenSearch** (datos e índice de matching).

---

## 7. Modelo de operación

### 7.1 Responsabilidad compartida (multicloud)

| Capa | Responsable | Nota |
|---|---|---|
| Hardware, hipervisor, red física | Proveedores (AWS/Azure/GCP) | Modelo de responsabilidad compartida |
| Servicios gestionados (RDS, OpenSearch, APIM, BigQuery, Healthcare API, Confluent) | Proveedor opera; SanaRed configura | Parcheo/HA gestionados por el proveedor |
| Aplicación EMPI, datos, IAM, mTLS, reglas WAF | **SanaRed (equipo de plataforma)** | Config, secretos, políticas, DR |
| Gobierno de datos (fusiones, calidad) | **Operador de Gobierno de Datos** | RF-07 |

### 7.2 Niveles de servicio (SLO/SLA)

| Indicador | Objetivo | Sustento |
|---|---|---|
| Latencia matching tiempo real | P95 ≤ 500 ms | RNF-01 · cache Redis + OpenSearch + core en AWS (sin salto cross-cloud en el hot path) |
| Disponibilidad del servicio de identidad | ≥ 99.9% | RNF-02 · Multi-AZ por servicio + Confluent replicación factor 3 |
| Propagación de eventos cross-cloud | Asíncrona, best-effort con reintento | Fuera del camino crítico; DLQ por consumidor |
| Consulta de auditoría | Traza nativa por eventos | RNF-03 · Event Sourcing (auditoría inmutable) |

### 7.3 Observabilidad

Stack **OTel + Jaeger + Grafana** (ya desplegado en el IaC, stack `50-observability`): trazas distribuidas del flujo de alta/merge, métricas de latencia P95, profundidad de colas del bus y de la DLQ, y tasa de duplicados residual (RF-07). Alertas ante P95 > umbral, error rate de adaptadores > 0% y duplicados > 2%.

### 7.4 Continuidad y recuperación (DR)

| Mecanismo | Enfoque |
|---|---|
| Backup / PITR | RDS con backups automáticos y point-in-time recovery |
| Reconstrucción de estado | **Event Store append-only** permite reproyectar el Golden Record (ventaja del Event Sourcing) |
| Alta disponibilidad | Multi-AZ en RDS/OpenSearch/Redis; bus con replicación factor 3 |
| Tolerancia cross-cloud | Si Azure/GCP no están disponibles, los eventos quedan retenidos en Kafka y se consumen al reconectar |

### 7.5 Seguridad operacional

Rotación de certificados mTLS (perímetro interno y salida a legados), rotación de la KMS CMK, gestión de reglas WAF, IAM de menor privilegio por servicio, datos sintéticos en no-producción (CA-05.4) y mantenimiento de la PIA (Ley 29733).

### 7.6 Gobierno de costos (FinOps)

| Práctica | Acción |
|---|---|
| Presupuestos y alertas | AWS Budgets / Azure Cost Management / GCP Budgets con alertas por umbral |
| Etiquetado | Tags por componente/entorno para atribuir costo (paciente/clínico/imágenes) |
| Compromisos | Savings Plans/Reserved en componentes estables (ver §5.6 optimizado) |
| Apagado selectivo | El patrón de flags del IaC (`enable_opensearch`, etc.) permite encender solo lo necesario en no-producción |
| Control de egreso | Propagación asíncrona y por lotes para acotar el egreso cross-cloud |

---

## 8. Palancas de optimización y riesgos de costo

| Palanca | Efecto | Referencia |
|---|---|---|
| Savings Plans/Reserved 1 año | −15–20% en cómputo/BD estables (OpenSearch OD $0.128→RI $0.088) | §5.1, §10 |
| Autoscaling del core (Fargate) | Paga picos de campaña solo cuando ocurren | RNF-05 |
| Tiering de almacenamiento (auditoría/imágenes) | Mueve histórico frío a clases baratas | RNF-07 |
| Confluent dimensionado por throughput real | Evita sobredimensionar el cluster | ADR-A3M-008 |

| Riesgo de costo | Mitigación |
|---|---|
| **Confluent no tiene precio de lista público** | Cotización directa antes de comprometer presupuesto; es la mayor incertidumbre del modelo |
| Egreso cross-cloud mayor al previsto | Propagación asíncrona/por lotes; monitoreo de tráfico entre nubes |
| GCP usage-driven variable | Validar con volumen real de imágenes/consultas antes de fijar el número |
| OpenSearch sobredimensionado | Ajuste de nodos por volumetría real; se conserva por escala (ADR-A3M-011), no por defecto |
| Personal de operación subestimado | Apalancar el equipo de plataforma existente; automatizar con IaC/CI-CD |

---

## 9. Trazabilidad con requerimientos

| Requerimiento | Cómo lo respalda este costeo/operación |
|---|---|
| **RNF-01** Latencia | Componentes del hot path (core+cache+OpenSearch) co-localizados en AWS; costeados en §5.1 |
| **RNF-02** Disponibilidad 99.9% | Multi-AZ + replicación factor 3, con su costo reflejado (RDS Multi-AZ, cluster HA) |
| **RNF-05** Escalabilidad | OpenSearch dedicado + autoscaling costeados para picos ×2 |
| **RNF-03/07** Seguridad y cumplimiento | KMS, mTLS, PIA, datos sintéticos — CapEx C4 + OpEx de seguridad operacional |
| **PT-02** Multinube gobernada | El costo de Confluent + enlaces privados es el precio explícito de la concordancia tri-cloud real |

---

## 10. Fuentes y método (precios verificados — julio 2026, us-east-1)

| Servicio | Precio unitario usado | Fuente | Confianza |
|---|---|---|---|
| AWS Fargate | $0.04048/vCPU-h · $0.004445/GB-h (x86, us-east-1) | [aws.amazon.com/fargate/pricing](https://aws.amazon.com/fargate/pricing/) | 🟢 |
| Amazon OpenSearch | m6g.large.search $0.128/h (OD) · $0.088/h (RI 1a) | [aws.amazon.com/opensearch-service/pricing](https://aws.amazon.com/opensearch-service/pricing/) | 🟢 |
| ElastiCache Redis | cache.r6g.large $0.206/h | [aws.amazon.com/elasticache/pricing](https://aws.amazon.com/elasticache/pricing/) | 🟢 |
| RDS PostgreSQL | db.r6g.xlarge base ~$0.45/h; Multi-AZ ≈ 2× | [aws.amazon.com/rds/postgresql/pricing](https://aws.amazon.com/rds/postgresql/pricing/) | 🟢 |
| Azure API Management | Standard ~$700/mes | [azure.microsoft.com/pricing/details/api-management](https://azure.microsoft.com/en-us/pricing/details/api-management/) | 🟢 |
| GCP Cloud Healthcare API | Blob + Structured Storage por GB + operaciones (usage-driven) | [cloud.google.com/healthcare-api/pricing](https://cloud.google.com/healthcare-api/pricing) | 🟡 |
| Confluent Cloud | eCKU no itemizado; rango de mercado $1,000–3,000/mes | [cloudzero.com/blog/confluent-cloud-pricing](https://www.cloudzero.com/blog/confluent-cloud-pricing/) · [confluent.io/confluent-cloud/pricing](https://www.confluent.io/confluent-cloud/pricing/) | 🔴 |

**Método:** para cada servicio con precio de lista, costo mensual = precio_unitario × cantidad × 730 h. Los servicios usage-driven (GCP) y no publicados (Confluent) se presentan como rangos con su nivel de confianza. Los costos organizacionales (CapEx §4, personal §5.7) **no** provienen de estas fuentes: son insumos que SanaRed debe cotizar.

**Advertencia:** los precios cloud cambian con frecuencia y varían por región, SKU final y descuentos por compromiso. Reconfirmar en la calculadora oficial de cada proveedor antes de usar estas cifras para un presupuesto formal.

---

*Documento de Hito 3 — Costos (CapEx/OpEx) y Operación de la Alternativa 3 Mejorada, perfil producción | Iniciativa EMPI | Clínica SanaRed Integrada*
*Precios de infraestructura anclados en fuentes públicas (julio 2026, us-east-1). Costos organizacionales presentados como rangos ilustrativos, no cotizaciones. Complementa `03_..._Multicloud_Concordante.md` (§5) y `99_..._Analisis_Optimizacion_Recursos.md`.*
