# Alternativa TO BE 1: EMPI Centralizado con API Gateway y Bus de Integración (ESB)

## Diagrama de Arquitectura — Mermaid

```mermaid
flowchart TD
    subgraph CANALES["🌐 Capa de Canales (Entrada de Identidad)"]
        direction LR
        PA["Portal AWS\n(RDS PostgreSQL)"]
        AS["Agenda Médica\nSaaS"]
        CC["Call Center\nCRM SaaS"]
        ADM["Módulos de Admisión\nx4 Clínicas (On-Prem)"]
        APP["App Móvil\n(GCP Cloud Run)"]
    end

    subgraph GATEWAY["🔐 Capa de Seguridad y Acceso"]
        direction LR
        APIGW["API Gateway\n(AWS API Gateway)\n- Rate Limiting\n- Auth JWT/OAuth2\n- Logging"]
        IAM["IAM Centralizado\n+ SSO + MFA\n(INI-03)"]
        APIGW <-->|"Token Validation"| IAM
    end

    subgraph EMPI_CORE["🧠 EMPI Core — Índice Maestro de Pacientes"]
        direction TB
        MS["Motor de Matching\n& Scoring\n(Algoritmo Probabilístico)"]
        GR["Golden Record\nEngine\n- Creación EMPI-ID\n- Estado del Registro\n- Reglas de Precedencia"]
        DUP["Deduplication\nService\n- Batch (INI-01)\n- Real-Time (INI-13)"]
        LV["Lifecycle\nManager\n- ACTIVO / INACTIVO\n- FUSIONADO / FALLECIDO"]
        MS --> GR
        GR --> DUP
        DUP --> LV
    end

    subgraph ESB["🔄 Bus de Integración (ESB)\n— Orquestador de Sincronización"]
        direction TB
        EVT["Event Bus\n(AWS EventBridge)\n- Publicación de cambios\n- Subscripción por sistema"]
        Q["Cola de Mensajería\n(Amazon SQS)\n- Retry con backoff\n- Dead Letter Queue"]
        TF["Transformador\nHL7v2 ↔ FHIR R4\n(INI-04 compatible)"]
        EVT --> Q
        Q --> TF
    end

    subgraph SISTEMAS_CLINICOS["🏥 Sistemas Clínicos Core"]
        direction LR
        HCE["HCE Oracle\n(On-Premises Lima)\n- Historia Clínica\n- Episodios"]
        LIS["LIS Azure SQL\n- Laboratorio\n- Resultados HL7"]
        PACS["PACS Local\n+ Réplica GCP\n- Imágenes DICOM"]
        ERP["ERP Facturación\n(Nube Privada Lima)"]
    end

    subgraph STORE["🗄️ Almacenamiento EMPI"]
        direction TB
        MDB["Master DB\n(Aurora PostgreSQL\nMulti-AZ)\n- Golden Records\n- EMPI-IDs"]
        CACHE["Cache Layer\n(ElastiCache Redis)\n- Lookup en tiempo real\n- TTL 5 min"]
        AUDIT["Audit Log Store\n(AWS CloudWatch +\nS3 Glacier)\n- Inmutable\n- 10 años"]
        MDB <--> CACHE
        MDB --> AUDIT
    end

    subgraph GOB["📊 Gobierno y Calidad de Datos"]
        direction LR
        DASH["Dashboard\nCalidad EMPI\n(INI-06a)"]
        BATCH["Scheduler Batch\n(AWS Step Functions)\n00:00-05:00"]
        ALERT["Alertas\nAutomáticas\n(> 2% duplicados)"]
        DASH --> ALERT
        BATCH --> DUP
    end

    %% Flujo principal de entrada
    CANALES -->|"HTTPS / REST\ncon EMPI-ID request"| APIGW
    APIGW -->|"Request autenticado\n+ claims de rol"| EMPI_CORE

    %% EMPI consulta y escribe en storage
    EMPI_CORE <-->|"Read / Write\nGolden Record"| STORE

    %% Propagación de cambios
    EMPI_CORE -->|"Evento de cambio\n(alta, fusión, update)"| ESB
    ESB -->|"Notificación\nFHIR Patient resource"| SISTEMAS_CLINICOS

    %% Sistemas clínicos también consultan directamente al EMPI
    SISTEMAS_CLINICOS -->|"Consulta EMPI-ID\nvía API FHIR R4"| APIGW

    %% Gobierno conectado al core
    GOB <-->|"Métricas y\nconsumo de logs"| EMPI_CORE
    GOB <-->|"Lectura de\naudit logs"| STORE

    %% Estilos
    classDef canal fill:#dbeafe,stroke:#3b82f6,color:#1e3a5f
    classDef gateway fill:#fef9c3,stroke:#ca8a04,color:#713f12
    classDef core fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef esb fill:#f3e8ff,stroke:#9333ea,color:#3b0764
    classDef clinico fill:#ffedd5,stroke:#ea580c,color:#7c2d12
    classDef store fill:#e0f2fe,stroke:#0284c7,color:#0c4a6e
    classDef gob fill:#fce7f3,stroke:#db2777,color:#831843

    class PA,AS,CC,ADM,APP canal
    class APIGW,IAM gateway
    class MS,GR,DUP,LV core
    class EVT,Q,TF esb
    class HCE,LIS,PACS,ERP clinico
    class MDB,CACHE,AUDIT store
    class DASH,BATCH,ALERT gob
```

