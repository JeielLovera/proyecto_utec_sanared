workspace "Alt. 1 EMPI Centralizado - C4 Nivel 1" "Diagrama de Contexto del Sistema EMPI (EMPI Centralizado con API Gateway y ESB) - Clinica SanaRed Integrada" {

    model {
        !impliedRelationships false

        admisionista = person "Admisionista" "Registra y valida identidad del paciente en admision presencial o urgencias desde cualquier sede."
        medico = person "Medico / Clinico" "Consulta el Golden Record del paciente en el punto de atencion."
        gobDatos = person "Operador Gobierno de Datos" "Gestiona duplicados, ejecuta fusiones manuales y monitorea la calidad del indice maestro."
        auditor = person "Auditor" "Acceso de solo lectura al audit log completo de todas las operaciones sobre identidades."

        empi = softwareSystem "EMPI - Indice Maestro Centralizado" "EMPI completamente centralizado. Aurora PostgreSQL Multi-AZ como Master DB. ElastiCache Redis para latencia garantizada. AWS API Gateway como unico punto de entrada. ESB EventBridge mas SQS para propagacion de cambios. Cloud primario: AWS." {
            apigw = container "AWS API Gateway" "Unico punto de entrada al EMPI. Autenticacion JWT OAuth2, rate limiting, logging centralizado. L-01" "API Gateway JWT OAuth2"
            empiCore = container "EMPI Core Service" "Motor de Matching y Scoring, Golden Record Engine, Deduplication Service y Lifecycle Manager como modulos internos de un unico servicio desplegable. Patron MDM" "AWS ECS Fargate" {
                apiController = component "API Controller" "Recibe el request autenticado desde AWS API Gateway y lo despacha al flujo de resolucion de identidad. Patron Adapter" "REST Controller"
                cacheClient = component "Cache Client" "Consulta y actualiza ElastiCache Redis para lookups de baja latencia por DNI o EMPI-ID" "Redis Client"
                repository = component "Golden Record Repository" "Persiste y consulta el Golden Record en Aurora. Encapsula el acceso a datos detras de una interfaz unica. Patron Repository" "JDBC Aurora PostgreSQL"
                matchingEngine = component "Motor de Matching y Scoring" "Algoritmo probabilistico sobre DNI, nombre fonetico Soundex o Metaphone, fecha de nacimiento, celular y correo. Produce un score de 0 a 100pct" "Probabilistic Scorer"
                goldenRecordEngine = component "Golden Record Engine" "Crea el EMPI-ID canonico. Aplica reglas de precedencia por sistema fuente para resolver conflictos de datos" "Domain Service"
                dedupService = component "Deduplication Service" "Modo batch INI-01 orquestado por Step Functions. Modo tiempo real INI-13 sincronico en cada alta o consulta" "Domain Service"
                lifecycleMgr = component "Lifecycle Manager" "Controla las transiciones de estado: INCOMPLETO, VERIFICADO, POSIBLE_DUPLICADO, INACTIVO_FUSIONADO, INACTIVO_FALLECIDO, Archivado" "State Machine"
                eventPublisher = component "Event Publisher" "Publica los eventos de cambio PATIENT_CREATED, PATIENT_MERGED y CONTACT_UPDATED hacia el Event Bus" "EventBridge SDK"

                apigw -> apiController "Request autenticado con claims de rol" "REST TLS"
                apiController -> cacheClient "Lookup por DNI hash" "interno"
                cacheClient -> repository "Cache miss, consulta Master DB" "interno"
                repository -> matchingEngine "No existe registro, ejecuta matching" "interno"
                matchingEngine -> goldenRecordEngine "Score menor 85pct, crea Golden Record" "interno"
                matchingEngine -> dedupService "Score mayor o igual 85pct, deriva a deduplicacion" "interno"
                goldenRecordEngine -> lifecycleMgr "Determina estado inicial del registro" "interno"
                dedupService -> lifecycleMgr "Actualiza estado tras fusion o revision manual" "interno"
                goldenRecordEngine -> repository "Persiste el nuevo Golden Record" "interno"
                goldenRecordEngine -> cacheClient "Actualiza el cache con el nuevo registro" "interno"
                goldenRecordEngine -> eventPublisher "Publica PATIENT_CREATED" "interno"
                dedupService -> eventPublisher "Publica PATIENT_MERGED" "interno"
            }
            masterDb = container "Master DB" "Golden Records, EMPI-IDs y relaciones entre registros. Failover automatico menor a 30s. RNF-02.1" "Aurora PostgreSQL Multi-AZ" "Database"
            cache = container "Cache Layer" "Lookup por DNI o EMPI-ID en tiempo real. TTL 5 min. Absorbe hasta 80pct del trafico de lectura. RNF-01.1" "ElastiCache Redis" "Database"
            auditStore = container "Audit Log Store" "CloudWatch retiene 12 meses activos. S3 Glacier retiene el historico hasta 10 anios. RNF-03.4 RNF-07.2" "CloudWatch mas S3 Glacier" "Database"
            eventBus = container "Event Bus" "Publica eventos de cambio del Golden Record. Suscripcion por sistema destino. L-02" "AWS EventBridge"
            sqsQueue = container "Cola de Mensajeria" "Desacopla el EMPI de los sistemas receptores. Retry con backoff y Dead Letter Queue. RNF-02.4" "Amazon SQS"
            hl7Transformer = container "Transformador HL7v2 a FHIR R4" "Convierte el recurso FHIR Patient al formato HL7 v2 que consume el HCE Oracle. RNF-04.3 Patron Adapter" "AWS Lambda"
            dashboard = container "Dashboard Calidad EMPI" "Indicadores de RF-07: tasa de duplicados, pct DNI validado, fusiones del periodo, cola de revision manual" "INI-06a"
            batchScheduler = container "Scheduler Batch" "Orquesta el proceso nocturno de deduplicacion 00:00 a 05:00. INI-01" "AWS Step Functions"
            alerting = container "Alertas Automaticas" "Dispara alerta si la tasa de duplicados supera el 2pct. RF-07 Scenario 1" "CloudWatch Alarms"

            apigw -> empiCore "Request autenticado con claims de rol" "REST TLS interno"
            empiCore -> masterDb "Lee y escribe Golden Record" "SQL TLS"
            empiCore -> cache "Lookup y warm cache" "Redis Protocol"
            masterDb -> auditStore "Escribe log de auditoria" "CloudWatch API"
            empiCore -> eventBus "Publica evento de cambio" "EventBridge SDK"
            eventBus -> sqsQueue "Encola evento por sistema destino" "EventBridge SQS"
            sqsQueue -> hl7Transformer "Trigger de transformacion" "SQS Lambda trigger"
            batchScheduler -> empiCore "Orquesta batch nocturno de deduplicacion" "Step Functions"
            dashboard -> empiCore "Consulta metricas de calidad" "REST Query"
            dashboard -> auditStore "Lee audit logs" "CloudWatch Query API"
            dashboard -> alerting "Dispara alerta si duplicados mayor 2pct" "interno"
        }

        portal = softwareSystem "Portal Pacientes AWS RDS" "Autogestion digital del paciente: citas, resultados, actualizacion de contacto." "External"
        agenda = softwareSystem "Agenda Medica SaaS" "Programacion de citas. Consulta identidad del EMPI." "External"
        crm = softwareSystem "CRM SaaS Call Center" "Fuente de datos biograficos por telefono. Consulta identidad del EMPI." "External"
        hce = softwareSystem "HCE Oracle 19c On-Prem Lima" "Historia Clinica Electronica. Sistema de registro de episodios clinicos y datos medicamentos." "External"
        lis = softwareSystem "LIS Azure SQL" "Sistema de Laboratorio. 3400 examenes por dia vinculados a EMPI-ID." "External"
        pacs = softwareSystem "PACS x4 sedes mas GCP" "Imagenes DICOM. 920 estudios por dia vinculados a EMPI-ID." "External"
        erp = softwareSystem "ERP Facturacion Nube Privada" "Ciclo de cobro. Consolida facturacion bajo EMPI-ID activo post-merge." "External"
        iamSys = softwareSystem "IAM SSO Centralizado INI-03" "Autenticacion federada OAuth2 OIDC. MFA obligatorio en escritura." "External"

        admisionista -> empi "Registra paciente y consulta identidad" "HTTPS REST JWT"
        medico -> empi "Consulta Golden Record" "HTTPS REST"
        gobDatos -> empi "Gestiona duplicados y calidad del indice" "Dashboard Admin"
        auditor -> empi "Consulta audit log por EMPI-ID" "UI Auditoria Read-only"

        empi -> hce "PATIENT_CREATED y PATIENT_MERGED via HL7 v2" "ESB EventBridge SQS"
        empi -> lis "PATIENT_CREATED FHIR Patient resource" "ESB EventBridge SQS"
        empi -> pacs "PATIENT_CREATED vincula DICOM a EMPI-ID" "ESB EventBridge SQS"
        empi -> erp "PATIENT_MERGED y CONTACT_UPDATED" "ESB EventBridge SQS"
        portal -> empi "Registra paciente y actualiza contacto" "HTTPS REST API GW"
        agenda -> empi "Consulta EMPI-ID del paciente" "HTTPS REST API GW"
        crm -> empi "Envia datos biograficos y consulta identidad" "HTTPS REST API GW"
        empi -> iamSys "Valida tokens JWT y claims de rol" "OAuth2 JWT"

        # Relaciones de nivel Contenedor (C4 Nivel 2)
        admisionista -> apigw "HTTPS REST" "TLS 1.3"
        portal -> apigw "Registra paciente y actualiza contacto" "HTTPS REST"
        agenda -> apigw "Consulta EMPI-ID" "HTTPS REST"
        crm -> apigw "Envia datos biograficos" "HTTPS REST"
        apigw -> iamSys "Valida token JWT y claims" "OAuth2 JWT"
        hl7Transformer -> hce "HL7 v2 ADT" "MLLP TCP"
        sqsQueue -> lis "FHIR Patient resource" "SQS REST"
        sqsQueue -> pacs "FHIR Patient resource" "SQS"
        sqsQueue -> erp "PATIENT_MERGED event" "SQS"
        gobDatos -> dashboard "Monitorea calidad e indice" "HTTPS"

        # Relaciones de nivel Componente (C4 Nivel 3)
        cacheClient -> cache "GET o SET por DNI hash o EMPI-ID" "Redis Protocol"
        repository -> masterDb "SELECT o INSERT sobre Golden Records" "SQL TLS"
        eventPublisher -> eventBus "Publica evento de dominio" "EventBridge SDK"
        batchScheduler -> dedupService "Orquesta el batch nocturno de deduplicacion" "Step Functions"
    }

    views {
        systemContext empi "SystemContext-EMPI" {
            include *
            autoLayout tb
            title "Alt. 1 EMPI Centralizado - C4 Nivel 1 Contexto del Sistema"
        }

        container empi "Containers-EMPI" {
            include *
            autoLayout tb
            title "Alt. 1 EMPI Centralizado - C4 Nivel 2 Contenedores"
        }

        component empiCore "Components-EMPICoreService" {
            include *
            autoLayout tb
            title "Alt. 1 EMPI Centralizado - C4 Nivel 3 Componentes EMPI Core Service"
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
