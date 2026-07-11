# Plan de Migración — Clínica SanaRed Integrada
## TOGAF ADM Fase F | Migration Planning

> **Base:** Fase E (Oportunidades y Soluciones) — 6 iniciativas consolidadas + bloque adicional de Analítica/IA
> **Insumo:** 16 sub-iniciativas técnicas detalladas en el Gap Analysis del Hito 1

---

## 1. Mapeo Final — De 16 Sub-Iniciativas a 7 Bloques de Iniciativa

El bloque de Seguridad y Observabilidad se dividió en dos iniciativas independientes (Observabilidad y Resiliencia Multinube / Seguridad y Gobierno de Datos), tal como ya estaban definidas por el equipo, separando explícitamente las sub-iniciativas técnicas que antes vivían combinadas en INI-06. Se agrega un séptimo bloque de Analítica Clínica con IA para alojar el Data Lakehouse y las iniciativas que no calzaban en las 6 originales.

| # | Iniciativa Consolidada (Fase E) | Sub-iniciativas Técnicas (Gap Analysis) | Horizonte |
|---|---|---|---|
| **1** | **Identidad Unificada de Pacientes (EMPI)** | INI-01 · EMPI — Matching + Deduplicación Batch (126K registros) + Integración Portal/Agenda<br>INI-13 · EMPI — Deduplicación en Tiempo Real + Golden Record 360° | Fase 1 → Fase 3 |
| **2** | **Interoperabilidad del Ciclo Clínico** | INI-02 · API Gateway / ESB (mensajería garantizada, sustituye HL7 punto a punto)<br>INI-05 · HCE Modernización — Arquitectura y Piloto<br>INI-07 · Integración Teleconsulta + Firma Electrónica + Agenda al HCE<br>INI-09 · PACS Cloud Consolidado (GCP Healthcare API)<br>INI-12 · HCE Migración Completa y Go-Live | Fase 1 → Fase 2 |
| **3** | **Omnicanalidad y Vista Longitudinal** | INI-04 · Resiliencia del Portal de Pacientes (CDN + Caché + Auto-scaling)<br>INI-11 · Canal Digital Unificado (Portal + App Móvil)<br>INI-14 · Integración de Salud Ocupacional al Golden Record | Fase 1 → Fase 3 |
| **4** | **Automatización Administrativa y Facturación** | INI-08 · ERP — Migración a Cloud Pública + Interfaz FHIR con HCE<br>INI-10 · Autorizaciones Electrónicas con Aseguradoras | Fase 2 |
| **5** | **Observabilidad y Resiliencia Multinube** | INI-06a · Dashboard de Monitoreo de Interfaces Clínicas (HL7/ESB) + Métricas, Logs y Trazas<br>INI-06b · Alarmas y SLOs por Servicio Crítico | Fase 1 |
| **6** | **Seguridad y Gobierno de Datos** | INI-03 · IAM Centralizado y SSO Multinube<br>INI-06c · RBAC + Cifrado + Trazabilidad de Consulta a Datos Sensibles (Zero Trust) | Fase 1 |
| **7** | **Analítica Clínica y Operativa con IA** *(bloque nuevo)* | INI-15 · CRM Integrado a Episodios Clínicos<br>INI-16 · Data Lakehouse + Analítica Clínica/Operativa<br>INI-17 · Capa de IA sobre el Lakehouse (modelos predictivos: demanda, readmisión, riesgo clínico) | Fase 3 |

> **Nota sobre INI-17:** se añade como extensión natural de INI-16 para capitalizar el Data Lakehouse con casos de uso de IA (predicción de demanda ambulatoria, riesgo de readmisión, priorización de resultados críticos), dado que la infraestructura de datos consolidados es condición previa para cualquier modelo de IA clínica responsable.

---

## 2. Diagrama de Mapeo 16 → 7

