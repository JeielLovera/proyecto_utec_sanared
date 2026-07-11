Empresa: Clínica SanaRed Integrada
(Ficticia)

Sector Económico

Salud

# Resumen ejecutivo

Clínica SanaRed Integrada es una red privada de salud con cuatro clínicas, nueve centros médicos,

1,200 médicos afiliados, 3,800 colaboradores y más de 1.6 millones de atenciones anuales. Su

negocio combina consultas ambulatorias, emergencia, hospitalización, cirugía, laboratorio, imágenes,

programas preventivos y convenios corporativos. Atiende pacientes particulares, asegurados y

empresas que contratan planes de salud ocupacional.

La red compite en un sector donde la experiencia del paciente, la rapidez de atención, la seguridad

clínica, la interoperabilidad con aseguradoras y el uso responsable de datos determinan la

preferencia. Sin embargo, su arquitectura tecnológica se formó por crecimiento acelerado y

adquisiciones: historia clínica electrónica on premises, agenda médica SaaS, portal de pacientes en

AWS, analítica de laboratorio en Azure, sistema de imágenes con almacenamiento local, facturación

en ERP privado y aplicaciones móviles desarrolladas por terceros.

La organización busca en tres años operar como una red integrada de salud digital, con continuidad

asistencial, omnicanalidad, trazabilidad clínica, interoperabilidad con financiadores y resiliencia ante

picos de demanda. Los problemas actuales son graves: pacientes duplicados, tiempos de espera

crecientes, autorizaciones manuales, resultados clínicos dispersos, caídas de sistemas durante

campañas, costos tecnológicos sin control y riesgos de privacidad.

El caso describe la cadena de valor desde la búsqueda de atención hasta la facturación y

seguimiento. Cada fase muestra cómo los roles clínicos y administrativos dependen de aplicaciones y

bases de datos inconexas, con información sensible distribuida entre on premises, AWS, Azure y

SaaS. La narrativa ofrece un contexto realista de transformación multinube en salud, con alta

exigencia regulatoria, operativa y humana.

# Contexto de la Organización

SanaRed empezó como una clínica de especialidades médicas en una zona residencial. Su

reputación creció por la calidad de sus médicos y por una atención más cercana que la de grandes

hospitales. Con el tiempo compró dos clínicas medianas, abrió centros ambulatorios en distritos

emergentes y firmó convenios con aseguradoras. El crecimiento fue comercialmente exitoso, pero

tecnológicamente desigual. Cada sede tenía su manera de registrar pacientes, coordinar citas,

gestionar historias clínicas y facturar.

El modelo de negocio combina atención médica directa, acuerdos con aseguradoras, programas

corporativos, paquetes preventivos y servicios diagnósticos. Los pacientes llegan por canales

digitales, llamadas, derivaciones médicas, emergencias o convenios empresariales. La propuesta de

valor es atención confiable, disponibilidad de especialistas, diagnóstico oportuno, cercanía geográfica

y continuidad médica. Los ingresos provienen de copagos, reembolsos de aseguradoras, planes

corporativos, procedimientos, exámenes y hospitalización.

La red atiende diariamente cerca de 5,200 citas ambulatorias, 780 emergencias, 3,400 exámenes de

laboratorio, 920 estudios de imágenes y 110 cirugías. En campañas preventivas, como chequeos

corporativos o vacunación, los volúmenes pueden duplicarse. Las entidades de datos críticas son

paciente, historia clínica, cita, médico, diagnóstico, orden médica, resultado, receta, autorización,

póliza, factura, consentimiento y episodio clínico.

El sector salud privado se ha vuelto altamente competitivo. Nuevas clínicas digitales ofrecen

teleconsulta en minutos. Aseguradoras presionan tarifas y exigen intercambio electrónico de

información. Pacientes comparan tiempos de espera, disponibilidad de resultados, facilidad de pago y

experiencia móvil. Al mismo tiempo, las regulaciones de protección de datos y seguridad de

información son más estrictas. Un incidente de privacidad o una falla clínica por información

incompleta podría afectar la reputación construida durante años.

Los problemas actuales ya se perciben en la experiencia del paciente. Una persona puede registrarse

en el portal web, llamar para confirmar su cita, llegar a una sede y descubrir que su información no

