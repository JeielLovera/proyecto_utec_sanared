# Alternativa TO BE 2: EMPI Federado con Domain-Driven Design y Event Sourcing

## Diagrama de Arquitectura — Mermaid

```mermaid
flowchart TD
    subgraph CANALES["🌐 Capa de Canales"]
        direction LR
        PA["Portal AWS\n(RDS PostgreSQL)"]
        AS["Agenda Médica\nSaaS"]
        CC["Call Center\nCRM SaaS"]
        ADM["Admisión On-Prem\nx4 Clínicas"]
        APP["App Móvil\n(GCP)"]
    end

    subgraph SECURITY["🔐 Seguridad Perimetral"]
        APIGW["API Gateway\n(Azure APIM)\n+ mTLS + OAuth2"]
        IAM["IAM / SSO\nFederado\n(INI-03)"]
        APIGW <-->|"Token + Claims"| IAM
    end

    subgraph IDENTITY_DOMAIN["🧠 Dominio de Identidad del Paciente\n(Identity Bounded Context)"]
        direction TB

        subgraph CMD["Commands (Escritura — CQRS)"]
            direction LR
            C1["RegisterPatient\nCommand"]
            C2["MergeRecords\nCommand"]
            C3["UpdateContact\nCommand"]
            C4["DeactivateRecord\nCommand"]
        end

        subgraph DOMAIN_CORE["Agregado: Golden Record"]
            direction TB
            AGG["PatientAggregate\n- EMPI-ID\n- Estado\n- Versión\n- Eventos pendientes"]
            RULES["Domain Rules\n- Validación DNI\n- Reglas de precedencia\n- Scoring thresholds"]
            AGG <--> RULES
        end

        subgraph EVT_STORE["Event Store (Event Sourcing)"]
            ES["Event Store\n(Azure Cosmos DB)\n- Secuencia inmutable\n- PatientRegistered\n- RecordsMerged\n- ContactUpdated\n- RecordDeactivated"]
        end

        CMD --> AGG
        AGG -->|"Append events"| ES
    end

    subgraph READ_SIDE["📖 Read Side — Proyecciones CQRS"]
        direction LR
        PROJ1["Proyección:\nGolden Record View\n(búsqueda rápida)\nAzure Cosmos DB"]
        PROJ2["Proyección:\nVista Longitudinal 360°\n(vista médica completa)\nAzure Synapse"]
        PROJ3["Proyección:\nDuplicates Index\n(matching en tiempo real)\nElasticsearch"]
        PROJ4["Proyección:\nAudit Trail\n(trazabilidad)\nAzure Monitor Logs"]
    end

    subgraph MATCHING["🔍 Servicio de Matching Distribuido"]
        direction TB
        RT["Real-Time Matcher\n(INI-13)\n- Elasticsearch fuzzy\n- Score probabilístico\n< 500 ms"]
        BATCH_SVC["Batch Deduplication\n(INI-01)\n- Azure Databricks\n- Procesamiento paralelo\n- 50K registros/hora"]
        REVIEW["Manual Review\nQueue\n(Azure Service Bus)\n- UI de revisión lado a lado"]
        RT --> REVIEW
        BATCH_SVC --> REVIEW
    end

    subgraph EVENT_BUS["📡 Bus de Eventos de Dominio\n(Azure Service Bus + Event Grid)"]
        direction LR
        EB_TOPICS["Topics por Dominio:\n- identity.patient.created\n- identity.patient.merged\n- identity.contact.updated\n- identity.record.deactivated"]
        DEAD["Dead Letter Queue\n+ Retry Policy\n(3 intentos, backoff exp.)"]
        EB_TOPICS --> DEAD
    end

    subgraph CONSUMERS["🏥 Consumidores de Dominio"]
        direction TB
        subgraph DOM_CLINICO["Dominio Clínico"]
            HCE["HCE Oracle\n(On-Prem)\nConsume: patient.created\npatient.merged"]
        end
        subgraph DOM_DIAG["Dominio Diagnóstico"]
            LIS["LIS Azure SQL\nConsume: patient.created"]
            PACS["PACS + GCP\nConsume: patient.created"]
        end
        subgraph DOM_FIN["Dominio Financiero"]
            ERP["ERP Facturación\nConsume: patient.merged\ncontact.updated"]
        end
        subgraph DOM_CANAL["Dominio Canal"]
            AGENDA["Agenda SaaS\nConsume: patient.created"]
            CRM_C["CRM SaaS\nConsume: contact.updated"]
        end
    end

    subgraph OBSERVABILITY["📊 Observabilidad y Gobierno"]
        direction LR
        DASH["Dashboard EMPI\n(Power BI / Grafana)\n- KPIs en tiempo real"]
        ALERT_SVC["Alerting Service\n- Tasa duplicados > 2%\n- Latencia > 500ms\n- Queue depth > 1000"]
        GOV["Governance Engine\n- Calidad del dato\n- Reglas de retención\n- Ley 29733 compliance"]
        DASH --> ALERT_SVC
        ALERT_SVC --> GOV
    end

    %% Flujo de entrada
    CANALES -->|"HTTPS/REST"| APIGW
    APIGW -->|"Comando autenticado"| CMD

    %% Event Sourcing: events → proyecciones
    ES -->|"Stream de eventos"| EVENT_BUS
    EVENT_BUS -->|"Proyectar eventos"| READ_SIDE

    %% Matching consume proyecciones
    PROJ3 --> RT
    ES --> BATCH_SVC

    %% Read side sirve queries
    PROJ1 -->|"EMPI-ID lookup"| APIGW
    PROJ2 -->|"Vista 360°"| APIGW

    %% Propagación a consumidores
    EVENT_BUS -->|"Subscripciones\npor dominio"| CONSUMERS

    %% Observabilidad transversal
    EVENT_BUS --> OBSERVABILITY
    IDENTITY_DOMAIN --> OBSERVABILITY

    %% Estilos
    classDef canal fill:#dbeafe,stroke:#3b82f6,color:#1e3a5f
    classDef security fill:#fef9c3,stroke:#ca8a04,color:#713f12
    classDef domain fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef read fill:#e0f2fe,stroke:#0284c7,color:#0c4a6e
    classDef matching fill:#f3e8ff,stroke:#9333ea,color:#3b0764
    classDef evtbus fill:#fce7f3,stroke:#db2777,color:#831843
    classDef consumer fill:#ffedd5,stroke:#ea580c,color:#7c2d12
    classDef obs fill:#f1f5f9,stroke:#64748b,color:#0f172a

    class PA,AS,CC,ADM,APP canal
    class APIGW,IAM security
    class C1,C2,C3,C4,AGG,RULES,ES domain
    class PROJ1,PROJ2,PROJ3,PROJ4 read
    class RT,BATCH_SVC,REVIEW matching
    class EB_TOPICS,DEAD evtbus
    class HCE,LIS,PACS,ERP,AGENDA,CRM_C consumer
    class DASH,ALERT_SVC,GOV obs
```