```mermaid
flowchart LR
    subgraph ORIG["16 Sub-iniciativas — Gap Analysis"]
        direction TB
        S01["INI-01 · MPI Batch"]
        S13["INI-13 · MPI Tiempo Real"]
        S02["INI-02 · API Gateway/ESB"]
        S05["INI-05 · HCE Piloto"]
        S07["INI-07 · Teleconsulta+Firma+Agenda"]
        S09["INI-09 · PACS Cloud"]
        S12["INI-12 · HCE Go-Live"]
        S04["INI-04 · Portal Resiliente"]
        S11["INI-11 · Canal Unificado"]
        S14["INI-14 · Salud Ocupacional"]
        S08["INI-08 · ERP Migración"]
        S10["INI-10 · Autorizaciones"]
        S06a["INI-06a · Dashboard Monitoreo"]
        S06b["INI-06b · Alarmas/SLOs"]
        S03["INI-03 · IAM/SSO"]
        S06c["INI-06c · RBAC+Cifrado"]
        S15["INI-15 · CRM-Episodios"]
        S16["INI-16 · Data Lakehouse"]
        S17["INI-17 · IA Clínica"]
    end

    subgraph CONS["7 Bloques de Iniciativa Consolidada"]
        direction TB
        B1["1. Identidad Unificada\n(EMPI)"]
        B2["2. Interoperabilidad\ndel Ciclo Clínico"]
        B3["3. Omnicanalidad y\nVista Longitudinal"]
        B4["4. Automatización\nAdmin. y Facturación"]
        B5["5. Observabilidad y\nResiliencia Multinube"]
        B6["6. Seguridad y\nGobierno de Datos"]
        B7["7. Analítica Clínica\ny Operativa con IA"]
    end

    S01 --> B1
    S13 --> B1
    S02 --> B2
    S05 --> B2
    S07 --> B2
    S09 --> B2
    S12 --> B2
    S04 --> B3
    S11 --> B3
    S14 --> B3
    S08 --> B4
    S10 --> B4
    S06a --> B5
    S06b --> B5
    S03 --> B6
    S06c --> B6
    S15 --> B7
    S16 --> B7
    S17 --> B7

    style B1 fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style B2 fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style B3 fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style B4 fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    style B5 fill:#fce4ec,stroke:#880e4f,stroke-width:2px
    style B6 fill:#ffebee,stroke:#c62828,stroke-width:2px
    style B7 fill:#e0f7fa,stroke:#00695c,stroke-width:2px
```

---

## 3. Vista Ejecutiva — Gantt por Iniciativa Consolidada (7 Bloques)

```mermaid
gantt
    title Plan de Migración SanaRed — Vista Ejecutiva (36 meses)
    dateFormat  YYYY-MM
    axisFormat  %b %Y

    section 1. Identidad Unificada (EMPI)
    EMPI — Fundación y Deduplicación Batch     :crit, b1, 2025-01, 2025-08
    EMPI — Tiempo Real y Golden Record 360°    :b1b, 2027-01, 2027-06

    section 2. Interoperabilidad del Ciclo Clínico
    Ciclo Clínico — Fundación e Integración    :crit, b2, 2025-02, 2026-06
    Ciclo Clínico — HCE Go-Live Completo       :crit, b2b, 2026-06, 2026-12

    section 3. Omnicanalidad y Vista Longitudinal
    Omnicanalidad — Portal y Canal Unificado   :b3, 2025-05, 2026-07
    Omnicanalidad — Salud Ocupacional          :b3b, 2027-03, 2027-08

    section 4. Automatización Admin. y Facturación
    Automatización — ERP y Autorizaciones      :b4, 2026-01, 2026-09

    section 5. Observabilidad y Resiliencia Multinube
    Observabilidad — Dashboard y Alarmas       :b5, 2025-04, 2025-12

    section 6. Seguridad y Gobierno de Datos
    Seguridad — IAM, SSO y RBAC                :crit, b6, 2025-03, 2025-12

    section 7. Analítica Clínica y Operativa con IA
    Analítica — Lakehouse, CRM e IA Clínica    :b7, 2027-01, 2027-12
```

---

## 4. Vista Detallada — Gantt por las 16+1 Sub-Iniciativas