coincide con la del sistema local. Los médicos consultan la historia clínica electrónica, pero los

resultados de imágenes pueden estar en un visor separado. Las autorizaciones de aseguradora se

gestionan en portales externos y se imprimen para adjuntarlas al expediente. El área de facturación

recibe información incompleta y retrasa cierres.

En el último año, SanaRed recibió 18,400 reclamos por demora de atención, 7,900 por problemas de

agenda o autorización y 2,100 por resultados no disponibles oportunamente. Una auditoría identificó

126,000 registros potencialmente duplicados de pacientes. Durante una campaña de chequeos

corporativos, el portal de resultados tuvo una caída de cuatro horas y 12,000 pacientes no pudieron

descargar documentos.

La aspiración del directorio es integrar la red alrededor del paciente. No se trata solo de digitalizar

trámites, sino de garantizar que cada interacción clínica y administrativa sea coherente, segura y

trazable. Para ello, SanaRed necesita modernizar su arquitectura, ordenar dominios de datos,

conectar sistemas clínicos y administrativos, gobernar APIs, proteger información sensible y diseñar

una operación multinube resiliente.

# Objetivos Estratégicos

1. Reducir el tiempo promedio de espera ambulatoria de 52 minutos a 25 minutos, integrando

agenda, admisión, autorizaciones, triaje y atención médica.

2. Lograr una vista clínica longitudinal para el 90% de pacientes atendidos, consolidando historia,

diagnósticos, resultados, recetas, alergias, consentimientos y episodios.

3. Disminuir registros duplicados de pacientes en 80% mediante gobierno de identidad,

validaciones, depuración y sincronización entre sedes y canales.

4. Incrementar la disponibilidad de canales digitales críticos a 99.9%, especialmente portal de

pacientes, agenda, resultados, pagos y teleconsulta.

5. Reducir el ciclo de facturación con aseguradoras de 17 días a 7 días, integrando autorizaciones,

prestaciones, auditoría médica y documentación.

6. Fortalecer la seguridad y privacidad de datos clínicos, con control de acceso por rol, trazabilidad

de consulta, cifrado, monitoreo y respuesta ante incidentes.

7. Implementar capacidades de analítica clínica y operativa para gestionar demanda, ocupación,

tiempos, calidad asistencial y costos por episodio.

# Cadena de Valor

## Fase 1: Búsqueda de atención

La experiencia del paciente comienza antes de ingresar a una clínica. Una madre busca una cita de

pediatría desde su celular; un ejecutivo corporativo solicita un chequeo preventivo; un paciente

crónico intenta renovar receta; un asegurado busca un especialista cubierto por su póliza. SanaRed

ofrece portal web, app móvil, call center y recepción presencial. Cada canal promete cercanía, pero

detrás de esa promesa conviven sistemas que no siempre se reconocen entre sí.

La agenda médica opera en un SaaS contratado hace cuatro años. El portal de pacientes está

desplegado en AWS con base de datos Amazon RDS. El call center usa un CRM SaaS. Las sedes

antiguas aún tienen módulos locales de admisión conectados a la historia clínica on premises. El

maestro de médicos está en el ERP, pero las disponibilidades reales se administran en la agenda

SaaS. Las pólizas y coberturas se consultan en portales de aseguradoras.

Participan pacientes, operadores de call center, admisión, médicos, coordinadores de sede y

aseguradoras. Las entidades de datos son paciente, cita, médico, especialidad, sede, cobertura,

canal, autorización previa y preferencia de atención. El problema aparece cuando la misma persona

tiene identidades distintas por canal. Un DNI puede estar asociado a dos correos, tres números de

historia y registros de dependientes familiares.

En un mes promedio se programan 156,000 citas. El 11% se reprograma, el 7% no asiste y el 4%

genera reclamo por errores de horario, sede o cobertura. Cuando un médico cambia su disponibilidad,

la actualización puede tardar horas en reflejarse en todos los canales. En campaña de influenza,

18,000 citas se cargaron por lote, pero la sincronización falló en dos centros médicos. Llegaron

pacientes a horarios que no existían en la agenda local. La escena en recepción fue caótica y quedó

registrada en redes sociales.

## Fase 2: Admisión del paciente