---

## Diagrama de Flujo — Escenario: Deduplicación y Fusión de Registros Duplicados

```mermaid
sequenceDiagram
    actor Operador as Operador Gobierno de Datos
    participant Sched as Azure Databricks\n(Batch Scheduler)
    participant ES as Event Store\n(Cosmos DB)
    participant ESearch as Elasticsearch Index\n(Duplicates Projection)
    participant Review as Manual Review Queue\n(Service Bus)
    participant UI as Review UI
    participant AGG as PatientAggregate\n(EMPI Core)
    participant EB as Event Bus\n(Service Bus Topics)
    participant HCE as HCE Oracle
    participant ERP as ERP Facturación

    Note over Sched: Ventana nocturna 00:00-05:00
    Sched->>ES: Lee eventos desde último checkpoint
    ES-->>Sched: Stream de PatientRegistered (lote nocturno)
    Sched->>ESearch: Consulta índice de candidatos a duplicado
    ESearch-->>Sched: Pares de candidatos con score probabilístico

    loop Para cada par de candidatos
        alt Score >= 95% → Merge automático
            Sched->>AGG: MergeRecords Command\n{sourceId, targetId, score, reason: AUTO}
            AGG->>AGG: Valida reglas de dominio\n(mismo DNI o alta coincidencia)
            AGG->>ES: Append RecordsMerged event\n{empiIdActivo, empiIdInactivo, score, timestamp}
            ES-->>EB: Publica RecordsMerged
            EB--)HCE: Notifica: redirigir episodios\nde EMPI-ID-inactivo a EMPI-ID-activo
            EB--)ERP: Notifica: consolidar\nfacturación bajo EMPI-ID-activo
        else Score 85%-94% → Revisión manual
            Sched->>Review: Encola par para revisión manual\n{record1, record2, score}
            Review-->>Operador: Notificación: casos pendientes
        else Score < 85% → Descartar
            Sched->>ES: Append NoMatchConfirmed event\n{id1, id2, score}
        end
    end

    Note over Operador,UI: Sesión de revisión manual
    Operador->>UI: Abre cola de revisión
    UI->>Review: GET /review/pending
    Review-->>UI: Lista de pares pendientes con score y atributos

    Operador->>UI: Selecciona par y compara registros lado a lado
    alt Operador confirma que son la misma persona
        Operador->>UI: Confirma merge + escribe justificación
        UI->>AGG: MergeRecords Command\n{sourceId, targetId, justification, operator: "jperez", reason: MANUAL}
        AGG->>ES: Append RecordsMerged event (manual)
        ES-->>EB: Publica RecordsMerged
        EB--)HCE: Notifica consolidación
        EB--)ERP: Notifica consolidación
        UI-->>Operador: Merge completado — EMPI-ID activo asignado
    else Operador confirma que son personas distintas
        Operador->>UI: Rechaza merge + escribe justificación
        UI->>AGG: ConfirmDistinct Command\n{id1, id2, justification}
        AGG->>ES: Append NoMatchConfirmed event (manual)
        ES-->>EB: No se publica cambio de identidad
        UI-->>Operador: Registros marcados como DISTINTOS
    end

    Note over Sched: Al finalizar el batch
    Sched->>Operador: Envía reporte: merges automáticos,\ncola manual, descartados, tasa residual
```

