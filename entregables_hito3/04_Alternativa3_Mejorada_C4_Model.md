# C4 Model — Alternativa 3 Mejorada (EMPI Multicloud Concordante)
## Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada | Hito 3

> **Qué es este documento:** el **modelo C4** de la Alternativa 3 Mejorada y su explicación (Contexto, Contenedores, Componentes y Despliegue), extraído de `03_Alternativa3_Mejorada_Multicloud_Concordante.md`. La fuente **renderable** en Structurizr está en los archivos `.dsl` referenciados abajo; aquí se muestran las vistas en Mermaid con su explicación.

---

## Archivos Structurizr DSL (fuente renderable)

| Archivo | Vistas que genera |
|---|---|
| [`Alt3M_C4_Model.dsl`](Alt3M_C4_Model.dsl) | **Completo**: C1 Contexto · C2 Contenedores · C3 Componentes (EMPI Core) · C4 Despliegue multicloud |
| [`Alt3M_C4_Model_resumido.dsl`](Alt3M_C4_Model_resumido.dsl) | **Resumido**: C1 Contexto · C2 Contenedores (para una diapositiva) |

**Cómo renderizar:** con Structurizr Lite (`docker run -it --rm -p 8080:8080 -v "<ruta>/entregables_hito3:/usr/local/structurizr" structurizr/lite` → `http://localhost:8080`) o pegando el DSL en el editor de structurizr.com.

---

## Nivel 1 — Diagrama de Contexto

Sitúa el **EMPI** como sistema en foco frente a sus actores (paciente, admisionista, médico, radiólogo, operador de datos) y los **6 sistemas existentes** de SanaRed con los que se integra sin reemplazarlos.

```mermaid
graph TB
    PAC["👤 Paciente"]
    ADM["👤 Admisionista"]
    MED["👤 Médico"]
    RAD["👤 Médico Radiólogo"]
    OPD["👤 Operador Gobierno de Datos"]

    EMPI["🟢 EMPI — Identidad Unificada de Pacientes\n(EMPI-ID · Matching · Golden Record 360°)"]

    HCE["HCE Oracle\n(on-prem · HL7 v2)"]
    PORTAL["Portal de Pacientes\n(AWS/RDS)"]
    AGENDA["Agenda SaaS"]
    LIS["LIS\n(Azure SQL)"]
    PACS["PACS\n(local + GCP)"]
    ERP["ERP Facturación\n(nube privada)"]

    PAC -->|"se registra / consulta"| PORTAL
    ADM -->|"admite pacientes"| EMPI
    MED -->|"consulta vista 360°"| EMPI
    RAD -->|"consulta imágenes inter-sede"| PACS
    OPD -->|"revisa fusiones"| EMPI

    PORTAL -->|"valida/crea identidad (FHIR $match)"| EMPI
    AGENDA -->|"valida identidad"| EMPI
    EMPI -->|"EMPI-ID (ADT^A28/A40)"| HCE
    EMPI -->|"vincula resultados al EMPI-ID"| LIS
    EMPI -->|"etiqueta estudios con EMPI-ID"| PACS
    EMPI -->|"EMPI-ID activo para facturar"| ERP
```

**Lectura:** el EMPI recibe identidad desde los canales (Portal, Agenda, Admisión) y **propaga el EMPI-ID** a los sistemas clínicos y administrativos (HCE, LIS, PACS, ERP), cada uno en su protocolo nativo (HL7 v2, FHIR, DICOM).

---

## Nivel 2 — Diagrama de Contenedores (multicloud concordante)

Muestra los contenedores del EMPI **agrupados por nube según concordancia de dominio**: el paciente en AWS, lo clínico/financiero en Azure, imágenes/analítica en GCP, y el bus como pieza transversal neutral.