Al llegar a la sede, el paciente atraviesa admisión. Se valida identidad, cobertura, consentimiento,

motivo de atención y pago inicial. Si es emergencia, el proceso se acelera con triaje. Si viene por

aseguradora, se revisa autorización. La operación parece administrativa, pero una admisión mal

ejecutada puede afectar atención clínica, facturación y seguridad del paciente.

El sistema de admisión principal está integrado a la historia clínica electrónica on premises, instalada

sobre una base Oracle en el centro de datos de la clínica principal. El portal de pagos corre en Azure

App Service. Las autorizaciones se validan en portales externos de aseguradoras; algunas ofrecen

APIs, otras solo formularios web. Los consentimientos digitales se guardan en un repositorio SaaS de

firma electrónica. Las sedes pequeñas tienen conectividad variable con el centro de datos.

Roles involucrados: admisionista, enfermera de triaje, auditor administrativo, aseguradora, caja,

paciente y médico de guardia. Entidades de datos: episodio, admisión, cobertura, autorización,

consentimiento, pago, triaje, prioridad, sala y responsable. La dificultad está en que cada validación

depende de un sistema distinto y muchas veces se resuelve con impresión, captura de pantalla o

llamada telefónica.

En emergencia, SanaRed recibe 780 pacientes diarios. En horas pico, 35 pacientes pueden esperar

simultáneamente autorización de aseguradora. Si el portal externo no responde, la admisión opera

bajo contingencia. En febrero, una caída de conectividad entre dos sedes y el centro de datos obligó a

registrar 1,400 admisiones en formularios temporales. Al migrarlas al sistema central aparecieron 260

inconsistencias entre paciente, cobertura y episodio. Algunas facturas se observaron semanas

después.

## Fase 3: Atención del paciente

La atención médica ocurre en consultorios, tópicos, salas de emergencia y hospitalización. El médico

abre la historia clínica, revisa antecedentes, registra diagnóstico, solicita exámenes, prescribe

medicamentos o indica procedimiento. Para el paciente, la consulta es una conversación. Para la

organización, es el punto donde se genera información clínica crítica.

La historia clínica electrónica es robusta, pero antigua. Corre on premises y fue diseñada para

atención presencial, no para red omnicanal. La teleconsulta se atiende desde una plataforma SaaS

que genera un resumen en PDF. Los médicos suben ese resumen manualmente a la historia. Las

recetas electrónicas se emiten desde un módulo separado. Los resultados de laboratorio se consultan

en Azure, mientras imágenes se visualizan en un PACS (Picture Archiving and Communication

System) local por sede.

Participan médico, enfermera, paciente, laboratorio, imágenes, farmacia y auditoría médica.

Entidades de datos: historia clínica, episodio, diagnóstico, alergia, orden médica, receta, resultado,

imagen, procedimiento y evolución. La información relevante no siempre aparece en el momento de la

atención. Un médico puede no ver un resultado tomado en otra sede hasta que se sincronice. Un

paciente puede repetir exámenes porque el resultado anterior no está disponible.

En el último año se registraron 2.4 millones de episodios clínicos. El 14% tuvo alguna orden

diagnóstica. De esos, el 9% presentó demora en disponibilidad de resultados dentro de la historia. No

siempre hubo daño clínico, pero sí frustración, reprocesos y costos. Un caso sensible ocurrió con un

paciente anticoagulado que ingresó por emergencia. El antecedente estaba en una atención de otra

sede, pero no apareció oportunamente por un problema de sincronización. El médico actuó con

criterio clínico, pero el incidente encendió alertas sobre continuidad asistencial.

## Fase 4: Exámenes de laboratorio e imágenes

Los servicios diagnósticos son el corazón invisible de la red. Laboratorio procesa muestras de sangre,

orina y cultivos. Imágenes realiza radiografías, ecografías, tomografías y resonancias. Cada solicitud

médica debe convertirse en una orden, una toma de muestra o estudio, un resultado validado y una

entrega al paciente y al médico.

El laboratorio usa un LIS (Laboratory Information System) alojado en Azure SQL Managed Instance.

Los equipos automatizados envían resultados al LIS por interfaces HL7. Imágenes usa PACS locales

en cada clínica y un visor web con réplica parcial en GCP Cloud Storage. La historia clínica on