---

## Diagrama C4 — Nivel Contexto: Dominio de Identidad del Paciente

```mermaid
C4Context
    title Contexto del Sistema EMPI — Alternativa 2 (Federada / DDD)

    Person(admisionista, "Admisionista", "Registra y valida pacientes en sede")
    Person(medico, "Médico", "Consulta Golden Record y vista longitudinal 360°")
    Person(gobDatos, "Operador Gobierno de Datos", "Gestiona duplicados y calidad del EMPI")

    System(empi, "EMPI — Dominio de Identidad", "Índice Maestro Federado con Event Sourcing. Genera Golden Records, ejecuta matching y propaga identidad a toda la red.")

    System_Ext(hce, "HCE Oracle (On-Prem)", "Historia Clínica Electrónica")
    System_Ext(lis, "LIS Azure SQL", "Sistema de Laboratorio")
    System_Ext(agenda, "Agenda Médica SaaS", "Programación de citas")
    System_Ext(portal, "Portal Pacientes AWS", "Autogestión del paciente")
    System_Ext(erp, "ERP Facturación", "Ciclo de cobro y liquidación")
    System_Ext(iam, "IAM / SSO (INI-03)", "Autenticación y autorización centralizada")

    Rel(admisionista, empi, "Registra paciente / consulta identidad", "HTTPS REST / FHIR R4")
    Rel(medico, empi, "Consulta Golden Record 360°", "HTTPS REST / FHIR R4")
    Rel(gobDatos, empi, "Gestiona duplicados y revisa calidad", "UI Web / API Admin")

    Rel(empi, hce, "Publica: patient.created, patient.merged", "Azure Service Bus (FHIR)")
    Rel(empi, lis, "Publica: patient.created", "Azure Service Bus")
    Rel(empi, agenda, "Publica: patient.created, contact.updated", "Azure Service Bus")
    Rel(empi, erp, "Publica: patient.merged, contact.updated", "Azure Service Bus")
    Rel(empi, iam, "Valida tokens y claims de rol", "OAuth2 / OIDC")
    Rel(portal, empi, "Registra paciente / actualiza contacto", "HTTPS REST")
```
