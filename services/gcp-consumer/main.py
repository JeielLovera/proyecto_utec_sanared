"""Consumidor GCP (Cloud Run). Recibe identity.patient.* (por HTTP para demo, o Kafka en
producción) y aplica las transformaciones de transform.py contra Healthcare API + BigQuery.

Los clientes de Google Cloud se importan de forma perezosa (lazy) para que transform.py
y este módulo sean testeables sin `google-cloud-*` instalado (ver test_transform.py).
"""
from __future__ import annotations

import json
import logging
import os
import threading

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
    apply_side_effects(result)
    log.info("processed %s -> %s", event.get("event_type"), result)
    return json.dumps(result, default=str), 200, {"Content-Type": "application/json"}


def apply_side_effects(result: dict) -> None:
    """Aplica el resultado de process_event contra Healthcare API / BigQuery.
    Reutilizada por el endpoint HTTP (demo) y por el consumidor Kafka en segundo plano."""
    if result["dicom_retag"] and DICOM_STORE_PATH:
        _apply_dicom_retag(result["dicom_retag"])
    if result["patient_360_row"] and BQ_DATASET:
        _upsert_patient_360(result["patient_360_row"])


def _apply_dicom_retag(plan: dict) -> None:
    """Reescribe el tag PatientID de los estudios afectados (Healthcare API).

    No existe un cliente GAPIC dedicado para Cloud Healthcare API en Python: se accede
    vía el cliente genérico basado en discovery (googleapiclient), como documenta GCP."""
    try:
        from googleapiclient.discovery import build  # import perezoso
    except ImportError:
        log.warning("google-api-python-client no instalado; retag omitido (%s)", plan)
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


def _start_kafka_consumer_background() -> None:
    """Si hay bus configurado, consume en un hilo de fondo (Cloud Run min_instances>=1
    lo mantiene vivo). Sin KAFKA_BOOTSTRAP, el servicio queda solo con /events HTTP."""
    if not os.environ.get("KAFKA_BOOTSTRAP"):
        log.info("KAFKA_BOOTSTRAP no configurado; consumidor Kafka de fondo deshabilitado")
        return
    import kafka_consumer

    def _loop():
        while True:
            try:
                kafka_consumer.run(apply_side_effects=apply_side_effects)
            except Exception:
                log.exception("consumidor Kafka de fondo se cayó; reintenta en 5s")
                import time
                time.sleep(5)

    threading.Thread(target=_loop, daemon=True, name="kafka-consumer").start()
    log.info("consumidor Kafka de fondo iniciado")


_start_kafka_consumer_background()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
