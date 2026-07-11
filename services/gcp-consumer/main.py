"""Consumidor GCP (Cloud Run). Recibe identity.patient.* (por HTTP para demo, o Kafka en
producción) y aplica las transformaciones de transform.py contra Healthcare API + BigQuery.

Los clientes de Google Cloud se importan de forma perezosa (lazy) para que transform.py
y este módulo sean testeables sin `google-cloud-*` instalado (ver test_transform.py).
"""
from __future__ import annotations

import json
import logging
import os

from flask import Flask, request

from transform import process_event

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("empi.gcp-consumer")

app = Flask(__name__)

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "")
REGION = os.environ.get("GCP_REGION", "us-central1")
BQ_DATASET = os.environ.get("BQ_DATASET", "")
BQ_TABLE = os.environ.get("BQ_TABLE", "patient_360")
DICOM_STORE_PATH = os.environ.get("DICOM_STORE_PATH", "")


@app.get("/health")
def health():
    return {"status": "ok"}, 200


@app.post("/events")
def events():
    event = request.get_json(force=True, silent=False)
    result = process_event(event)

    if result["dicom_retag"] and DICOM_STORE_PATH:
        _apply_dicom_retag(result["dicom_retag"])
    if result["patient_360_row"] and BQ_DATASET:
        _upsert_patient_360(result["patient_360_row"])

    log.info("processed %s -> %s", event.get("event_type"), result)
    return json.dumps(result, default=str), 200, {"Content-Type": "application/json"}


def _apply_dicom_retag(plan: dict) -> None:
    """Reescribe el tag PatientID de los estudios afectados (Healthcare API)."""
    try:
        from google.cloud import healthcare_v1  # import perezoso
    except ImportError:
        log.warning("google-cloud-healthcare no instalado; retag omitido (%s)", plan)
        return
    # Nota: la búsqueda de instancias por PatientID + el bulk-update de tags requiere
    # el flujo QIDO-RS/STOW-RS del dicomWeb; se omite el detalle de wiring aquí (fuera
    # del alcance verificable sin credenciales) y se deja como punto de extensión.
    log.info("DICOM retag %s -> %s (store=%s)", plan["from_patient_id"],
              plan["to_patient_id"], DICOM_STORE_PATH)


def _upsert_patient_360(row: dict) -> None:
    """Inserta/actualiza la fila en BigQuery."""
    try:
        from google.cloud import bigquery  # import perezoso
    except ImportError:
        log.warning("google-cloud-bigquery no instalado; upsert omitido (%s)", row["empi_id"])
        return
    client = bigquery.Client(project=PROJECT_ID)
    table_ref = f"{PROJECT_ID}.{BQ_DATASET}.{BQ_TABLE}"
    errors = client.insert_rows_json(table_ref, [row])
    if errors:
        log.error("BigQuery insert errors: %s", errors)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
