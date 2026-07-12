# Consumidor GCP — Cloud Run (Fase 3)

Consume `identity.patient.*` (por la VPN/bus AWS) y ejecuta las dos acciones GCP del
golden path (doc §6, §7):

1. **Re-etiquetar el estudio DICOM** del absorbido al survivor (Cloud Healthcare API,
   tag `PatientID` 0010,0020).
2. **Refrescar `patient_360`** en BigQuery (vista analítica desnormalizada).

## Archivos

| Archivo | Rol |
|---|---|
| `transform.py` | Funciones **puras** (`dicom_retag_plan`, `build_patient_360_row`, `process_event`). Verificables sin GCP. |
| `main.py` | Cloud Run (Flask): `POST /events` (demo/HTTP) + arranca `kafka_consumer` en un **hilo de fondo** si `KAFKA_BOOTSTRAP` está seteado |
| `kafka_consumer.py` | Consumidor Kafka standalone real (`confluent-kafka` + `aws-msk-iam-sasl-signer-python`) |
| `Dockerfile`, `requirements.txt` | Imagen para Cloud Run |
| `test_transform.py` | Pruebas de las transformaciones |

## Verificar (local, sin GCP)

```bash
python -m pytest services/gcp-consumer/test_transform.py -q
```

## Correr el servicio HTTP en local

```bash
pip install -r services/gcp-consumer/requirements.txt
python services/gcp-consumer/main.py
curl -X POST localhost:8080/events -H 'content-type: application/json' -d '{
  "event_type": "PatientMerged", "event_id": "ev1",
  "data": {"survivor_empi_id": "EMPI-A", "merged_empi_id": "EMPI-B", "retired_identifiers": []}
}'
```

Sin `GCP_PROJECT_ID`/`BQ_DATASET`/`DICOM_STORE_PATH` configurados, el servicio solo
**loguea** el plan (no llama a GCP) — mismo patrón NoOp que el bus del servicio EMPI.

## Verificar el consumidor Kafka real (Redpanda local)

```bash
export KAFKA_BOOTSTRAP=localhost:19092
export KAFKA_AUTH=plaintext          # "iam" contra MSK Serverless real
python services/gcp-consumer/kafka_consumer.py 1   # procesa 1 mensaje y termina
```

## Estado

**Verificado E2E** (2026-07-11, infraestructura local con Docker): `pytest` 5/5, y el
consumidor Kafka standalone leyó un evento `PatientMerged` real (publicado por el
servicio EMPI en Redpanda) y generó correctamente el plan de re-tag DICOM y la fila
`patient_360` (`retag=True row=True`). Pendiente: wiring real QIDO-RS/STOW-RS del DICOM
retag y el `insert_rows_json` de BigQuery contra un proyecto GCP real (requiere aplicar
`infra/terraform/stacks/30-gcp-analytics/` con la credencial cross-cloud que expone
`40-xcloud-net`, ver `infra/terraform/DEPLOYMENT.md` §6.1).
