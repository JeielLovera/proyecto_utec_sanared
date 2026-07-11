ANEXO: RIESGOS TECNOLÓGICOS

Caso asociado: Clínica SanaRed Integrada

Propósito del anexo: Este anexo identifica los 3 riesgos tecnológicos más relevantes
para el caso.

# Riesgos tecnológicos priorizados

|Prioridad | categoría | Riesgo tecnológico | Aplicaciones e infraestructura involucradas|
| :--- | :---: | :--- | :--- |
|1 | Seguridad | exposición de datos clínicos sensibles por identidades duplicadas, accesos heterogéneos, integraciones con terceros y datosd istribuidos en múltiples nubes. | Historia clínica Oracle on premises, portal AWS, agenda SaaS, CRM SaaS, Azure App Service, LIS en Azure SQL, PACS locales, repositorio de firma electrónica.|
|2 | Integridad | Falta de identidad única del paciente y sincronización clínica confiable, con riesgo de atención basada en información incompleta o inconsistente. | Historia clínica, agenda SaaS, portal de pacientes AWS, admisión local, LIS Azure, PACS, tele consulta SaaS, ERP privado.|
|3 | Disponibilidad | caídas o degradación de canales digitales e integradores clínicos que afectan agenda, resultados, admisión, portal y continuidad asistencial. | Portal AWS, APIs intermedias, integrador HL7, conectividad de sedes, LIS Azure, PACS locales, historia clínica on premises.|


# 1.  Riesgo de Seguridad: privacidad clínica en ecosistema distribuido

### Descripción del riesgo

SanaRed  maneja
información  altamente  sensible:  historia  clínica,
diagnósticos, resultados, imágenes, recetas, consentimientos, pólizas, pagos y
datos familiares. La distribución entre aplicaciones y sedes aumenta el riesgo
de  fuga,  accesos  indebidos  y  auditoria  incompleta  sobre  quien  consulto
información clínica.

### Problemática técnica crítica

Un paciente puede tener un registro en el portal AWS, otro en la agenda SaaS y
otro  en  la  historia  clínica  Oracle  on  premises.  Los  operadores  de  call  center
acceden al CRM SaaS, admisión accede a la historia clínica, laboratorio al LIS

en  Azure  y  radiología  al  PACS  local.  Cada  plataforma  tiene  roles  propios.
Algunas consultas administrativas muestran datos clínicos mínimos, pero los
adjuntos PDF de tele consulta y resultados quedan en repositorios donde los
permisos se heredan por sede o área.

Cuando  auditoria  requiere  saber  quién  vio  un  resultado  sensible,  se  deben
consultar logs separados: portal AWS, historia clínica, LIS, PACS y SaaS de firma
electrónica.  No  existe  correlación  única  por  identidad  del  colaborador  ni  por
identidad  consolidada  del  paciente.  Un  médico  afiliado  que  rota  entre  sedes
podría conservar permisos más amplios de los necesarios. Un acceso indebido
sería difícil de detectar de forma temprana.

### Evidencias AS IS a relevar

•  Mapa de datos sensibles por aplicación, repositorio, nube y tercero.

•  Roles, perfiles y permisos en historia clínica, portal, CRM, agenda, LIS,

PACS y ERP.

•  Uso  de  MFA,  SSO,  cuentas  compartidas,  altas/bajas  de  médicos

afiliados y segregación por sede.

•  Logs  de  acceso  a  datos  clínicos  y  capacidad  de  correlación  para

auditoria.

•  Flujos de adjuntos PDF, consentimientos,  imágenes y resultados entre

sistemas.

# 2.  Riesgo de Integridad: paciente duplicado y continuidad asistencial incompleta

### Descripción del riesgo

La red necesita una vista longitudinal del paciente, pero hoy hay duplicados y
datos  clínicos  dispersos.  Una  inconsistencia  de  identidad  puede  afectar
agenda, admisión, resultados, facturación y decisiones médicas. El riesgo no es
solo administrativo: puede impactar seguridad del paciente.

### Problemática técnica crítica

El  portal  de  pacientes  en  AWS  permite  registro  con  correo  y  documento.  La
agenda SaaS permite programar por teléfono usando nombre, celular y fecha de
nacimiento. La historia clínica on premises usa número de historia generado por
sede  histórica.  Cuando  el  paciente  cambia  de  aseguradora  o  registra  a  un

dependiente familiar, se crean relaciones que no siempre se sincronizan. La de
duplicación se ejecuta de forma manual por reportes mensuales.

En emergencia, un paciente anticoagulado puede aparecer con dos historias:
una contiene antecedente y  medicación, otra  contiene la  admisión actual. El
medico consulta la historia abierta desde admisión y no ve oportunamente el
resultado  cargado  en  otra  sede.  El  LIS  en  Azure  ya  tiene  resultados,  pero  el
integrador no los asocio al episodio correcto por diferencia de identificador.

### Evidencias AS IS a relevar

•  Reglas  actuales  de  creación  de  paciente  en  portal,  agenda,  admisión,

historia clínica, call center y aseguradoras.

•  Campos  usados  para  matching:  DNI,  correo,  celular,  fecha  de

nacimiento, dependiente, póliza y sede.

•  Tasa de duplicados, falsos positivos y falsos negativos en depuración.

•  Flujos  de  sincronización  de  resultados,  ordenes,  recetas,  alergias  y

antecedentes.

•  Casos  de  atención  donde  el  dato  clínico  no  estuvo  disponible

oportunamente.

# 3.  Riesgo de Disponibilidad: canales e integradores clínicos vulnerables a picos y fallas

### Descripción del riesgo

Los  canales  digitales  y  los  integradores  clínicos  son  críticos  para  agenda,
resultados, pagos, tele consulta y continuidad asistencial. Las caídas durante
campanas afectan a miles de pacientes y saturan call center, sedes y personal
clínico.

### Problemática técnica crítica

El  portal  de  pacientes  en  AWS  consume  APIs  intermedias  para  resultados  y
citas. El LIS en Azure envía resultados hacia la historia clínica mediante HL7. El
PACS local replica parcialmente imágenes a GCP Cloud Storage. Si el integrador
HL7 se detiene, los resultados existen en laboratorio, pero no se publican en
historia ni portal. Call center recibe llamadas, pero solo puede ver el estado del
portal, no la cola técnica del integrador.

Durante  una  campana  corporativa,  el  portal  recibe  picos  de  descarga  de
resultados. La base RDS escala lectura, pero el servicio que consulta estados
de  resultado  depende  de  una  API  sin  cache  y  de  un  enlace  hacia  sistemas
intermitentes.  Pacientes
internos.  La  aplicación  responde  con  errores
descargan  varias  veces,  call  center  escala  tickets  y  laboratorio  termina
enviando PDF por correo para casos urgentes.

### Evidencias AS IS a relevar

•  Arquitectura de portal, APIs, integrador HL7, LIS, PACS, historia clínica y

tele consulta.

•  SLA, RTO/RPO, capacidad de escalamiento y pruebas de carga por canal

crítico.

•  Colas  pendientes,  reintentos,  idempotencia  y  monitoreo  de  interfaces

clínicas.

•  Procedimientos  de  contingencia  para  resultados,  admisión  y  tele

consulta.

• Indicadores de llamadas por indisponibilidad o demora de resultados.

