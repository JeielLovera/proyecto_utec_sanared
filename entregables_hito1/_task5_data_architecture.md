# Task 5: Arquitectura de Datos AS-IS vs TO-BE (ADM Fase C)
## Clínica SanaRed Integrada | Hito 1 — TOGAF ADM Fase C: Arquitectura de Datos

---

## Resumen Ejecutivo

Este entregable desarrolla la Arquitectura de Datos de SanaRed en sus dimensiones AS-IS y TO-BE,
siguiendo la Fase C del TOGAF ADM (Sistemas de Información — Datos). Se identifican siete
dominios de datos diferenciados con sus sistemas custodios actuales, se modela conceptualmente
el universo de trece entidades críticas mediante dos sub-diagramas de Entidad-Relación (ERD), y
se define la estrategia de consolidación de identidad del paciente (Golden Record / Master Patient
Index) para reducir los 126,000 registros duplicados en al menos un 80%.

La fragmentación de datos es el problema transversal más crítico de SanaRed: el mismo paciente
existe con identidades distintas en el portal AWS, la agenda SaaS y la HCE Oracle on-premises,
lo que compromete la seguridad clínica, la continuidad asistencial y la eficiencia financiera. El paso
de AS-IS a TO-BE en datos representa la palanca de mayor impacto para los siete objetivos
estratégicos del directorio.

---

## Sección 5.1: Mapa de Dominios de Datos

### 5.1.1 Tabla de Dominios de Datos — Sistema Custodio AS-IS

La siguiente tabla identifica los siete dominios de datos diferenciados de SanaRed, su sistema
custodio principal en el estado actual, los sistemas secundarios que acceden o generan datos en
ese dominio, y los problemas de integridad o fragmentación detectados.

| # | Dominio de Datos | Sistema Custodio AS-IS | Sistemas Secundarios (acceso/generación) | Problema AS-IS Detectado |
|---|---|---|---|---|
| D1 | **Identidad del Paciente** | HCE Oracle on-premises (N° de historia por sede) | Portal AWS (correo + DNI), Agenda SaaS (nombre + celular + fecha nac.), Admisión local, CRM SaaS | 126,000 registros duplicados; un paciente puede tener hasta 3 identidades distintas por canal |
| D2 | **Clínico / Asistencial** | HCE Oracle on-premises (historia, episodios, diagnósticos, recetas, alergias) | Teleconsulta SaaS (PDF manual), App Móvil (terceros), Admisión local | Sin vista longitudinal; resultados de otras sedes no siempre disponibles en el momento de la atención |
| D3 | **Diagnóstico — Laboratorio** | LIS Azure SQL Managed Instance (órdenes, muestras, resultados de lab) | HCE Oracle (integración HL7 intermitente), Portal AWS (API intermedia), Historia clínica | 9% de órdenes con demora; 18,600 resultados bloqueados durante caída del integrador HL7 en 11 horas |
| D4 | **Diagnóstico — Imágenes** | PACS local por sede (imágenes DICOM) | GCP Cloud Storage (réplica parcial), Visor web multi-sede | Sin vista unificada entre sedes; réplica parcial en GCP; radiólogos no acceden a imágenes de otras clínicas |
| D5 | **Financiero / Facturación** | ERP Nube Privada (facturas, autorizaciones, pólizas, tarifas, cobros) | HCE Oracle (prestaciones), Portal de Pagos Azure App Service, Portales externos aseguradoras | Ciclo de cobro promedio 17 días (hasta 35); 13% de expedientes observados por inconsistencias |
| D6 | **Operacional / Agenda** | Agenda Médica SaaS (citas, disponibilidad médica, horarios, sedes) | Portal AWS, App Móvil, Call Center / CRM SaaS, Admisión local | Cambios de disponibilidad tardan horas en propagarse; sincronización falló en campaña de influenza |
| D7 | **Experiencia del Paciente** | Portal Pacientes AWS (RDS) + CRM SaaS (campañas, reclamos, satisfacción) | App Móvil, App Salud Ocupacional GCP, Encuestas SaaS | Datos de satisfacción desconectados de episodios clínicos; 18% de mensajes con rebote o baja interacción |

### 5.1.2 Diagrama de Paisaje de Datos AS-IS

El diagrama muestra los siete dominios y sus sistemas custodios, con las dependencias y flujos de
datos inter-dominio que revelan la fragmentación actual. Los flujos marcados con `⚠️` representan
puntos de quiebre donde la integridad de datos no está garantizada.