```mermaid
gantt
    title Plan de Migración SanaRed — Vista Detallada (36 meses)
    dateFormat  YYYY-MM
    axisFormat  %b %Y

    section 1. Identidad Unificada (EMPI)
    INI-01 MPI Batch + Portal/Agenda           :crit, ini01, 2025-01, 2025-08
    INI-13 MPI Tiempo Real + Golden Record 360°:ini13, 2027-01, 2027-06

    section 2. Interoperabilidad del Ciclo Clínico
    INI-02 API Gateway / ESB                   :crit, ini02, 2025-02, 2025-09
    INI-05 HCE Modernización (Piloto)          :crit, ini05, 2025-04, 2025-12
    INI-07 Teleconsulta+Firma+Agenda → HCE     :ini07, 2026-01, 2026-06
    INI-09 PACS Cloud (GCP Healthcare API)     :ini09, 2026-03, 2026-10
    INI-12 HCE Migración Completa + Go-Live    :crit, ini12, 2026-06, 2026-12

    section 3. Omnicanalidad y Vista Longitudinal
    INI-04 Portal Resiliente (CDN+Caché)       :ini04, 2025-05, 2025-09
    INI-11 Canal Digital Unificado             :ini11, 2026-02, 2026-07
    INI-14 Salud Ocupacional → Golden Record   :ini14, 2027-03, 2027-08

    section 4. Automatización Admin. y Facturación
    INI-08 ERP Migración + Interfaz FHIR       :ini08, 2026-01, 2026-08
    INI-10 Autorizaciones Electrónicas         :ini10, 2026-04, 2026-09

    section 5. Observabilidad y Resiliencia Multinube
    INI-06a Dashboard Monitoreo Interfaces     :ini06a, 2025-04, 2025-09
    INI-06b Alarmas y SLOs Críticos            :ini06b, 2025-07, 2025-12

    section 6. Seguridad y Gobierno de Datos
    INI-03 IAM Centralizado + SSO              :crit, ini03, 2025-03, 2025-10
    INI-06c RBAC + Cifrado + Trazabilidad      :crit, ini06c, 2025-06, 2025-12

    section 7. Analítica Clínica y Operativa con IA
    INI-15 CRM Integrado a Episodios           :ini15, 2027-02, 2027-07
    INI-16 Data Lakehouse + Analítica          :ini16, 2027-01, 2027-09
    INI-17 Capa de IA Clínica (Predictiva)      :ini17, 2027-06, 2027-12
```

---

## 5. Diagrama de Dependencias entre los 7 Bloques

```mermaid
flowchart TD
    B1["1. Identidad Unificada\n(EMPI)\nFase 1 — CRÍTICA"]
    B5["5. Observabilidad y\nResiliencia Multinube\nFase 1"]
    B6["6. Seguridad y\nGobierno de Datos\nFase 1 — CRÍTICA"]
    B2["2. Interoperabilidad\ndel Ciclo Clínico\nFase 1-2 — CRÍTICA"]
    B3["3. Omnicanalidad y\nVista Longitudinal\nFase 1-3"]
    B4["4. Automatización\nAdmin. y Facturación\nFase 2"]
    B7["7. Analítica Clínica\ny Operativa con IA\nFase 3"]

    B1 --> B2
    B1 --> B3
    B6 --> B2
    B5 --> B2
    B2 --> B3
    B2 --> B4
    B2 --> B7
    B3 --> B7
    B4 --> B7
    B1 --> B7

    style B1 fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style B2 fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style B5 fill:#fce4ec,stroke:#880e4f,stroke-width:1.5px
    style B6 fill:#ffebee,stroke:#c62828,stroke-width:2px
    style B3 fill:#fff3e0,stroke:#e65100,stroke-width:1.5px
    style B4 fill:#f3e5f5,stroke:#6a1b9a,stroke-width:1.5px
    style B7 fill:#e0f7fa,stroke:#00695c,stroke-width:1.5px
```

---

## 6. Resumen Ejecutivo del Plan de Migración

El plan de migración de Clínica SanaRed Integrada organiza la transformación arquitectónica en **siete bloques de iniciativa** distribuidos en tres horizontes temporales a lo largo de 36 meses, consolidando las 16 sub-iniciativas técnicas del Gap Analysis (Fase E) bajo el esquema de oportunidades que el equipo definió a nivel de negocio.

