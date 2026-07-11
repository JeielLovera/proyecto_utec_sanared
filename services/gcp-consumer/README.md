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
| `main.py` | Cloud Run (Flask): `POST /events` (demo/HTTP) → `transform.process_event` → clientes GCP (import perezoso) |
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

## Estado

**Verificado:** `pytest` 5/5 (plan de re-tag DICOM, forma de la fila `patient_360`,
orquestación por tipo de evento). Pendiente: wiring real QIDO-RS/STOW-RS del DICOM
retag (requiere credenciales/dataset real) y consumo Kafka (mismo caveat de
autenticación MSK-IAM que el adaptador HL7, ver `services/hl7-adapter/README.md`).