```mermaid
graph TD
    subgraph D1["D1 — Identidad del Paciente"]
        HCE_ID["📦 HCE Oracle on-premises\nN° Historia por sede"]
        AGN_ID["📦 Agenda SaaS\nnombre + celular + fecha_nac"]
        PRT_ID["📦 Portal AWS RDS\ncorreo + DNI"]
    end

    subgraph D2["D2 — Clínico / Asistencial"]
        HCE_CLI["📦 HCE Oracle\nHistoria, Episodio, Diagnóstico\nReceta, Alergia, Evolución"]
        TELE["📦 Teleconsulta SaaS\nPDF resumen (carga manual)"]
    end

    subgraph D3["D3 — Diagnóstico / Lab"]
        LIS["📦 LIS Azure SQL MI\nOrden, Muestra, Resultado"]
    end

    subgraph D4["D4 — Diagnóstico / Imágenes"]
        PACS["📦 PACS local x sede\nImágenes DICOM"]
        GCP_PACS["📦 GCP Cloud Storage\nRéplica parcial PACS"]
    end

    subgraph D5["D5 — Financiero / Facturación"]
        ERP["📦 ERP Nube Privada\nFactura, Póliza, Autorización\nTarifa, Cobro"]
        PAY["📦 Portal Pagos Azure\nApp Service"]
    end

    subgraph D6["D6 — Operacional / Agenda"]
        AGN["📦 Agenda Médica SaaS\nCita, Disponibilidad, Horario"]
        CRM["📦 CRM SaaS\nCall Center, Reclamos"]
    end

    subgraph D7["D7 — Experiencia del Paciente"]
        PRT["📦 Portal Pacientes AWS\nResultados, Notificaciones"]
        GCP_SO["📦 App Salud Ocup. GCP\nProgramas corporativos"]
    end

    %% Flujos entre dominios — puntos de integración y quiebre
    AGN_ID  -->|"⚠️ Sin match único\n(identidades distintas)"| HCE_ID
    PRT_ID  -->|"⚠️ Sin match único\n(correo vs historia)"| HCE_ID
    HCE_CLI -->|"Prestaciones\n(codificación incompleta)"| ERP
    LIS     -->|"⚠️ HL7 integrador\n(intermitente)"| HCE_CLI
    LIS     -->|"⚠️ API intermedia\n(sin caché)"| PRT
    PACS    -->|"Réplica parcial"| GCP_PACS
    ERP     -->|"Autorizaciones\n(portales externos)"| ERP
    AGN     -->|"Disponibilidad médica\n(sincronización demorada)"| PRT
    CRM     -->|"Campañas / reclamos\n(sin episodio clínico)"| PRT
```

---

## Sección 5.2: Modelo Conceptual de Datos — ERD

El modelo conceptual incluye las 13 entidades críticas del negocio de SanaRed. Dado que el
conjunto de relaciones supera 40, el ERD se divide en dos sub-diagramas complementarios que
comparten las entidades de enlace (Paciente, Episodio Clínico, Médico) para mantener consistencia.

> **Entidades compartidas entre sub-diagramas:** `PACIENTE`, `EPISODIO_CLINICO`, `MEDICO`

---

### 5.2.1 ERD Parte 1 — Núcleo Clínico y Asistencial

Cubre el flujo de atención: desde la identidad del paciente hasta el registro clínico, incluyendo
historia clínica, episodio, diagnóstico, orden médica, resultado, receta y consentimiento.

