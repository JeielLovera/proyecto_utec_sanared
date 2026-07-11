workspace "Alt. 2 EMPI Federado DDD - C4 Nivel 1" "Diagrama de Contexto del Sistema EMPI (Indice Maestro de Pacientes Federado con DDD, CQRS y Event Sourcing) - Clinica SanaRed Integrada" {

    model {
        !impliedRelationships false

        admisionista = person "Admisionista" "Registra y valida identidad del paciente en admision presencial o urgencias desde cualquier sede."
        medico = person "Medico / Clinico" "Consulta el Golden Record y la vista longitudinal 360 del paciente en el punto de atencion."
        gobDatos = person "Operador Gobierno de Datos" "Gestiona duplicados, ejecuta fusiones manuales y monitorea la calidad del indice maestro."
        auditor = person "Auditor" "Acceso de solo lectura al audit trail completo e inmutable de todas las operaciones sobre identidades."

        empi = softwareSystem "EMPI - Dominio de Identidad del Paciente" "Indice Maestro Federado con DDD, CQRS y Event Sourcing completo. Cosmos DB como Event Store. Proyecciones especializadas por caso de uso. Azure Service Bus para propagacion de eventos semanticos. Cloud primario: Azure." {
            group "Azure - Plataforma principal del EMPI" {
                apim = container "Azure APIM" "Unico punto de entrada al EMPI. mTLS para sistemas internos HCE LIS ERP. OAuth2 OIDC para canales externos Portal App CRM. Rate limiting por canal. L-01 Seguridad" "API Management mTLS OAuth2"
                empiSvc = container "EMPI Domain Service" "PatientAggregate con 4 Commands: RegisterPatient MergeRecords UpdateContact DeactivateRecord. Domain Rules Engine. Scoring thresholds configurables. Patron DDD CQRS Write Side" "Azure Container Apps Java Kotlin" {
                    fhirAdapter = component "FHIR R4 Inbound Adapter" "Recibe requests FHIR R4 Patient resource o JSON canonico desde APIM. Traduce al modelo de dominio interno. Desacopla protocolo de transporte del dominio. Patron Adapter L-05" "REST Controller FHIR Parser"
                    cmdDispatcher = component "Command Dispatcher" "Recibe el Command del Adapter y lo enruta al Handler correspondiente. Aplica los middlewares de autenticacion y correlacion antes de ejecutar. Patron Command Bus" "In-process Command Bus Mediator"
                    authGuard = component "Auth and RBAC Guard" "Verifica firma JWT RS256 emitida por IAM INI-03. Extrae claims: rol sede source_system. Valida que el rol tiene permiso para el Command especifico. Solo OPERADOR_DATOS puede MergeRecords. L-01 RNF-03.1" "JWT Verifier Domain Role Enforcer"
                    correlationMw = component "Correlation Middleware" "Genera o propaga correlation_id unico por request. Lo inyecta en cada evento generado y en headers downstream. Habilita trazabilidad end-to-end desde el canal hasta el consumidor. L-06" "Request ID Propagator"
                    patientAggregate = component "PatientAggregate" "Entidad raiz del dominio. Encapsula el estado del Golden Record y todas las invariantes de negocio. Genera eventos de dominio como resultado de cada Command aceptado. Sin dependencias de infraestructura: puro modelo de negocio. Patron Aggregate Root DDD" "DDD Aggregate Root Domain Model"
                    domainRules = component "Domain Rules Engine" "Validacion de formato DNI peruano 8 digitos. Reglas de precedencia configurable por source_system: Portal mayor prioridad para datos contacto, HCE para datos clinicos. Scoring thresholds 85pct y 95pct. RNF-06.2 L-07" "Business Rules configurable"
                    regHandler = component "RegisterPatient Handler" "Valida formato DNI. Invoca Matching Engine para scoring pre-registro. Si no hay duplicado crea Golden Record. Llama PatientAggregate.register(). Persiste via EventStoreRepository. RF-01 CA-01.1" "Command Handler"
                    mergeHandler = component "MergeRecords Handler" "Valida score minimo segun Domain Rules. Llama PatientAggregate.merge(). Inactiva registro secundario. Genera RecordsMerged event con reason AUTO o MANUAL. RF-02 RF-03 CA-02.2" "Command Handler"
                    updateHandler = component "UpdateContact Handler" "Aplica regla de precedencia del Domain Rules Engine antes de actualizar. Llama PatientAggregate.updateContact(). Genera ContactUpdated event. RF-04" "Command Handler"
                    deactHandler = component "DeactivateRecord Handler" "Gestiona transicion a INACTIVO_FUSIONADO o INACTIVO_FALLECIDO segun reason. Bloquea nuevas citas si reason es DECEASED. Genera RecordDeactivated event. RF-06" "Command Handler"
                    matchingEngine = component "Matching Engine" "Paso 1: busqueda exacta por DNI en proyeccion Cosmos DB menos de 10ms. Paso 2: busqueda fuzzy en Elasticsearch por nombre fonetico y fecha nacimiento menos de 200ms. Paso 3: scoring final multi-atributo DNI 0.50 nombre 0.20 FN 0.15 celular 0.10 correo 0.05. P95 total menor 500ms. RNF-01.1 CA-03.3" "Probabilistic Scorer Elasticsearch client"
                    esRepo = component "EventStoreRepository" "Persiste eventos de dominio en Cosmos DB con semantica append-only. Optimistic locking por campo version del agregado para evitar escrituras concurrentes. Devuelve stream de eventos para reconstruir estado si es necesario. Patron Repository Event Sourcing L-06" "Cosmos DB SDK append-only"
                    querySvc = component "Query Service" "Sirve consultas de Golden Record desde proyeccion Cosmos DB. Sirve Vista 360 desde Azure Synapse. Cache-aside: consulta primero Cosmos projection y si no hay respuesta redirige. Devuelve correlation_id en respuesta para trazabilidad. RNF-01.2 RF-05 CA-03.5" "CQRS Read Side Service"

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
                cosmosEs = container "Event Store" "Secuencia inmutable de todos los eventos de identidad. Change Feed nativo sin polling. PatientRegistered RecordsMerged ContactUpdated RecordDeactivated. L-06 Patron Event Sourcing" "Azure Cosmos DB append-only" "Database"
                projector = container "Event Projector Service" "Consume Cosmos DB Change Feed. Actualiza las cuatro proyecciones especializadas en paralelo. Latencia menor a 2s por proyeccion. Patron Materialized View" "Azure Container Apps async"
                projCosmos = container "Golden Record View" "Lookup rapido por EMPI-ID o DNI. Estado actual del Golden Record. Actualizacion menor a 2s. Sirve consultas de admision y portal. RF-05" "Cosmos DB projection collection" "Database"
                projElastic = container "Duplicates Index" "Indice fuzzy de nombre fonetico fecha nacimiento y celular. Matching tiempo real menor 200ms. Alimenta batch Databricks. RNF-01.1" "Elasticsearch Azure Elastic Cloud" "Database"
                projSynapse = container "Vista 360 Longitudinal" "Vista medica materializada con HCE LIS PACS Agenda y Recetas. Sin joins en tiempo real. Respuesta menor 2s. RF-05 CA-03.5" "Azure Synapse Analytics" "Database"
                projMonitor = container "Audit Trail" "Proyeccion de todos los eventos con actor source_sys y timestamp. Consultable menor 10s. 100pct auditado. RNF-03.4 CA-05.2" "Azure Monitor Logs" "Database"
                serviceBus = container "Azure Service Bus" "Topics semanticos: identity.patient.created merged contact.updated record.deactivated. DLQ y retry backoff 30s 60s 120s. L-02 Patron EDA" "Service Bus Topics con DLQ"
                databricks = container "Batch Deduplication" "Procesamiento paralelo del corpus de 126000 duplicados. Scoring distribuido sobre particiones. Mayor a 50000 registros por hora. INI-01 RNF-01.3" "Azure Databricks Spark"
                reviewQueue = container "Manual Review Queue" "Pares con score 85 a 94pct encolados por prioridad. Alimenta la UI de revision manual. RF-02 Scenario 2" "Service Bus FIFO por score desc"
                reviewUi = container "UI Revision Manual" "Interfaz side-by-side con historial completo de eventos desde Event Store. Captura justificacion del operador. RF-02 CA-02.3" "Azure Container Apps React"
                govEngine = container "Governance Engine" "Reporte semanal de calidad RF-07. Alertas tasa duplicados mayor 2pct. Retencion Ley 29733. Archivado a Blob Cool Tier y Glacier. L-08" "Azure Container Apps scheduled"
                grafana = container "Dashboard Observabilidad" "KPIs en tiempo real desde Change Feed. Tasa duplicados latencia throughput cola revision. L-03 Observabilidad" "Grafana conectado a Azure Monitor"
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
