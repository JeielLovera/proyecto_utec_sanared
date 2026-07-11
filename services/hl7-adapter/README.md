# Adaptador HL7 — Azure Functions (Fase 2)

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
| `hl7.py` | Builders puros (`build_adt_a28`, `build_adt_a40`, `to_hl7`). **Verificable sin Azure.** |
| `function_app.py` | Functions v2: disparador **HTTP** (demo/pruebas) + **Kafka** (producción) → `process_event` |
| `host.json`, `requirements.txt` | Runtime de Azure Functions |
| `test_hl7.py` | Pruebas del puente evento→HL7 |

## Verificar el builder (local)

```bash
python -m pytest services/hl7-adapter/test_hl7.py -q
```

## Nota de autenticación cross-cloud (MSK Serverless)

MSK Serverless usa **AWS IAM (SASL/OAUTHBEARER SigV4)**. El binding Kafka de Functions habla
SASL PLAIN/SCRAM, así que para MSK el consumo real se hace con `confluent-kafka` +
`aws-msk-iam-sasl-signer` y credenciales AWS en **Key Vault**. El disparador Kafka del código
queda como contrato; el disparador **HTTP** permite ejercitar el golden path de inmediato
(curl del evento, o un bridge del bus MSK→HTTP).

Estado: builders **verificados** (pytest 3/3). Consumo Kafka real: pendiente de la Fase de
despliegue (credenciales + Key Vault).