```mermaid
erDiagram

    PACIENTE {
        string id_paciente PK
        string numero_historia
        string dni
        string nombre
        string correo
        string celular
        date fecha_nacimiento
        string canal_registro
        string estado_deduplicacion
    }

    HISTORIA_CLINICA {
        string id_historia PK
        string id_paciente FK
        date fecha_apertura
        string sede_origen
        string alergias
        string antecedentes
        string grupo_sanguineo
        string estado
    }

    EPISODIO_CLINICO {
        string id_episodio PK
        string id_historia FK
        string id_paciente FK
        string id_medico FK
        string id_cita FK
        date fecha_inicio
        date fecha_cierre
        string tipo_atencion
        string sede
        string motivo_consulta
        string estado
    }

    MEDICO {
        string id_medico PK
        string nombre
        string especialidad
        string numero_colegiatura
        string sede_principal
        string estado
    }

    DIAGNOSTICO {
        string id_diagnostico PK
        string id_episodio FK
        string id_medico FK
        string codigo_cie10
        string descripcion
        string tipo
        date fecha_registro
        string presuncion
    }

    ORDEN_MEDICA {
        string id_orden PK
        string id_episodio FK
        string id_medico FK
        string id_diagnostico FK
        string tipo_orden
        string descripcion
        string prioridad
        date fecha_emision
        string estado
    }

    RESULTADO {
        string id_resultado PK
        string id_orden FK
        string id_episodio FK
        string tipo_resultado
        string valores
        string unidades
        string referencia_normal
        date fecha_resultado
        string estado_sincronizacion
        boolean disponible_portal
    }

    RECETA {
        string id_receta PK
        string id_episodio FK
        string id_medico FK
        string medicamento
        string dosis
        string frecuencia
        string duracion
        date fecha_emision
        string tipo
    }

    CONSENTIMIENTO {
        string id_consentimiento PK
        string id_paciente FK
        string id_episodio FK
        string tipo_consentimiento
        date fecha_firma
        string estado
        string repositorio_doc
    }

    %% Cardinalidades — Núcleo Clínico
    PACIENTE           ||--o{ HISTORIA_CLINICA   : "tiene (1 paciente → N historias por sede)"
    HISTORIA_CLINICA   ||--o{ EPISODIO_CLINICO   : "contiene"
    PACIENTE           ||--o{ EPISODIO_CLINICO   : "protagoniza"
    MEDICO             ||--o{ EPISODIO_CLINICO   : "atiende"
    EPISODIO_CLINICO   ||--o{ DIAGNOSTICO        : "genera"
    MEDICO             ||--o{ DIAGNOSTICO        : "registra"
    EPISODIO_CLINICO   ||--o{ ORDEN_MEDICA       : "origina"
    MEDICO             ||--o{ ORDEN_MEDICA       : "emite"
    DIAGNOSTICO        ||--o{ ORDEN_MEDICA       : "justifica"
    ORDEN_MEDICA       ||--o{ RESULTADO          : "produce"
    EPISODIO_CLINICO   ||--o{ RESULTADO          : "incluye"
    EPISODIO_CLINICO   ||--o{ RECETA             : "genera"
    MEDICO             ||--o{ RECETA             : "prescribe"
    PACIENTE           ||--o{ CONSENTIMIENTO     : "firma"
    EPISODIO_CLINICO   ||--o{ CONSENTIMIENTO     : "requiere"
```

---

### 5.2.2 ERD Parte 2 — Administrativo, Financiero y Agenda

Cubre el flujo administrativo y financiero: desde la programación de la cita hasta la generación de
la factura, incluyendo la autorización de aseguradora y la póliza de cobertura.

```mermaid
erDiagram

    PACIENTE {
        string id_paciente PK
        string dni
        string nombre
        string canal_registro
        string estado_deduplicacion
    }

    MEDICO {
        string id_medico PK
        string nombre
        string especialidad
        string sede_principal
    }

    EPISODIO_CLINICO {
        string id_episodio PK
        string id_paciente FK
        string id_medico FK
        string id_cita FK
        date fecha_inicio
        string tipo_atencion
        string sede
    }

    CITA {
        string id_cita PK
        string id_paciente FK
        string id_medico FK
        string id_poliza FK
        date fecha_hora
        string sede
        string especialidad
        string canal_agendamiento
        string estado
        string motivo
    }

    POLIZA {
        string id_poliza PK
        string id_paciente FK
        string aseguradora
        string numero_poliza
        string tipo_cobertura
        date vigencia_inicio
        date vigencia_fin
        string coberturas
        string topes
        string estado
    }

    AUTORIZACION {
        string id_autorizacion PK
        string id_poliza FK
        string id_episodio FK
        string id_cita FK
        string codigo_autorizacion
        string procedimiento_autorizado
        date fecha_solicitud
        date fecha_respuesta
        string estado
        string canal_gestion
    }

    FACTURA {
        string id_factura PK
        string id_episodio FK
        string id_paciente FK
        string id_autorizacion FK
        string id_poliza FK
        string numero_factura
        decimal monto_total
        decimal copago
        decimal monto_aseguradora
        date fecha_emision
        string estado
        int dias_ciclo_cobro
    }

    %% Cardinalidades — Administrativo / Financiero
    PACIENTE          ||--o{ CITA             : "agenda"
    MEDICO            ||--o{ CITA             : "es asignado a"
    CITA              ||--o|  EPISODIO_CLINICO : "origina"
    PACIENTE          ||--o{ POLIZA           : "tiene"
    POLIZA            ||--o{ CITA             : "cubre"
    POLIZA            ||--o{ AUTORIZACION     : "genera"
    EPISODIO_CLINICO  ||--o{ AUTORIZACION     : "requiere"
    CITA              ||--o{ AUTORIZACION     : "necesita"
    EPISODIO_CLINICO  ||--||  FACTURA          : "liquida en"
    PACIENTE          ||--o{ FACTURA          : "recibe"
    AUTORIZACION      ||--o|  FACTURA          : "respalda"
    POLIZA            ||--o{ FACTURA          : "determina cobertura de"
```

