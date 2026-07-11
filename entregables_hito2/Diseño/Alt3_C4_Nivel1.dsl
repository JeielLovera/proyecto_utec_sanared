workspace "Alt. 3 EMPI DDD Consolidado - C4 Nivel 1" "Diagrama de Contexto del Sistema EMPI (DDD + CQRS + Event Sourcing completo, perimetro dual AWS/Azure) - Clinica SanaRed Integrada" {

    model {
        !impliedRelationships false

        admisionista = person "Admisionista" "Registra y valida identidad del paciente en sede, urgencias o call center."
        medico = person "Medico / Clinico" "Consulta Golden Record y vista longitudinal 360 en el punto de atencion."
        gobDatos = person "Operador Gobierno de Datos" "Gestiona duplicados, calidad del indice y cumplimiento normativo."
        auditor = person "Auditor" "Consulta audit trail completo e inmutable de todas las operaciones sobre identidades."

        empi = softwareSystem "EMPI - Dominio de Identidad del Paciente" "Indice Maestro con DDD, CQRS y Event Sourcing completo. Cosmos DB como Event Store. Proyecciones especializadas por caso de uso. ElastiCache Redis para latencia garantizada. Perimetro dual AWS externo y Azure interno. Dual-cloud." {
            group "AWS - Perimetro Externo y Orquestacion" {
                apigw = container "AWS API Gateway + WAF" "Perimetro externo para canales digitales y admision web. WAF contra inyecciones. Rate limiting por canal. Circuit breaker a Redis. L-01" "API Gateway WAF Lambda Authorizer"
                redis = container "ElastiCache Redis" "Cache write-through DNI a EMPI-ID. 80pct de lookups en menos de 50ms. Modo offline TTL 24h. Fallback del circuit breaker. L-04" "Redis Multi-AZ"
                batchSf = container "Step Functions Orchestrator" "Orquesta el batch: inicio, particion, espera de Databricks, checkpointing y reporte. Retoma desde el ultimo checkpoint. INI-01" "AWS Step Functions"
                hl7Lambda = container "HL7 Transformer Lambda" "Adapter FHIR R4 a HL7 v2 para el HCE Oracle en Fase 1. Se elimina en Fase 2. Patron Adapter L-05" "Lambda Node.js"
                sqsDlqs = container "SQS Dead Letter Queues" "Colas queue-hce, queue-lis, queue-erp, queue-agenda, queue-crm, queue-pacs. DLQ con retry 30s, 60s, 120s. L-02" "SQS FIFO DLQ por sistema"
                cloudwatchAws = container "CloudWatch" "Metricas y logs del perimetro AWS. Alertas de latencia, error rate y profundidad de cola. Alimenta el dashboard Grafana. L-03" "CloudWatch SNS"
            }

            group "Azure - Motor de Dominio y Proyecciones" {
                apim = container "Azure APIM" "Perimetro interno para HCE Oracle, LIS y ERP. mTLS con autenticacion bidireccional por certificado. L-01" "API Management mTLS"
                empiDomain = container "EMPI Domain Service" "PatientAggregate con 6 Commands. Reglas de dominio: DNI, precedencia, scoring. Escribe eventos en Cosmos DB. Patron DDD CQRS Write Side" "Azure Container Apps Java Kotlin" {
                    fhirAdapter = component "FHIR R4 Inbound Adapter" "Recibe FHIR R4 Patient o JSON canonico desde ambos gateways. Traduce al modelo de dominio interno. Patron Adapter L-05" "REST Controller FHIR Parser"
                    correlationMw = component "Correlation Middleware" "Genera o propaga correlation_id unico por request. Lo inyecta en eventos y headers downstream. Trazabilidad end-to-end. L-06" "Request ID Propagator"
                    cmdBus = component "Command Bus" "Enruta cada Command al Handler correspondiente. Aplica middlewares de auditoria y validacion. Patron Command Bus Mediator" "In-process Command Dispatcher"
                    authGuard = component "Auth and RBAC Guard" "Verifica JWT RS256 emitido por IAM INI-03. Claims: rol, sede, source_system. Solo OPERADOR_DATOS puede ejecutar MergeRecords. L-01 RNF-03.1" "JWT Verifier Domain Role Enforcer"
                    patientAggregate = component "PatientAggregate" "Entidad raiz del dominio. Encapsula el estado del Golden Record y las invariantes de negocio. Genera eventos de dominio. Puro modelo de negocio, sin dependencias de infraestructura. Patron Aggregate Root DDD" "DDD Aggregate Root Domain Model"
                    domainRules = component "Domain Rules Engine" "Validacion de DNI peruano (8 digitos). Reglas de precedencia por source_system. Scoring thresholds 85pct y 95pct leidos desde App Configuration. RNF-06.2 L-07" "Business Rules Azure App Config"
                    regCmd = component "RegisterPatient Handler" "Genera EMPI-ID (UUID v7). Invoca al Matching Engine. Llama PatientAggregate.register(). Persiste via EventStoreRepository. RF-01 CA-01.1" "Command Handler"
                    mergeCmd = component "MergeRecords Handler" "Valida el score minimo. Llama PatientAggregate.merge(). Inactiva el registro secundario. Genera el evento RecordsMerged. RF-02 RF-03 CA-02.2" "Command Handler"
                    updateCmd = component "UpdateContact Handler" "Aplica la regla de precedencia del Domain Rules Engine. Llama PatientAggregate.updateContact(). Genera el evento ContactUpdated. RF-04" "Command Handler"
                    deactCmd = component "DeactivateRecord Handler" "Transicion a INACTIVO_FUSIONADO o INACTIVO_FALLECIDO. Bloquea citas si el motivo es DECEASED. Genera el evento RecordDeactivated. RF-06" "Command Handler"
                    revertCmd = component "RevertMerge Handler" "Reactiva el Golden Record secundario con sus datos historicos. Genera el evento MergeReverted mediante append, nunca UPDATE. RF-06 CA-02.4" "Command Handler"
                    confirmCmd = component "ConfirmDistinct Handler" "Marca dos registros como NO_MATCH_CONFIRMED. Persiste la regla de no-match. RF-02 Scenario 3" "Command Handler"
                    matchingEngine = component "Matching Engine" "Pesos: DNI exacto 0.50, nombre Soundex 0.20, fecha nacimiento 0.15, celular 0.10, correo 0.05. Consulta Elasticsearch en el paso 2. Score 0-100pct. RNF-01.1 CA-03.3" "Probabilistic Scorer"
                    esRepo = component "EventStoreRepository" "Persiste eventos en Cosmos DB con politica append-only. Optimistic locking por version del agregado. Patron Repository Event Sourcing L-06" "Cosmos DB SDK append-only"
                    querySvc = component "Query Service" "Sirve el Golden Record desde Cosmos DB y la Vista 360 desde Synapse. Cache-aside consultando Redis primero. Devuelve correlation_id en la respuesta. RNF-01.2 RF-05 CA-03.5" "Read Service CQRS Read Side"

                    apigw -> fhirAdapter "Request FHIR R4 con JWT claims" "HTTPS TLS 1.3"
                    apim -> fhirAdapter "Request FHIR R4 con JWT claims" "HTTPS mTLS"
                    fhirAdapter -> correlationMw "Propaga o genera correlation_id" "interno"
                    fhirAdapter -> cmdBus "Despacha Command interno" "interno"
                    cmdBus -> authGuard "Verifica permisos antes de ejecutar" "interno"
                    cmdBus -> regCmd "RegisterPatient Command" "interno"
                    cmdBus -> mergeCmd "MergeRecords Command" "interno"
                    cmdBus -> updateCmd "UpdateContact Command" "interno"
                    cmdBus -> deactCmd "DeactivateRecord Command" "interno"
                    cmdBus -> revertCmd "RevertMerge Command" "interno"
                    cmdBus -> confirmCmd "ConfirmDistinct Command" "interno"
                    cmdBus -> querySvc "Query Golden Record y Vista 360" "interno"
                    regCmd -> matchingEngine "Score pre-registro" "interno"
                    mergeCmd -> matchingEngine "Valida score minimo para merge" "interno"
                    regCmd -> patientAggregate "PatientAggregate.register()" "interno"
                    mergeCmd -> patientAggregate "PatientAggregate.merge()" "interno"
                    updateCmd -> patientAggregate "PatientAggregate.updateContact()" "interno"
                    deactCmd -> patientAggregate "PatientAggregate.deactivate()" "interno"
                    revertCmd -> patientAggregate "PatientAggregate.revertMerge()" "interno"
                    patientAggregate -> domainRules "Consulta reglas y umbrales" "interno"
                    patientAggregate -> esRepo "Persiste eventos generados" "interno"
                    matchingEngine -> domainRules "Lee umbrales de scoring" "interno"
                    regCmd -> redis "Write-through SET empi:dni:hash TTL 300" "Redis"
                    querySvc -> redis "GET por DNI hash o EMPI-ID" "Redis"
                }
                cosmosEs = container "Event Store" "Secuencia inmutable de eventos. Change Feed nativo sin polling. EMPI-ID, event_type, payload, actor, correlation_id. L-06 Patron Event Sourcing" "Azure Cosmos DB append-only" "Database"
                projectorSvc = container "Event Projector Service" "Consume el Cosmos Change Feed. Actualiza las cuatro proyecciones. Latencia de 1 a 5s. Patron Materialized View" "Azure Container Apps async"
                projCosmos = container "Golden Record View" "Lookup por EMPI-ID o DNI. Estado actual del Golden Record. Actualizacion menor a 1s. Sirve a admision ante cache miss." "Cosmos DB projection" "Database"
                projElastic = container "Duplicate Index" "Indice fuzzy por nombre fonetico, fecha de nacimiento y celular. Matching en tiempo real menor a 200ms. Base del batch en Databricks. RNF-01.1" "Elasticsearch Azure Elastic Cloud" "Database"
                projSynapse = container "Patient 360 View" "Vista longitudinal materializada con HCE, LIS, PACS y Agenda. Respuesta menor a 2s sin joins. RF-05 CA-03.5" "Azure Synapse Analytics" "Database"
                projMonitor = container "Audit Trail" "Proyeccion de eventos con correlation_id. Consultable en menos de 10s. 100pct auditadas. RNF-03.4 CA-05.2" "Azure Monitor Logs" "Database"
                appConfig = container "Azure App Configuration" "Almacena los scoring thresholds y reglas de precedencia. Leido por el Domain Rules Engine con cache TTL de 60s. RNF-06.2" "Azure App Configuration" "Database"
                serviceBus = container "Azure Service Bus" "Topics identity.patient.created, merged, contact.updated, deactivated, merge.reverted. Consumidores organizados por dominio. L-02" "Service Bus Topics"
                databricks = container "Azure Databricks" "Procesamiento paralelo del batch. Lee particiones de Elasticsearch. Scoring en paralelo a mas de 50000 registros por hora. INI-01" "Databricks Spark"
                reviewUi = container "UI Revision Manual" "Interfaz side-by-side con historial completo de eventos desde el Event Store. Cola FIFO por score descendente. Justificacion del operador. RF-02" "Azure Container Apps React"
                govEngine = container "Governance Engine" "Reporte semanal de calidad. Alertas de duplicados sobre 2pct. Retencion segun Ley 29733. Archivado a Glacier y Blob. RF-07 L-08" "Azure Container Apps scheduled"
                grafana = container "Grafana Dashboard" "Dashboard de KPIs combinando CloudWatch y Azure Monitor. L-03" "Grafana dual CloudWatch AzMonitor"
            }

            apigw -> redis "Cache lookup DNI a EMPI-ID" "Redis"
            apigw -> empiDomain "Command autenticado con JWT claims" "REST TLS"
            apim -> empiDomain "Command desde HCE LIS ERP con mTLS" "HTTPS mTLS"
            empiDomain -> cosmosEs "Append evento de dominio" "Cosmos SDK TLS"
            empiDomain -> redis "Write-through nuevo Golden Record" "Redis"
            cosmosEs -> projectorSvc "Change Feed nativo menor 500ms" "Cosmos Change Feed"
            projectorSvc -> projCosmos "Actualiza Golden Record View" "Cosmos SDK"
            projectorSvc -> projElastic "Actualiza Duplicate Index" "Elasticsearch API"
            projectorSvc -> projSynapse "Actualiza Patient 360 View" "Synapse pipeline"
            projectorSvc -> projMonitor "Escribe Audit Trail" "Azure Monitor API"
            cosmosEs -> serviceBus "Change Feed publica evento semantico" "Service Bus SDK"
            serviceBus -> sqsDlqs "Enruta por sistema destino" "Service Bus SQS bridge"
            sqsDlqs -> hl7Lambda "queue-hce trigger Lambda" "SQS"
            batchSf -> databricks "Trigger job con particion y checkpoint" "Databricks API"
            databricks -> projElastic "Lee duplicate candidates" "Elasticsearch API"
            databricks -> empiDomain "MergeRecords y ConfirmDistinct commands" "REST TLS"
            reviewUi -> empiDomain "MergeRecords y ConfirmDistinct manual" "REST JWT"
            reviewUi -> cosmosEs "Lee historial eventos por EMPI-ID" "Cosmos SDK"
            govEngine -> projMonitor "Consulta metricas de calidad" "Azure Monitor Query"
            grafana -> cloudwatchAws "Metricas AWS" "CloudWatch API"
            grafana -> projMonitor "Metricas Azure" "Azure Monitor API"
        }

        portal = softwareSystem "Portal Pacientes AWS RDS" "Autogestion digital del paciente." "External"
        agenda = softwareSystem "Agenda Medica SaaS" "Programacion de citas." "External"
        hce = softwareSystem "HCE Oracle 19c On-Prem Lima" "Historia Clinica Electronica. Sistema de registro de episodios clinicos." "External"
        lis = softwareSystem "LIS Azure SQL" "Sistema de Laboratorio. 3400 examenes por dia." "External"
        pacs = softwareSystem "PACS x4 sedes mas GCP" "Imagenes DICOM. 920 estudios por dia." "External"
        erp = softwareSystem "ERP Facturacion Nube Privada" "Ciclo de cobro. 13pct de expedientes observados por duplicados." "External"
        crm = softwareSystem "CRM SaaS Call Center" "Gestion de interacciones y datos de contacto." "External"
        iamSys = softwareSystem "IAM Centralizado SSO INI-03" "Autenticacion federada OAuth2 OIDC y mTLS. MFA obligatorio en escritura." "External"

        admisionista -> empi "Registra paciente y consulta identidad" "HTTPS REST FHIR R4 AWS API GW"
        medico -> empi "Consulta Golden Record y Vista 360" "HTTPS REST FHIR R4"
        gobDatos -> empi "Gestiona duplicados revisa calidad configura reglas" "UI Admin API REST"
        auditor -> empi "Consulta audit trail inmutable por EMPI-ID" "UI Auditoria Read-only"

        empi -> hce "identity.patient.created y merged HL7 v2 Fase 1 o FHIR R4 Fase 2" "Azure Service Bus Lambda Transform SQS"
        empi -> lis "identity.patient.created FHIR R4 Patient" "Azure Service Bus SQS"
        empi -> pacs "identity.patient.created vincula DICOM a EMPI-ID" "Azure Service Bus SQS"
        empi -> agenda "identity.patient.created y contact.updated" "Azure Service Bus REST"
        empi -> erp "identity.patient.merged y contact.updated" "Azure Service Bus SQS"
        empi -> crm "identity.contact.updated y patient.created" "Azure Service Bus REST"
        portal -> empi "RegisterPatient UpdateContact Consulta Golden Record" "HTTPS REST AWS API GW"
        empi -> iamSys "Valida tokens JWT claims de rol y sede mTLS interno" "OAuth2 OIDC mTLS"

        # Relaciones de nivel Contenedor (C4 Nivel 2)
        admisionista -> apigw "HTTPS REST FHIR R4" "TLS 1.3"
        gobDatos -> reviewUi "Revision de duplicados" "HTTPS"
        gobDatos -> grafana "KPIs y alertas del EMPI" "HTTPS"
        apigw -> iamSys "Valida token JWT" "OAuth2 OIDC"
        apim -> iamSys "Valida token y certificado cliente" "mTLS"
        hl7Lambda -> hce "HL7 v2 ADT ORU" "MLLP TCP"
        sqsDlqs -> lis "queue-lis FHIR Patient" "SQS REST"
        sqsDlqs -> erp "queue-erp patient.merged" "SQS"
        serviceBus -> agenda "identity.patient.created y contact.updated" "Service Bus REST"

        # Relaciones de nivel Componente (C4 Nivel 3)
        authGuard -> iamSys "Verifica JWT RS256 desde IAM INI-03" "JWKS endpoint HTTPS"
        esRepo -> cosmosEs "Append evento con optimistic lock" "Cosmos SDK TLS"
        matchingEngine -> projElastic "Fuzzy query candidatos step 2" "Elasticsearch API TLS"
        querySvc -> cosmosEs "GET Golden Record View si cache miss" "Cosmos SDK"
        querySvc -> projSynapse "GET Patient 360 projection" "Synapse SQL TLS"
        domainRules -> appConfig "GetConfiguration cache TTL 60s" "Azure SDK"
    }

    views {
        systemContext empi "SystemContext-EMPI" {
            include *
            autoLayout tb
            title "Alt. 3 EMPI DDD Consolidado - C4 Nivel 1 Contexto del Sistema"
        }

        container empi "Containers-EMPI" {
            include *
            autoLayout tb
            title "Alt. 3 EMPI DDD Consolidado - C4 Nivel 2 Contenedores"
        }

        component empiDomain "Components-EMPIDomainService" {
            include *
            autoLayout tb
            title "Alt. 3 EMPI DDD Consolidado - C4 Nivel 3 Componentes EMPI Domain Service"
        }

        styles {
            element "Person" {
                shape person
                background #08427b
                color #ffffff
                fontSize 22
            }
            element "Software System" {
                background #1168bd
                color #ffffff
            }
            element "External" {
                background #999999
                color #ffffff
            }
            element "Container" {
                background #438dd5
                color #ffffff
            }
            element "Database" {
                shape cylinder
                background #438dd5
                color #ffffff
            }
            element "Component" {
                background #85bbf0
                color #000000
            }
        }
    }
}