**Bloque 1 — Identidad Unificada de Pacientes (EMPI).** Es la iniciativa fundacional del plan: sin un identificador único de paciente, ninguna otra iniciativa puede garantizar integridad de datos. Arranca en el mes 1 con la implementación del motor de matching y la deduplicación batch de los 126,000 registros duplicados, integrando HCE Oracle, Portal AWS y Agenda SaaS al nuevo maestro centralizado. Su segunda etapa, en Fase 3, evoluciona el matching a tiempo real y activa el Golden Record 360° como vista unificada del paciente.

**Bloque 2 — Interoperabilidad del Ciclo Clínico.** Es el bloque de mayor complejidad y duración del plan, extendiéndose de la Fase 1 a la Fase 2. Comienza con el despliegue del API Gateway/ESB que sustituye el integrador HL7 punto a punto —eliminando el punto único de falla que bloqueó 18,600 resultados en un incidente de 11 horas— y con la arquitectura piloto de la nueva HCE. Continúa con la integración estructurada de Teleconsulta, Firma Electrónica y Agenda, la consolidación del PACS en la nube, y culmina con la migración completa y el go-live de la HCE modernizada, hito que marca el cierre de la dependencia on-premises del núcleo clínico.

**Bloque 3 — Omnicanalidad y Vista Longitudinal.** Convierte el portal de pacientes en un canal resiliente (con CDN, caché y auto-scaling) y consolida el portal web y la app móvil en una experiencia digital unificada, eliminando la duplicidad de canales. En la fase final, conecta los datos de Salud Ocupacional al Golden Record, cerrando uno de los últimos silos de información del paciente corporativo.

**Bloque 4 — Automatización Administrativa y Facturación.** Concentrado en la Fase 2, migra el ERP de la nube privada a una nube pública con interfaz FHIR hacia la HCE modernizada, y automatiza las autorizaciones con aseguradoras mediante API. Esta iniciativa depende directamente de que la HCE modernizada (Bloque 2) ya exponga datos clínicos estructurados, condición necesaria para eliminar la codificación manual que hoy genera el 13% de expedientes observados y el ciclo de facturación de 17 días.

**Bloque 5 — Observabilidad y Resiliencia Multinube.** Se ejecuta íntegramente en la Fase 1, en paralelo a la implementación del API Gateway, instrumentando el dashboard de monitoreo de interfaces clínicas y las alarmas sobre los servicios críticos (HL7/ESB, Portal, LIS). Es la iniciativa que permite detectar de forma proactiva las fallas que hoy se descubren solo cuando el paciente o el call center reportan el problema.

**Bloque 6 — Seguridad y Gobierno de Datos.** También de Fase 1 y de carácter crítico, implementa el IAM centralizado con SSO multinube y el modelo RBAC con cifrado y trazabilidad de consulta a datos sensibles. Es condición previa de la interoperabilidad del ciclo clínico, ya que ningún sistema puede integrarse de forma segura al ecosistema sin una identidad de colaborador federada y auditable.

**Bloque 7 — Analítica Clínica y Operativa con IA (nuevo).** Bloque incorporado para capitalizar la infraestructura de datos consolidada de los bloques anteriores. En la Fase 3, una vez que el CRM está integrado a los episodios clínicos reales y el Data Lakehouse multinube consolida HCE, LIS, PACS, ERP y CRM, se habilita una capa de inteligencia artificial sobre el lakehouse para modelos predictivos de demanda ambulatoria, riesgo de readmisión y priorización de resultados críticos — transformando los datos dispersos de SanaRed en una ventaja competitiva activa, no solo en un repositorio histórico.

La secuencia de dependencias confirma que los Bloques 1, 5 y 6 son los cimientos del plan: todos los demás bloques —incluida la analítica con IA— dependen, directa o indirectamente, de tener una identidad de paciente confiable, una capa de observabilidad activa y un modelo de seguridad multinube gobernado.