---

## Sección 5.3: Estrategia TO-BE — Golden Record y Consolidación de Identidad del Paciente

### 5.3.1 Contexto del Problema AS-IS

| Indicador | Valor AS-IS | Impacto |
|---|---|---|
| Registros duplicados de pacientes | 126,000 | Riesgo clínico, facturas duplicadas, reclamos |
| Campos de match por canal | Portal: correo+DNI / Agenda: nombre+celular+fecha_nac / HCE: N° historia sede | Sin llave única común |
| Proceso de deduplicación actual | Manual, reportes mensuales | Reactivo, sin tiempo real |
| Casos con historia fragmentada en atención | Identificados (ej. paciente anticoagulado en emergencia) | Riesgo de seguridad del paciente |
| Resultados no asociados al episodio correcto | 9% de órdenes diagnósticas con demora | Reprocesos, costos, frustración |

### 5.3.2 Diseño de la Estrategia Golden Record (MPI — Master Patient Index)

La estrategia TO-BE se basa en tres pilares: **Identidad Única**, **Sincronización Confiable** y
**Gobierno de Datos Continuo**.

#### Pilar 1 — Master Patient Index (MPI) como Sistema de Registro de Identidad

- Se implementa un **MPI centralizado** que actúa como fuente de verdad para la identidad del paciente. Cada paciente recibe un **Enterprise Patient ID (EPID)** único en toda la red SanaRed.
- El EPID reemplaza progresivamente los identificadores locales (N° historia por sede, correo portal, ID agenda SaaS) como referencia cross-sistema.
- El MPI almacena todos los identificadores históricos como alias para garantizar trazabilidad y compatibilidad hacia atrás.

#### Pilar 2 — Motor de Matching Probabilístico + Determinístico

El proceso de deduplicación utiliza un motor de dos capas:

| Capa | Método | Campos clave | Acción |
|---|---|---|---|
| Determinística | Coincidencia exacta | DNI + fecha de nacimiento | Match automático → fusión de registros |
| Probabilística | Score Jaro-Winkler / Soundex | Nombre, celular, correo, dirección | Score ≥ 0.92 → fusión automática; 0.75–0.91 → revisión humana |
| Reglas de negocio | Dependientes familiares | Póliza + titular + relación | Registro vinculado, no fusionado |
| Exclusión | Falsos positivos | Nombres idénticos, fechas similares | Cola de revisión con evidencia |

#### Pilar 3 — Gobierno de Datos y Calidad Continua

- **Validación en el punto de entrada**: todos los canales (portal, agenda, admisión, call center) consultan el MPI antes de crear un nuevo registro. Si existe match, se reutiliza el EPID.
- **Panel de calidad de identidad**: dashboard operativo con tasa de duplicados, matches pendientes, registros sin DNI y evolución mensual.
- **SLA de resolución**: duplicados de alta prioridad (pacientes en emergencia, anticoagulados, crónicos) resueltos en < 2 horas; cola general en < 48 horas.

### 5.3.3 Diagrama de Flujo TO-BE — Golden Record