```mermaid
graph TB
    subgraph AWS["☁️ AWS — Dominio del PACIENTE (concuerda con Portal de Pacientes)"]
        APIGW["API Gateway + WAF\n(canal paciente · público)"]
        APIMTLS["API GW privado / ALB\n(mTLS interno · sistemas internos)"]
        CORE["EMPI Core / PatientAggregate\n(FastAPI · ECS Fargate)\nCommands + Matcher tiempo real"]
        SEARCH["Amazon OpenSearch / Elasticsearch\n(índice de matching · blocking a escala)"]
        REDIS["ElastiCache Redis\n(cache de identidad · lookup DNI)"]
        ES[("Amazon RDS PostgreSQL\npatient_events (append-only)\n+ golden_record_view")]
    end

    subgraph AZURE["☁️ Azure — Integración CLÍNICA y FINANCIERA (concuerda con LIS + Pagos)"]
        APIM["APIM (mTLS)\nsalida a legados"]
        ADCLI["Adaptadores Clínicos\n(HCE HL7v2↔FHIR · LIS)\nAzure Functions"]
        ADFIN["Adaptador Financiero\n(ERP · Portal de Pagos)\nAzure Functions"]
    end

    subgraph GCP["☁️ GCP — IMÁGENES y ANALÍTICA (concuerda con PACS + Salud Ocup.)"]
        HCAPI["Cloud Healthcare API\nFHIR Store + DICOM Store\n(vincula PACS al EMPI-ID)"]
        BQ["BigQuery\nVista 360° + Batch Matching (Splink)"]
    end

    subgraph NEUTRAL["🔗 Backbone neutral (portable)"]
        BUS["Bus de eventos Kafka-compatible\n(Confluent / Redpanda)\ntopics identity.patient.*"]
    end

    subgraph ONPREM["🏥 On-premises Lima"]
        ADMIS["Módulo de Admisión\n(por sede · opera sobre HCE)"]
        HCE["HCE Oracle (sin cambios)"]
        PACSL["PACS local por sede"]
    end

    APIGW --> CORE
    ADMIS -->|"mTLS · Direct Connect/VPN"| APIMTLS
    APIMTLS --> CORE
    ADMIS -.->|"opera sobre HCE"| HCE
    CORE --> REDIS
    CORE --> SEARCH
    CORE --> ES
    CORE -->|publica eventos| BUS
    BUS --> ADCLI
    BUS --> ADFIN
    BUS --> HCAPI
    ADCLI --> APIM
    APIM -->|"ExpressRoute/VPN"| HCE
    HCAPI -->|"EMPI-ID en tags DICOM"| PACSL
    HCAPI --> BQ
    ES -.->|datos de identidad| BQ

    style AWS fill:#e3f2fd,stroke:#1565c0
    style AZURE fill:#e8eaf6,stroke:#283593
    style GCP fill:#e8f5e9,stroke:#1b5e20
    style NEUTRAL fill:#fff8e1,stroke:#f57f17
```

### Explicación del placement — QUÉ vs. DÓNDE

Cada componente resulta de **dos decisiones separadas**: el **QUÉ** (qué tecnología) y el **DÓNDE** (en qué nube). La mayoría se ubica por **concordancia de dominio**; hay dos matices —el batch (QUÉ por complejidad, DÓNDE por concordancia) y el bus (neutralidad; la concordancia no aplica)—.

| Componente | QUÉ (tecnología) — motivo | DÓNDE (nube) — motivo | Regla dominante |
|---|---|---|---|
| **Núcleo identidad + Event Store** | RDS PostgreSQL (Event Sourcing relacional) — *reduce complejidad + reutiliza RDS existente* | **AWS** — *concordancia (dominio paciente)* | Concordancia |
| **Índice matching tiempo real** | OpenSearch/Elasticsearch — *volumetría / escala* | **AWS** — *concordancia (paciente, junto al core)* | Concordancia + volumetría |
| **Batch de deduplicación** | Splink — *complejidad + portabilidad (backend-swappable)* | **GCP / BigQuery** — *concordancia (analítica)* | **Mixto**: QUÉ=complejidad · DÓNDE=concordancia |
| **Vista 360°** | BigQuery — *analítica materializada* | **GCP** — *concordancia (analítica)* | Concordancia |
| **Imágenes (PACS↔EMPI)** | Cloud Healthcare API (FHIR+DICOM) — *nativo de salud* | **GCP** — *concordancia (imágenes)* | Concordancia |
| **Integración clínica y financiera (salida)** | Adaptadores + APIM mTLS (perímetro de **salida** a legados) | **Azure** — *concordancia (LIS + Portal de Pagos)* | Concordancia |
| **Perímetro de entrada — paciente (público)** | API Gateway + WAF | **AWS** — *concordancia (canal de paciente)* | Concordancia |
| **Perímetro de entrada — sistemas internos** | API GW privado / ALB + mTLS (Direct Connect/VPN) | **AWS** — *entrada al core sin salto cross-cloud (RNF-01)* | Dirección de tráfico (ADR-A3M-003) |
| **Bus de eventos** | Kafka neutral (Confluent/Redpanda) — *anti-lock-in* | **Transversal** (junto al productor solo por latencia) | **Neutralidad** — concordancia NO aplica |

---

## Nivel 3 — Componentes del EMPI Core

Descompone el contenedor **EMPI Core / PatientAggregate** (AWS · FastAPI/ECS Fargate). Los componentes y sus relaciones están definidos en la vista `C3_ComponentesCore` del [`Alt3M_C4_Model.dsl`](Alt3M_C4_Model.dsl).

```mermaid
graph TB
    GW["Perímetro AWS\n(WAF público · mTLS interno)"]
    subgraph CORE["EMPI Core / PatientAggregate (AWS)"]
        API["API REST / FHIR\n(Patient + operación match PDQm)"]
        CMD["Command Handler\n(Register · Merge · RevertMerge\nDeactivate · ConfirmDistinct · UpdateContact)"]
        MATCH["Real-Time Matcher\n(cache → blocking → scoring)"]
        RULES["Domain Rules\n(umbrales 0.95/0.85 configurables)"]
        PROJ["Projector\n(construye golden_record_view)"]
        PUB["Event Publisher"]
    end
    CACHE["ElastiCache Redis"]
    SEARCH["Índice OpenSearch/Elasticsearch"]
    ES[("Event Store\nRDS PostgreSQL")]
    BUS["Bus de eventos\n(Kafka)"]

    GW --> API
    API --> CMD
    API --> MATCH
    MATCH --> CACHE
    MATCH --> SEARCH
    CMD --> RULES
    CMD --> ES
    CMD --> PUB
    PUB --> BUS
    PROJ --> ES
```

