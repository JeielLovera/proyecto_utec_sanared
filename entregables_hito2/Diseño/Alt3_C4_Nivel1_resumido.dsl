workspace "Alt. 3 EMPI DDD Consolidado - C4 Nivel 1" "Diagrama de Contexto del Sistema EMPI (DDD + CQRS + Event Sourcing completo, perimetro dual AWS/Azure) - Clinica SanaRed Integrada" {

    model {
        !impliedRelationships false

        admisionista = person "Admisionista" "Registra y valida identidad del paciente en sede, urgencias o call center."
        medico = person "Medico / Clinico" "Consulta Golden Record y vista longitudinal 360 en el punto de atencion."
        gobDatos = person "Operador Gobierno de Datos" "Gestiona duplicados, calidad del indice y cumplimiento normativo."
        auditor = person "Auditor" "Consulta audit trail completo e inmutable de todas las operaciones sobre identidades."

        empi = softwareSystem "EMPI - Dominio de Identidad del Paciente" "Indice Maestro con DDD, CQRS y Event Sourcing completo. Cosmos DB como Event Store. Proyecciones especializadas por caso de uso. ElastiCache Redis para latencia garantizada. Perimetro dual AWS externo y Azure interno. Dual-cloud." {
            group "AWS - Perimetro Externo y Orquestacion" {
                apigw = container "AWS API Gateway + WAF" "Perimetro externo con WAF, rate limiting y circuit breaker a Redis." "API Gateway WAF Lambda Authorizer"
                redis = container "ElastiCache Redis" "Cache write-through DNI a EMPI-ID. 80pct de lookups en menos de 50ms." "Redis Multi-AZ"
                batchSf = container "Step Functions Orchestrator" "Orquesta el batch con checkpointing y retoma ante fallos." "AWS Step Functions"
                hl7Lambda = container "HL7 Transformer Lambda" "Adapter FHIR R4 a HL7 v2 para el HCE en Fase 1." "Lambda Node.js"
                sqsDlqs = container "SQS Dead Letter Queues" "Colas por sistema destino con DLQ y retry backoff." "SQS FIFO DLQ por sistema"
                cloudwatchAws = container "CloudWatch" "Metricas y alertas del perimetro AWS." "CloudWatch SNS"
            }

            group "Azure - Motor de Dominio y Proyecciones" {
                apim = container "Azure APIM" "Perimetro interno con mTLS para HCE, LIS y ERP." "API Management mTLS"
                empiDomain = container "EMPI Domain Service" "PatientAggregate con 6 Commands. Write Side CQRS." "Azure Container Apps Java Kotlin" {
                    fhirAdapter = component "FHIR R4 Inbound Adapter" "Traduce FHIR R4 al modelo de dominio interno." "REST Controller FHIR Parser"
                    correlationMw = component "Correlation Middleware" "Propaga correlation_id para trazabilidad end-to-end." "Request ID Propagator"
                    cmdBus = component "Command Bus" "Enruta cada Command al Handler correspondiente." "In-process Command Dispatcher"
                    authGuard = component "Auth and RBAC Guard" "Verifica JWT y permisos por rol." "JWT Verifier Domain Role Enforcer"
                    patientAggregate = component "PatientAggregate" "Raiz de dominio: invariantes y eventos del Golden Record." "DDD Aggregate Root Domain Model"
                    domainRules = component "Domain Rules Engine" "Umbrales de scoring y reglas de precedencia configurables." "Business Rules Azure App Config"
                    regCmd = component "RegisterPatient Handler" "Genera EMPI-ID, hace scoring y crea el Golden Record." "Command Handler"
                    mergeCmd = component "MergeRecords Handler" "Fusiona registros segun score AUTO o MANUAL." "Command Handler"
                    updateCmd = component "UpdateContact Handler" "Actualiza contacto aplicando reglas de precedencia." "Command Handler"
                    deactCmd = component "DeactivateRecord Handler" "Inactiva registro por fusion o fallecimiento." "Command Handler"
                    revertCmd = component "RevertMerge Handler" "Reactiva un Golden Record fusionado por error." "Command Handler"
                    confirmCmd = component "ConfirmDistinct Handler" "Marca dos registros como definitivamente distintos." "Command Handler"
                    matchingEngine = component "Matching Engine" "Scoring probabilistico DNI, nombre, fecha nacimiento, contacto." "Probabilistic Scorer"
                    esRepo = component "EventStoreRepository" "Persistencia append-only con optimistic locking." "Cosmos DB SDK append-only"
                    querySvc = component "Query Service" "Sirve Golden Record y Vista 360, cache-aside con Redis." "Read Service CQRS Read Side"

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
                cosmosEs = container "Event Store" "Secuencia inmutable de eventos con Change Feed nativo." "Azure Cosmos DB append-only" "Database"
                projectorSvc = container "Event Projector Service" "Actualiza las cuatro proyecciones desde el Change Feed." "Azure Container Apps async"
                projCosmos = container "Golden Record View" "Lookup por EMPI-ID o DNI, menor a 1s. Sirve ante cache miss." "Cosmos DB projection" "Database"
                projElastic = container "Duplicate Index" "Indice fuzzy para matching, menor 200ms." "Elasticsearch Azure Elastic Cloud" "Database"
                projSynapse = container "Patient 360 View" "Vista medica multi-fuente sin joins en tiempo real." "Azure Synapse Analytics" "Database"
                projMonitor = container "Audit Trail" "Proyeccion de auditoria con correlation_id." "Azure Monitor Logs" "Database"
                appConfig = container "Azure App Configuration" "Umbrales y reglas de precedencia con cache TTL 60s." "Azure App Configuration" "Database"
                serviceBus = container "Azure Service Bus" "Topics semanticos por dominio, consumidores por suscripcion." "Service Bus Topics"
                databricks = container "Azure Databricks" "Scoring paralelo del corpus historico de duplicados." "Databricks Spark"
                reviewUi = container "UI Revision Manual" "Revision side-by-side con historial de eventos." "Azure Container Apps React"
                govEngine = container "Governance Engine" "Reportes de calidad, alertas y retencion Ley 29733." "Azure Container Apps scheduled"
                grafana = container "Grafana Dashboard" "KPIs combinando CloudWatch y Azure Monitor." "Grafana dual CloudWatch AzMonitor"
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