```mermaid
graph TD
    subgraph CANALES["Canales de Entrada de Identidad"]
        CH1["🌐 Portal Web AWS"]
        CH2["📱 App Móvil"]
        CH3["📞 Call Center / CRM"]
        CH4["🏥 Admisión Presencial"]
        CH5["📅 Agenda SaaS"]
    end

    subgraph MPI_ENGINE["Master Patient Index — Núcleo de Identidad"]
        MATCH["Motor de Matching\nDeterminístico + Probabilístico"]
        EPID["🔑 Enterprise Patient ID\n(EPID Único)"]
        ALIAS["📋 Registro de Alias\n(IDs históricos por sistema)"]
        QUEUE["🔍 Cola de Revisión\nHumana (score 0.75-0.91)"]
        GOV["📊 Panel de Gobierno\nCalidad de Identidad"]
    end

    subgraph SISTEMAS_CLINICOS["Sistemas Clínicos y Operativos"]
        HCE["HCE Oracle\non-premises"]
        LIS["LIS Azure\nSQL MI"]
        AGN["Agenda\nSaaS"]
        ERP["ERP\nNube Privada"]
        PRT_AWS["Portal\nAWS RDS"]
    end

    subgraph GOLDEN["Golden Record — Vista Unificada del Paciente"]
        GR["🏆 Golden Record\nVista 360° del Paciente\nHistoria + Citas + Resultados\nFacturas + Consentimientos"]
    end

    CH1 & CH2 & CH3 & CH4 & CH5 -->|"Solicitud de\nidentificación"| MATCH
    MATCH -->|"Match exacto\n(DNI + fecha nac.)"| EPID
    MATCH -->|"Score < 0.75\nnuevo registro"| EPID
    MATCH -->|"Score 0.75-0.91\npendiente revisión"| QUEUE
    QUEUE -->|"Resolución\noperador MPI"| EPID
    EPID --- ALIAS
    EPID --> GOV

    EPID -->|"EPID propagado\nvía API / evento"| HCE
    EPID -->|"EPID propagado"| LIS
    EPID -->|"EPID propagado"| AGN
    EPID -->|"EPID propagado"| ERP
    EPID -->|"EPID propagado"| PRT_AWS

    HCE & LIS & AGN & ERP & PRT_AWS -->|"Datos federados\npor EPID"| GR
```

### 5.3.4 Metas y KPIs de la Estrategia Golden Record

| KPI | Línea Base AS-IS | Meta TO-BE (Año 1) | Meta TO-BE (Año 2) |
|---|---|---|---|
| Registros duplicados activos | 126,000 | ≤ 25,200 (−80%) | ≤ 5,000 (−96%) |
| % pacientes con EPID único | 0% | 75% | 99% |
| Tiempo de deduplicación (lote) | Mensual (manual) | Diario (automático) | Tiempo real (evento) |
| Tasa de match automático | 0% | ≥ 85% | ≥ 95% |
| Resultados asociados al episodio correcto | 91% (9% con demora) | 97% | 99.5% |
| Ciclo de facturación promedio | 17 días | 10 días | 7 días |
| Reclamos por inconsistencia de identidad | 7,900 / año | ≤ 2,000 / año | ≤ 500 / año |

### 5.3.5 Fases de Implementación del Golden Record

```mermaid
gantt
    title Roadmap de Consolidación de Identidad — Golden Record
    dateFormat  YYYY-MM
    axisFormat  %b %Y

    section Fase 1 — Fundación (Corto plazo)
    Definir estándar EPID y modelo MPI          :crit, f1a, 2025-01, 2025-03
    Implementar motor matching (det + prob)      :crit, f1b, 2025-02, 2025-05
    Deduplicación batch inicial (126K registros) :crit, f1c, 2025-04, 2025-07
    Integrar Portal AWS y Agenda SaaS al MPI     :f1d, 2025-05, 2025-08

    section Fase 2 — Integración (Mediano plazo)
    Integrar HCE Oracle al MPI (vía API)         :f2a, 2025-08, 2025-11
    Integrar LIS Azure y PACS al MPI             :f2b, 2025-09, 2026-01
    Integrar ERP y CRM al MPI                   :f2c, 2025-11, 2026-03
    Panel de gobierno de calidad de datos        :f2d, 2025-10, 2026-02

    section Fase 3 — Madurez (Largo plazo)
    Matching en tiempo real (event-driven)       :f3a, 2026-02, 2026-06
    Golden Record con vista 360° operativa       :f3b, 2026-04, 2026-08
    Analítica clínica sobre identidad unificada  :f3c, 2026-06, 2026-12
```

---

## Referencias al Marco TOGAF

| Componente TOGAF | Artefacto en este entregable |
|---|---|
| Fase C — Arquitectura de Sistemas de Información (Datos) | Mapa de Dominios, ERD Partes 1 y 2 |
| Architecture Vision (Fase A) | Problema de 126K duplicados como driver central |
| Requirements Management | Req. 5: Dominios, ERD 13 entidades, Golden Record |
| Data Principles | Unicidad de identidad, Calidad en la fuente, Trazabilidad |
| Transition Architecture | Roadmap Golden Record Fases 1–3 |
| Gap Analysis (Fase E) | KPI tabla AS-IS vs TO-BE por dominio de datos |
