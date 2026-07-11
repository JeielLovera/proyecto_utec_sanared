workspace "Alt. 2 EMPI Federado DDD - C4 Nivel 1" "Diagrama de Contexto del Sistema EMPI (Indice Maestro de Pacientes Federado con DDD, CQRS y Event Sourcing) - Clinica SanaRed Integrada" {

    model {
        !impliedRelationships false

        admisionista = person "Admisionista" "Registra y valida identidad del paciente en admision presencial o urgencias desde cualquier sede."
        medico = person "Medico / Clinico" "Consulta el Golden Record y la vista longitudinal 360 del paciente en el punto de atencion."
        gobDatos = person "Operador Gobierno de Datos" "Gestiona duplicados, ejecuta fusiones manuales y monitorea la calidad del indice maestro."
        auditor = person "Auditor" "Acceso de solo lectura al audit trail completo e inmutable de todas las operaciones sobre identidades."

        empi = softwareSystem "EMPI - Dominio de Identidad del Paciente" "Indice Maestro Federado con DDD, CQRS y Event Sourcing completo. Cosmos DB como Event Store. Proyecciones especializadas por caso de uso. Azure Service Bus para propagacion de eventos semanticos. Cloud primario: Azure." {
            group "Azure - Plataforma principal del EMPI" {
                apim = container "Azure APIM" "Punto de entrada unico. mTLS interno, OAuth2 externo, rate limiting." "API Management mTLS OAuth2"
                empiSvc = container "EMPI Domain Service" "PatientAggregate y sus 4 Commands. Write Side CQRS." "Azure Container Apps Java Kotlin" {
                    fhirAdapter = component "FHIR R4 Inbound Adapter" "Traduce FHIR R4 a modelo de dominio interno." "REST Controller FHIR Parser"
                    cmdDispatcher = component "Command Dispatcher" "Enruta cada Command al Handler correspondiente." "In-process Command Bus Mediator"
                    authGuard = component "Auth and RBAC Guard" "Verifica JWT y permisos por rol." "JWT Verifier Domain Role Enforcer"
                    correlationMw = component "Correlation Middleware" "Propaga correlation_id para trazabilidad end-to-end." "Request ID Propagator"
                    patientAggregate = component "PatientAggregate" "Raiz de dominio: invariantes y eventos del Golden Record." "DDD Aggregate Root Domain Model"
                    domainRules = component "Domain Rules Engine" "Umbrales de scoring y reglas de precedencia configurables." "Business Rules configurable"
                    regHandler = component "RegisterPatient Handler" "Valida DNI, hace scoring y crea el Golden Record." "Command Handler"
                    mergeHandler = component "MergeRecords Handler" "Fusiona registros segun score AUTO o MANUAL." "Command Handler"
                    updateHandler = component "UpdateContact Handler" "Actualiza contacto aplicando reglas de precedencia." "Command Handler"
                    deactHandler = component "DeactivateRecord Handler" "Inactiva registro por fusion o fallecimiento." "Command Handler"
                    matchingEngine = component "Matching Engine" "Scoring probabilistico DNI, nombre, fecha nacimiento, contacto. P95 menor 500ms." "Probabilistic Scorer Elasticsearch client"
                    esRepo = component "EventStoreRepository" "Persistencia append-only con optimistic locking." "Cosmos DB SDK append-only"
                    querySvc = component "Query Service" "Sirve Golden Record y Vista 360 al Read Side." "CQRS Read Side Service"

                    apim -> fhirAdapter "Request FHIR R4 con JWT claims" "HTTPS TLS 1.3"
                    fhirAdapter -> correlationMw "Genera o propaga correlation_id" "interno"
                    fhirAdapter -> cmdDispatcher "Despacha Command interno con contexto" "interno"
                    cmdDispatcher -> authGuard "Verifica permisos antes de ejecutar" "interno"
                    cmdDispatcher -> regHandler "RegisterPatient Command" "interno"
                    cmdDispatcher -> mergeHandler "MergeRecords Command" "interno"
                    cmdDispatcher -> updateHandler "UpdateContact Command" "interno"
                    cmdDispatcher -> deactHandler "DeactivateRecord Command" "interno"
                    cmdDispatcher -> querySvc "Query Golden Record y Vista 360" "interno"
                    regHandler -> matchingEngine "Score pre-registro para detectar duplicados" "interno"
                    mergeHandler -> matchingEngine "Valida score minimo antes de fusionar" "interno"
                    regHandler -> domainRules "Consulta umbrales y reglas de validacion" "interno"
                    mergeHandler -> domainRules "Consulta threshold 95pct para auto-merge" "interno"
                    updateHandler -> domainRules "Consulta reglas de precedencia por source_system" "interno"
                    regHandler -> patientAggregate "PatientAggregate.register()" "interno"
                    mergeHandler -> patientAggregate "PatientAggregate.merge()" "interno"
                    updateHandler -> patientAggregate "PatientAggregate.updateContact()" "interno"
                    deactHandler -> patientAggregate "PatientAggregate.deactivate()" "interno"
                    patientAggregate -> esRepo "Persiste eventos de dominio generados" "interno"
                }
                cosmosEs = container "Event Store" "Secuencia inmutable de eventos con Change Feed nativo." "Azure Cosmos DB append-only" "Database"
                projector = container "Event Projector Service" "Actualiza las 4 proyecciones desde el Change Feed." "Azure Container Apps async"
                projCosmos = container "Golden Record View" "Lookup por EMPI-ID o DNI, menor a 2s." "Cosmos DB projection collection" "Database"
                projElastic = container "Duplicates Index" "Indice fuzzy para matching, menor 200ms." "Elasticsearch Azure Elastic Cloud" "Database"
                projSynapse = container "Vista 360 Longitudinal" "Vista medica multi-fuente sin joins en tiempo real." "Azure Synapse Analytics" "Database"
                projMonitor = container "Audit Trail" "Proyeccion de auditoria con actor, sistema y timestamp." "Azure Monitor Logs" "Database"
                serviceBus = container "Azure Service Bus" "Topics semanticos con DLQ y retry backoff." "Service Bus Topics con DLQ"
                databricks = container "Batch Deduplication" "Scoring paralelo del corpus historico de duplicados." "Azure Databricks Spark"
                reviewQueue = container "Manual Review Queue" "Cola de pares dudosos priorizada por score." "Service Bus FIFO por score desc"
                reviewUi = container "UI Revision Manual" "Revision side-by-side con historial de eventos." "Azure Container Apps React"
                govEngine = container "Governance Engine" "Reportes de calidad, alertas y retencion Ley 29733." "Azure Container Apps scheduled"
                grafana = container "Dashboard Observabilidad" "KPIs en tiempo real: duplicados, latencia, throughput." "Grafana conectado a Azure Monitor"
            }

            apim -> empiSvc "Command autenticado con claims de rol" "REST TLS interno"
            empiSvc -> cosmosEs "Append evento de dominio append-only" "Cosmos SDK TLS"
            cosmosEs -> projector "Change Feed nativo menor 500ms" "Cosmos Change Feed"
            projector -> projCosmos "Actualiza Golden Record View" "Cosmos SDK"
            projector -> projElastic "Actualiza Duplicate Index" "Elasticsearch API"
            projector -> projSynapse "Actualiza Vista 360 Longitudinal" "Synapse pipeline"
            projector -> projMonitor "Escribe Audit Trail" "Azure Monitor Ingestion API"
            cosmosEs -> serviceBus "Change Feed publica evento semantico" "Service Bus SDK"
            projElastic -> databricks "Lee particiones de candidatos a duplicado" "Elasticsearch API"
            databricks -> empiSvc "MergeRecords y ConfirmDistinct commands" "REST TLS"
            databricks -> reviewQueue "Encola pares score 85 a 94pct" "Service Bus SDK"
            reviewQueue -> reviewUi "Pares ordenados por score desc" "Service Bus poll"
            reviewUi -> empiSvc "MergeRecords y ConfirmDistinct manual con justificacion" "REST JWT"
            reviewUi -> cosmosEs "Lee historial de eventos del registro" "Cosmos SDK Read-only"
            govEngine -> projMonitor "Consulta metricas de calidad" "Azure Monitor Query API"
            grafana -> projMonitor "Metricas y logs del EMPI" "Azure Monitor API"
            projCosmos -> apim "Sirve Golden Record ante consulta" "Cosmos SDK"
            projSynapse -> apim "Sirve Vista 360 ante consulta medico" "Synapse SQL"
        }

        portal = softwareSystem "Portal Pacientes AWS RDS" "Autogestion digital del paciente: citas, resultados, actualizacion de contacto." "External"
        agenda = softwareSystem "Agenda Medica SaaS" "Programacion de citas. Consume identidad del EMPI." "External"
        hce = softwareSystem "HCE Oracle 19c On-Prem Lima" "Historia Clinica Electronica. Sistema de registro de episodios clinicos y datos medicamentos." "External"
        lis = softwareSystem "LIS Azure SQL" "Sistema de Laboratorio. 3400 examenes por dia vinculados a EMPI-ID." "External"
        pacs = softwareSystem "PACS x4 sedes mas GCP" "Imagenes DICOM. 920 estudios por dia vinculados a EMPI-ID." "External"
        erp = softwareSystem "ERP Facturacion Nube Privada" "Ciclo de cobro. Consolida facturacion bajo EMPI-ID activo post-merge." "External"
        crm = softwareSystem "CRM SaaS Call Center" "Gestion de interacciones. Consume actualizaciones de datos de contacto." "External"
        iamSys = softwareSystem "IAM SSO Centralizado INI-03" "Autenticacion federada OAuth2 OIDC y mTLS. MFA obligatorio en escritura." "External"

        admisionista -> empi "Registra paciente y consulta identidad" "HTTPS REST FHIR R4"
        medico -> empi "Consulta Golden Record y Vista 360" "HTTPS REST FHIR R4"
        gobDatos -> empi "Gestiona duplicados y calidad del indice" "UI Admin API REST"
        auditor -> empi "Consulta audit trail inmutable por EMPI-ID" "UI Auditoria Read-only"

        empi -> hce "identity.patient.created y merged via HL7 v2 Fase 1 o FHIR R4 Fase 2" "Azure Service Bus"
        empi -> lis "identity.patient.created FHIR R4 Patient" "Azure Service Bus"
        empi -> pacs "identity.patient.created vincula DICOM a EMPI-ID" "Azure Service Bus"
        empi -> agenda "identity.patient.created y contact.updated" "Azure Service Bus REST"
        empi -> erp "identity.patient.merged y contact.updated" "Azure Service Bus"
        empi -> crm "identity.contact.updated y patient.created" "Azure Service Bus REST"
        portal -> empi "RegisterPatient UpdateContact Consulta Golden Record" "HTTPS REST Azure APIM"
        empi -> iamSys "Valida tokens JWT y claims de rol y sede" "OAuth2 OIDC mTLS"

        # Relaciones de nivel Contenedor (C4 Nivel 2)
        admisionista -> apim "HTTPS REST FHIR R4" "TLS 1.3"
        gobDatos -> reviewUi "Revision manual de duplicados" "HTTPS"
        gobDatos -> grafana "Monitoreo KPIs y alertas" "HTTPS"
        apim -> iamSys "Valida token JWT y claims" "OAuth2 OIDC"
        serviceBus -> hce "identity.patient.created merged HL7 v2 o FHIR R4" "Service Bus MLLP TCP"
        serviceBus -> lis "identity.patient.created FHIR R4" "Service Bus REST"
        serviceBus -> pacs "identity.patient.created" "Service Bus"
        serviceBus -> erp "identity.patient.merged y contact.updated" "Service Bus"
        serviceBus -> agenda "identity.patient.created y contact.updated" "Service Bus REST"
        serviceBus -> crm "identity.contact.updated y patient.created" "Service Bus REST"

        # Relaciones de nivel Componente (C4 Nivel 3)
        authGuard -> iamSys "Valida firma del token JWT RS256" "JWKS endpoint HTTPS"
        esRepo -> cosmosEs "Append evento con optimistic lock por version" "Cosmos SDK TLS"
        matchingEngine -> projElastic "Fuzzy query nombre fonetico y fecha nacimiento" "Elasticsearch API TLS"
        matchingEngine -> projCosmos "Lookup exacto por DNI paso 1" "Cosmos SDK TLS"
        querySvc -> projCosmos "GET Golden Record View por EMPI-ID o DNI" "Cosmos SDK TLS"
        querySvc -> projSynapse "GET Vista 360 longitudinal" "Synapse SQL TLS"
    }

    views {
        systemContext empi "SystemContext-EMPI" {
            include *
            autoLayout tb
            title "Alt. 2 EMPI Federado DDD - C4 Nivel 1 Contexto del Sistema"
        }

        container empi "Containers-EMPI" {
            include *
            autoLayout tb
            title "Alt. 2 EMPI Federado DDD - C4 Nivel 2 Contenedores"
        }

        component empiSvc "Components-EMPIDomainService" {
            include *
            autoLayout tb
            title "Alt. 2 EMPI Federado DDD - C4 Nivel 3 Componentes EMPI Domain Service"
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