**Componentes:**
- **API REST / FHIR** — expone el recurso `Patient` y la operación de *match* (IHE PDQm).
- **Command Handler** — ejecuta los 6 commands de dominio (`RegisterPatient`, `MergeRecords`, `RevertMerge`, `DeactivateRecord`, `ConfirmDistinct`, `UpdateContact`).
- **Real-Time Matcher** — estrategia de 3 pasos con *early-exit*: cache (Redis) → blocking (OpenSearch) → scoring probabilístico.
- **Domain Rules** — umbrales 0.95/0.85 y reglas de precedencia, configurables en caliente.
- **Projector** — construye la proyección `golden_record_view` desde los eventos (CQRS).
- **Event Publisher** — publica los eventos de dominio al bus neutral.

---

## Nivel 4 — Despliegue (multicloud concordante)

La vista de despliegue completa (nodos AWS / Azure / GCP / Confluent / On-premises con cada contenedor en su nube) está en la vista `C4_Despliegue` del [`Alt3M_C4_Model.dsl`](Alt3M_C4_Model.dsl). A continuación, el detalle del componente cuyo despliegue tiene matices propios: el **bus de eventos neutral**.

### Despliegue del bus de eventos neutral (producción y demo)

**Aclaración clave:** "neutral" es **lógico**, no físico. El bus **corre en algún sitio**; lo neutral es que el acoplamiento es al **protocolo Kafka**, no a la mensajería propietaria de una nube — se puede mover el broker (Confluent → MSK → Redpanda) **sin tocar el código** de productores ni consumidores.

**Opciones de producción:**

| Opción | Qué es | Neutralidad | Ops |
|---|---|---|---|
| **Confluent Cloud** *(recomendada)* | Kafka gestionado sobre AWS/Azure/GCP; PrivateLink a las 3 nubes + *cluster linking* | ✅ Alta | Baja (managed) |
| **Redpanda / Kafka en Kubernetes** | Broker en EKS/AKS/GKE (operador) | ✅ Alta | Media-alta |
| **AWS MSK / Azure Event Hubs (Kafka)** | Kafka gestionado atado a una nube | 🟡 Media (clientes portables por protocolo; broker no) | Baja |

**Colocación física (producción):** el bus vive **junto a su productor principal** (EMPI Core en AWS), porque publicar es el camino caliente (cada alta/merge publica un evento). Los consumidores en Azure y GCP se conectan como **consumidores remotos** por enlaces privados (AWS PrivateLink / Azure Private Link / GCP Private Service Connect). El consumo cross-cloud es **asíncrono y tolerante** (propagación de identidad, no el camino crítico de admisión) → el salto entre nubes es aceptable.

```mermaid
graph LR
    CORE["EMPI Core\n(productor · AWS)"]
    BUS["Kafka neutral\n(Confluent Cloud · región AWS)"]
    subgraph AZ["Azure — consumidores"]
        ADC["Adaptadores clínicos/financieros"]
    end
    subgraph GC["GCP — consumidores"]
        HC["Cloud Healthcare API"]
    end
    CORE -->|"publica (local, baja latencia)"| BUS
    BUS -->|"Private Link (async)"| ADC
    BUS -->|"Private Service Connect (async)"| HC
```

> Colocarlo en la región AWS **no lo vuelve "de AWS"**: sigue siendo neutral porque habla Kafka. Si el core migrara a otra nube, se mueve el cluster Confluent **sin cambiar el código** de productores/consumidores.

**Perfil demo/lab:** Redpanda como **1 contenedor** junto al EMPI Core en AWS (módulo `/neutral-bus` del IaC). Mismo protocolo Kafka → el contrato de la demo es el de producción. Los consumidores (Azure Functions, contenedores GCP) se suscriben remotamente; en el lab basta conectividad pública con TLS, sin los enlaces privados de producción.

**Seguridad y HA (producción):** SASL/mTLS + ACLs por topic; TLS en tránsito; replicación factor 3 multi-AZ (gestionada por Confluent); retención de topics + **DLQ por consumidor** (equivalente Kafka de las SQS DLQ de la Alt. 3 original).

---

*Documento de Hito 3 — C4 Model de la Alternativa 3 Mejorada | Iniciativa EMPI | Clínica SanaRed Integrada*
*Extraído de `03_Alternativa3_Mejorada_Multicloud_Concordante.md` · Fuente renderable: `Alt3M_C4_Model.dsl` y `Alt3M_C4_Model_resumido.dsl`*
