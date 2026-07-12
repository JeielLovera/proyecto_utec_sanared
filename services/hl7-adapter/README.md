# Adaptador HL7 — consumidor del bus (Fase 2)

Traduce los eventos del EMPI (`identity.patient.*`) a **HL7 v2 (ADT)** y los entrega al
HCE por APIM/VPN. Es el consumidor Azure del golden path (doc §6, §8).

| Evento del bus | Mensaje HL7 | Segmento clave |
|---|---|---|
| `PatientRegistered` | **ADT^A28** (alta en el índice) | `PID-3` con todos los identificadores |
| `PatientMerged` | **ADT^A40** (fusión) | **`MRG`** = par (retirado ↔ survivor) que el HCE unifica |

El **puente merge→ADT^A40+MRG** es el corazón de la integración: el `MRG-1` lleva
exactamente el `retired_identifier` del evento, que es lo que el HCE necesita para fusionar
las dos historias (doc §8).

## Archivos

| Archivo | Rol |
|---|---|
| `hl7.py` | Builders puros (`build_adt_a28`, `build_adt_a40`, `to_hl7`). Verificable sin Azure. |
| `consumer_logic.py` | `process_event`: traduce y reenvía al HCE. Sin dependencia de `azure.functions` ni `confluent-kafka`. |
| `function_app.py` | Azure Functions v2: disparador **HTTP** (demo/pruebas manuales). |
| `kafka_consumer.py` | **Consumidor Kafka standalone real** (producción). Corre como proceso persistente. |
| `Dockerfile` | Imagen del consumidor standalone (Azure Container Instance). |
| `test_hl7.py` | Pruebas del puente evento→HL7. |

## Por qué no es una Azure Function con Kafka trigger

MSK Serverless exige **SASL/OAUTHBEARER firmado con IAM**; el binding Kafka nativo de
Azure Functions solo habla SASL PLAIN/SCRAM. Por eso el consumo real **no** usa el
trigger de Functions: se despliega como **Azure Container Instance** (`restart_policy
Always`) corriendo `kafka_consumer.py`, que sí implementa IAM vía `confluent-kafka` +
`aws-msk-iam-sasl-signer-python`. `function_app.py` queda solo para pruebas HTTP manuales.

## Verificar (sin nube)

```bash
python -m pytest services/hl7-adapter/test_hl7.py -q   # builders HL7 (3/3)
```

## Verificar el consumidor standalone contra Kafka real (Redpanda local)

```bash
export KAFKA_BOOTSTRAP=localhost:19092
export KAFKA_AUTH=plaintext          # "iam" contra MSK Serverless real
export HCE_ENDPOINT=http://localhost:19999   # mock HCE (p. ej. mendhak/http-https-echo)
python services/hl7-adapter/kafka_consumer.py 1   # procesa 1 mensaje y termina
```

## Estado

**Verificado E2E** (2026-07-11, infraestructura local con Docker): el servicio EMPI
publicó eventos reales en un bus Kafka (Redpanda), este consumidor los leyó de verdad
y entregó el `ADT^A40`/`ADT^A28` generado a un HCE mock, confirmando **`200 OK`** en la
respuesta HTTP. Falta: aplicar `infra/terraform/stacks/20-azure-integ/hl7_consumer.tf`
(Container Registry + Container Instance) contra Azure real con la credencial cross-cloud
que expone `40-xcloud-net` (ver `infra/terraform/DEPLOYMENT.demo.md` / `DEPLOYMENT.prod.md` §7).
