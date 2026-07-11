workspace "EMPI SanaRed - Alternativa 3 Mejorada (Multicloud Concordante)" "Modelo C4 del EMPI (Identidad Unificada de Pacientes) con placement por concordancia de dominio: AWS = paciente, Azure = clinico/financiero, GCP = imagenes/analitica, y bus de eventos neutral. Iniciativa INI-01/INI-13 - Clinica SanaRed Integrada - Hito 3." {

    !identifiers hierarchical

    model {

        // ============================================================
        // PERSONAS
        // ============================================================
        paciente  = person "Paciente" "Se registra y consulta sus datos por canales digitales."
        admision  = person "Admisionista" "Registra y admite pacientes en sede."
        medico    = person "Medico" "Consulta la vista 360 del paciente."
        radiologo = person "Medico Radiologo" "Consulta imagenes inter-sede."
        opDatos   = person "Operador Gobierno de Datos" "Revisa y resuelve fusiones de identidad."

        // ============================================================
        // SISTEMAS EXISTENTES DE SANARED (externos al EMPI)
        // ============================================================
        portal = softwareSystem "Portal de Pacientes" "Canal digital del paciente (AWS/RDS)." {
            tags "Existente"
        }
        agenda = softwareSystem "Agenda SaaS" "Gestion de citas." {
            tags "Existente"
        }
        hce = softwareSystem "HCE Oracle" "Historia clinica electronica (on-premises, HL7 v2)." {
            tags "Existente"
        }
        lis = softwareSystem "LIS" "Laboratorio (Azure SQL Managed Instance)." {
            tags "Existente"
        }
        pacs = softwareSystem "PACS" "Imagenes diagnosticas DICOM (local por sede + replica GCP)." {
            tags "Existente"
        }
        erp = softwareSystem "ERP Facturacion" "Facturacion y cobros (nube privada)." {
            tags "Existente"
        }
        admisionMod = softwareSystem "Modulo de Admision (on-prem)" "Registro/admision por sede; opera sobre la HCE. Consulta el EMPI en tiempo real al admitir." {
            tags "Existente"
        }

        // ============================================================
        // EMPI - Sistema en foco
        // ============================================================
        empi = softwareSystem "EMPI - Identidad Unificada de Pacientes" "Crea y mantiene el EMPI-ID canonico, deduplica y ofrece la vista 360 del paciente." {

            group "AWS - Dominio del Paciente" {
                apiGwExt = container "API Gateway + WAF" "Perimetro publico del canal de paciente (Portal, app movil): rate limiting, WAF, circuit breaker." "AWS API Gateway" {
                    tags "AWS"
                }
                apiGwInt = container "API GW privado / ALB (mTLS interno)" "Entrada de sistemas internos (Modulo de Admision on-prem, Agenda) por mTLS; sin WAF y sin salto a Azure." "AWS ALB / API Gateway privado" {
                    tags "AWS"
                }
                core = container "EMPI Core / PatientAggregate" "Identidad, commands de dominio y matching en tiempo real." "FastAPI / ECS Fargate" {
                    tags "AWS"
                    apiRest        = component "API REST / FHIR" "Expone Patient y la operacion match (PDQm)." "FastAPI"
                    cmdHandler     = component "Command Handler" "RegisterPatient, MergeRecords, RevertMerge, DeactivateRecord, ConfirmDistinct, UpdateContact." "Python"
                    matcher        = component "Real-Time Matcher" "Estrategia 3 pasos: cache -> blocking -> scoring." "Python / jellyfish"
                    domainRules    = component "Domain Rules" "Umbrales 0.95/0.85 y precedencia, configurables en caliente." "Parameter Store"
                    projector      = component "Projector" "Construye golden_record_view desde los eventos." "Python"
                    eventPublisher = component "Event Publisher" "Publica los eventos de dominio al bus." "Python"
                }
                searchIdx = container "Indice de Matching" "Blocking fuzzy a escala (garantiza volumetria)." "Amazon OpenSearch / Elasticsearch" {
                    tags "AWS"
                }
                cache = container "Cache de Identidad" "Lookup DNI < 50 ms (write-through)." "Amazon ElastiCache Redis" {
                    tags "AWS"
                }
                eventStore = container "Event Store + Golden Record" "Eventos append-only (fuente de verdad) + proyeccion de lectura." "Amazon RDS PostgreSQL" {
                    tags "AWS"
                }
            }

            group "Azure - Integracion Clinica y Financiera" {
                apim = container "APIM (mTLS)" "Perimetro de SALIDA del EMPI hacia legados (HCE/LIS/ERP)." "Azure API Management" {
                    tags "Azure"
                }
                adClinico = container "Adaptadores Clinicos" "HCE (HL7 v2 <-> FHIR) y LIS." "Azure Functions" {
                    tags "Azure"
                }
                adFinanc = container "Adaptador Financiero" "ERP y Portal de Pagos." "Azure Functions" {
                    tags "Azure"
                }
            }

            group "GCP - Imagenes y Analitica" {
                healthcare = container "FHIR + DICOM Store" "Vincula estudios del PACS al EMPI-ID." "GCP Cloud Healthcare API" {
                    tags "GCP"
                }
                analytics = container "Analitica, Vista 360 y Batch" "Vista 360 materializada + deduplicacion batch (Splink)." "BigQuery" {
                    tags "GCP"
                }
            }

            group "Neutral - Backbone de Eventos" {
                bus = container "Bus de Eventos" "Propagacion cross-cloud (topics identity.patient.*)." "Kafka (Confluent / Redpanda)" {
                    tags "Neutral"
                }
            }
        }

        // ============================================================
        // RELACIONES - Contexto y Contenedor
        // ============================================================
        paciente  -> portal "Se registra / consulta"
        admision  -> admisionMod "Admite en ventanilla"
        medico    -> empi.analytics "Consulta vista 360"
        radiologo -> empi.healthcare "Consulta imagenes inter-sede (por EMPI-ID)"
        opDatos   -> empi.core "Revisa fusiones"

        portal      -> empi.apiGwExt "Valida/crea identidad (match FHIR)"
        agenda      -> empi.apiGwInt "Valida identidad (mTLS)"
        admisionMod -> empi.apiGwInt "Consulta/crea identidad (mTLS, Direct Connect/VPN)"
        admisionMod -> hce "Opera sobre HCE"

        empi.apiGwExt   -> empi.core "Enruta (paciente)"
        empi.apiGwInt   -> empi.core "Enruta (interno)"
        empi.core       -> empi.cache "Lookup DNI"
        empi.core       -> empi.searchIdx "Blocking de candidatos"
        empi.core       -> empi.eventStore "Append eventos + proyecta"
        empi.core       -> empi.bus "Publica identity.patient.*"
        empi.bus        -> empi.adClinico "identity.patient.*"
        empi.bus        -> empi.adFinanc "identity.patient.merged"
        empi.bus        -> empi.healthcare "identity.patient.created"
        empi.adClinico  -> empi.apim "mTLS"
        empi.apim       -> hce "ADT A28/A40 (HL7 v2)"
        empi.apim       -> lis "Vincula resultados al EMPI-ID"
        empi.adFinanc   -> erp "EMPI-ID activo"
        empi.healthcare -> pacs "Etiqueta estudios DICOM con EMPI-ID"
        empi.healthcare -> empi.analytics "Metadatos de imagen"
        empi.eventStore -> empi.analytics "Datos de identidad"

        // ============================================================
        // RELACIONES - Componente (EMPI Core)
        // ============================================================
        empi.apiGwExt              -> empi.core.apiRest "HTTPS (paciente)"
        empi.apiGwInt              -> empi.core.apiRest "HTTPS (mTLS interno)"
        empi.core.apiRest          -> empi.core.cmdHandler "Invoca commands"
        empi.core.apiRest          -> empi.core.matcher "Consulta identidad"
        empi.core.matcher          -> empi.cache "Lookup DNI"
        empi.core.matcher          -> empi.searchIdx "Blocking"
        empi.core.cmdHandler       -> empi.core.domainRules "Valida invariantes"
        empi.core.cmdHandler       -> empi.eventStore "Persiste eventos"
        empi.core.cmdHandler       -> empi.core.eventPublisher "Emite evento"
        empi.core.eventPublisher   -> empi.bus "Publica"
        empi.core.projector        -> empi.eventStore "Lee eventos / escribe proyeccion"

        // ============================================================
        // DESPLIEGUE - Produccion (multicloud concordante)
        // ============================================================
        produccion = deploymentEnvironment "Produccion" {

            deploymentNode "AWS - Dominio del Paciente" {
                tags "AWS"
                deploymentNode "Amazon API Gateway" {
                    containerInstance empi.apiGwExt
                }
                deploymentNode "API Gateway privado / ALB (mTLS)" {
                    containerInstance empi.apiGwInt
                }
                deploymentNode "ECS Fargate (Multi-AZ)" {
                    containerInstance empi.core
                }
                deploymentNode "Amazon OpenSearch Service" {
                    containerInstance empi.searchIdx
                }
                deploymentNode "Amazon ElastiCache" {
                    containerInstance empi.cache
                }
                deploymentNode "Amazon RDS PostgreSQL (Multi-AZ)" {
                    containerInstance empi.eventStore
                }
            }

            deploymentNode "Confluent Cloud (region AWS)" {
                tags "Neutral"
                containerInstance empi.bus
            }

            deploymentNode "Azure - Integracion Clinica/Financiera" {
                tags "Azure"
                deploymentNode "Azure API Management" {
                    containerInstance empi.apim
                }
                deploymentNode "Azure Functions" {
                    containerInstance empi.adClinico
                    containerInstance empi.adFinanc
                }
                deploymentNode "Azure SQL Managed Instance" {
                    softwareSystemInstance lis
                }
            }

            deploymentNode "GCP - Imagenes y Analitica" {
                tags "GCP"
                deploymentNode "Cloud Healthcare API" {
                    containerInstance empi.healthcare
                }
                deploymentNode "BigQuery" {
                    containerInstance empi.analytics
                }
                deploymentNode "PACS (replica GCP)" {
                    softwareSystemInstance pacs
                }
            }

            deploymentNode "On-premises Lima" {
                tags "On-prem"
                deploymentNode "HCE Oracle" {
                    softwareSystemInstance hce
                }
                deploymentNode "Modulo de Admision (por sede)" {
                    softwareSystemInstance admisionMod
                }
            }
        }
    }

    // ================================================================
    // VISTAS
    // ================================================================
    views {

        systemContext empi "C1_Contexto" "Nivel 1 - Contexto del EMPI" {
            include *
            autolayout lr
        }

        container empi "C2_Contenedores" "Nivel 2 - Contenedores multicloud concordantes" {
            include *
            autolayout lr
        }

        component empi.core "C3_ComponentesCore" "Nivel 3 - Componentes del EMPI Core" {
            include *
            autolayout lr
        }

        deployment empi produccion "C4_Despliegue" "Despliegue multicloud concordante (Produccion)" {
            include *
            autolayout lr
        }

        styles {
            element "Person" {
                shape person
                background #08427b
                color #ffffff
            }
            element "Software System" {
                background #1168bd
                color #ffffff
            }
            element "Existente" {
                background #6b6b6b
                color #ffffff
            }
            element "Container" {
                color #ffffff
            }
            element "Component" {
                background #85bbf0
                color #000000
            }
            element "AWS" {
                background #ff9900
                color #000000
            }
            element "Azure" {
                background #0078d4
                color #ffffff
            }
            element "GCP" {
                background #34a853
                color #ffffff
            }
            element "Neutral" {
                background #f57f17
                color #000000
            }
            element "On-prem" {
                background #b0653c
                color #ffffff
            }
        }
    }
}