premises recibe algunos resultados por integración, pero otras veces se adjuntan documentos PDF. El

portal de pacientes muestra resultados desde AWS, consumiendo APIs intermedias.

Roles: tecnólogo médico, médico radiólogo, patólogo clínico, enfermera, médico tratante, paciente y

soporte TI. Entidades de datos: orden, muestra, estudio, resultado, imagen, informe, equipo,

validación, criticidad y notificación. El problema grave es la falta de sincronización confiable entre

sistemas clínicos y canales digitales.

SanaRed procesa 3,400 exámenes de laboratorio diarios y 920 estudios de imágenes. En promedio,

6% de resultados ambulatorios no aparece en el portal dentro del plazo prometido. Las llamadas al

call center por resultados representan 22% del volumen mensual. En una caída del integrador HL7,

18,600 resultados quedaron pendientes de envío a la historia durante 11 horas. Los resultados

existían en el LIS, pero no en el lugar donde médicos y pacientes los esperaban. El área clínica operó

con llamadas y capturas manuales.

## Fase 5: Facturación

Cuando la atención termina, comienza la facturación. Para un paciente particular, el proceso puede

ser simple: pago y comprobante. Para asegurados y empresas, se abre un circuito complejo de

prestaciones, autorizaciones, auditoría médica, topes, exclusiones, copagos, liquidaciones y

observaciones.

El ERP de facturación está alojado en una nube privada administrada por un proveedor local. Las

prestaciones se originan en la historia clínica on premises, pero no todas llegan con codificación

correcta. Las aseguradoras reciben documentos por portales, APIs o correo. Auditoría médica revisa

diagnósticos, órdenes, informes y consentimientos. Finanzas consolida cuentas por cobrar y

provisiones.

Participan caja, facturación, auditoría médica, médico tratante, aseguradora, finanzas y paciente.

Entidades de datos: prestación, tarifa, cobertura, autorización, factura, observación, sustento clínico,

liquidación, copago y nota de crédito. La fragmentación genera demoras y rechazos. Un examen

puede estar clínicamente realizado, pero administrativamente incompleto.

El ciclo promedio de cobro a aseguradoras es de 17 días y en algunos convenios supera 35. El 13%

de expedientes se observa por documentación incompleta o inconsistencia entre diagnóstico,

procedimiento y autorización. Cada expediente observado consume tiempo de auditoría, retrasa flujo

de caja y deteriora la relación con financiadores. En un convenio corporativo grande, se acumularon

USD 1.8 millones pendientes por discrepancias de codificación durante seis meses.

## Fase 6: Seguimiento del paciente

La relación con el paciente no termina con la factura. SanaRed envía resultados, recordatorios,

encuestas, indicaciones posconsulta, controles y programas preventivos. Los pacientes crónicos

requieren seguimiento continuo; los quirúrgicos necesitan monitoreo posoperatorio; los corporativos

esperan reportes agregados. Esta fase define lealtad y reputación.

El CRM SaaS administra campañas. El portal de pacientes en AWS muestra citas, resultados y

pagos. La app móvil envía notificaciones. Los programas de salud ocupacional se gestionan en una

aplicación propia alojada en GCP. Las encuestas están en otro SaaS. Los datos de satisfacción no se

conectan con episodios clínicos ni con operaciones de sede.

Roles: paciente, gestor de experiencia, médico, enfermera de seguimiento, empresa cliente,

marketing, calidad y analítica. Entidades de datos: encuesta, recordatorio, plan de control, resultado,

indicación, empresa, cohorte, reclamo y recomendación. La falta de integración hace que la

experiencia sea inconsistente. Un paciente puede recibir una encuesta antes de tener sus resultados,

o un recordatorio para un control que ya fue reprogramado.

En doce meses se enviaron 4.2 millones de mensajes entre SMS, correos y notificaciones. El 18%

tuvo rebote o baja interacción. Los reclamos por comunicaciones contradictorias crecieron 34%.

SanaRed tiene datos suficientes para anticipar demanda, personalizar seguimiento y mejorar calidad,

pero sus sistemas no permiten una visión coherente. Mientras tanto, competidores digitales ofrecen

experiencias más simples y rápidas, aunque con menor infraestructura clínica.

