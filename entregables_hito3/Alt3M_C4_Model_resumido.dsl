workspace "EMPI SanaRed - Alt. 3 Mejorada (resumido)" "Vista resumida C4 (Contexto + Contenedores) del EMPI multicloud concordante. Para una diapositiva unica. Iniciativa INI-01/INI-13 - Clinica SanaRed." {

    !identifiers hierarchical

    model {

        // Personas
        paciente  = person "Paciente"
        admision  = person "Admisionista"
        medico    = person "Medico / Radiologo"
        opDatos   = person "Operador Gobierno de Datos"

        // Sistemas existentes de SanaRed  (tag "Existente" como 3er argumento posicional)
        portal = softwareSystem "Portal de Pacientes" "AWS/RDS" "Existente"
        agenda = softwareSystem "Agenda SaaS" "SaaS" "Existente"
        hce    = softwareSystem "HCE Oracle" "on-prem, HL7 v2" "Existente"
        lis    = softwareSystem "LIS" "Azure SQL" "Existente"
        pacs   = softwareSystem "PACS" "DICOM local + GCP" "Existente"
        erp    = softwareSystem "ERP Facturacion" "nube privada" "Existente"

        // EMPI
        empi = softwareSystem "EMPI - Identidad Unificada" "EMPI-ID canonico, deduplicacion y vista 360." {

            group "AWS - Dominio del Paciente" {
                apiGwExt   = container "API Gateway + WAF" "Perimetro externo" "AWS API Gateway" "AWS"
                core       = container "EMPI Core / PatientAggregate" "Identidad + matching tiempo real" "FastAPI / ECS Fargate" "AWS"
                searchIdx  = container "Indice de Matching" "Blocking a escala" "OpenSearch / Elasticsearch" "AWS"
                cache      = container "Cache de Identidad" "Lookup DNI" "ElastiCache Redis" "AWS"
                eventStore = container "Event Store + Golden Record" "Eventos append-only + proyeccion" "Amazon RDS PostgreSQL" "AWS"
            }
            group "Azure - Integracion Clinica y Financiera" {
                apim      = container "APIM (mTLS interno)" "Perimetro interno" "Azure API Management" "Azure"
                adClinico = container "Adaptadores Clinicos" "HCE HL7v2-FHIR, LIS" "Azure Functions" "Azure"
                adFinanc  = container "Adaptador Financiero" "ERP, Pagos" "Azure Functions" "Azure"
            }
            group "GCP - Imagenes y Analitica" {
                healthcare = container "FHIR + DICOM Store" "Vincula PACS al EMPI-ID" "GCP Cloud Healthcare API" "GCP"
                analytics  = container "Analitica, 360 y Batch" "Vista 360 + Splink" "BigQuery" "GCP"
            }
            group "Neutral - Backbone de Eventos" {
                bus = container "Bus de Eventos" "Propagacion cross-cloud" "Kafka (Confluent / Redpanda)" "Neutral"
            }
        }

        // Relaciones
        paciente  -> portal "Se registra / consulta"
        admision  -> empi.apiGwExt "Admite"
        medico    -> empi.analytics "Vista 360 / imagenes"
        opDatos   -> empi.core "Revisa fusiones"

        portal -> empi.apiGwExt "match FHIR"
        agenda -> empi.apiGwExt "Valida identidad"

        empi.apiGwExt   -> empi.core "Enruta"
        empi.core       -> empi.cache "Lookup"
        empi.core       -> empi.searchIdx "Blocking"
        empi.core       -> empi.eventStore "Append + proyecta"
        empi.core       -> empi.bus "Publica identity.patient.*"
        empi.bus        -> empi.adClinico "eventos clinicos"
        empi.bus        -> empi.adFinanc "patient.merged"
        empi.bus        -> empi.healthcare "patient.created"
        empi.adClinico  -> empi.apim "mTLS"
        empi.apim       -> hce "ADT (HL7 v2)"
        empi.apim       -> lis "Vincula resultados"
        empi.adFinanc   -> erp "EMPI-ID activo"
        empi.healthcare -> pacs "Etiqueta DICOM con EMPI-ID"
        empi.healthcare -> empi.analytics "Metadatos imagen"
        empi.eventStore -> empi.analytics "Datos identidad"
    }

    views {

        systemContext empi "C1_Contexto" "Nivel 1 - Contexto" {
            include *
            autolayout lr
        }

        container empi "C2_Contenedores" "Nivel 2 - Contenedores (resumido)" {
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
        }
    }
}