---

## Diagrama de Flujo — Escenario: Alta de Paciente Nuevo en Tiempo Real

```mermaid
sequenceDiagram
    actor Admisionista
    participant Canal as Módulo Admisión (Sede)
    participant GW as API Gateway + IAM
    participant EMPI as EMPI Core
    participant Cache as Redis Cache
    participant DB as Aurora DB (Master)
    participant ESB as Event Bus (ESB)
    participant HCE as HCE Oracle
    participant Agenda as Agenda SaaS

    Admisionista->>Canal: Ingresa datos del paciente (DNI, nombre, FN)
    Canal->>GW: POST /empi/v1/patients {dni, nombre, fechaNac}
    GW->>GW: Valida token JWT + claims rol=ADMISIONISTA
    GW->>EMPI: Request autenticado

    EMPI->>Cache: Lookup por DNI hash
    alt DNI encontrado en cache
        Cache-->>EMPI: EMPI-ID existente (hit)
        EMPI-->>GW: 200 OK {empiId, existingRecord: true}
        GW-->>Canal: Golden Record existente devuelto
        Canal-->>Admisionista: Muestra ficha del paciente existente
    else DNI no encontrado en cache
        Cache-->>EMPI: Miss
        EMPI->>DB: SELECT por DNI en Golden Records
        alt Registro encontrado en DB
            DB-->>EMPI: Golden Record activo
            EMPI->>Cache: Warm cache con resultado
            EMPI-->>GW: 200 OK {empiId, existingRecord: true}
            GW-->>Canal: Golden Record existente devuelto
            Canal-->>Admisionista: Muestra ficha del paciente existente
        else No existe registro
            DB-->>EMPI: Not found
            EMPI->>EMPI: Ejecuta matching probabilístico\nsobre atributos biográficos
            alt Score >= 95% (posible duplicado exacto)
                EMPI-->>GW: 200 OK {empiId, flag: POSIBLE_DUPLICADO}
                GW-->>Canal: Alerta de posible duplicado
                Canal-->>Admisionista: Muestra ficha candidata para confirmación
            else Score < 85% (paciente nuevo)
                EMPI->>DB: INSERT nuevo Golden Record\nEstado: VERIFICADO / INCOMPLETO
                DB-->>EMPI: EMPI-ID generado
                EMPI->>Cache: Warm cache
                EMPI->>ESB: Publica evento PATIENT_CREATED
                ESB--)HCE: Notifica alta (FHIR Patient)
                ESB--)Agenda: Notifica alta (FHIR Patient)
                EMPI-->>GW: 201 Created {empiId, status: VERIFICADO}
                GW-->>Canal: Nuevo paciente registrado
                Canal-->>Admisionista: Alta exitosa — EMPI-ID asignado
            end
        end
    end
```

---

## Diagrama de Estados — Golden Record

```mermaid
stateDiagram-v2
    [*] --> INCOMPLETO : Alta con datos mínimos\n(sin correo o celular)
    [*] --> VERIFICADO : Alta con datos completos\n(DNI + nombre + FN)

    INCOMPLETO --> VERIFICADO : Enriquecimiento de datos\n(portal o admisión)
    VERIFICADO --> POSIBLE_DUPLICADO : Matching score\n85%-94%

    POSIBLE_DUPLICADO --> VERIFICADO : Operador confirma\nque son distintos
    POSIBLE_DUPLICADO --> INACTIVO_FUSIONADO : Operador confirma\nque es el mismo

    VERIFICADO --> INACTIVO_FUSIONADO : Fusión batch\n(score >= 95%)
    INACTIVO_FUSIONADO --> VERIFICADO : Reversión por\nerror confirmado

    VERIFICADO --> INACTIVO_FALLECIDO : Registro de\nfallecimiento
    INACTIVO_FUSIONADO --> [*] : Archivado\n(+10 años)
    INACTIVO_FALLECIDO --> [*] : Archivado\n(+10 años)
```
