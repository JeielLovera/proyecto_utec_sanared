"""Consumidor Kafka standalone del consumidor GCP (MSK Serverless real, SASL/IAM).

Corre como hilo de fondo dentro del propio Cloud Run (min_instances>=1 para mantenerlo
vivo, ver infra/terraform/stacks/30-gcp-analytics/cloudrun.tf) o como proceso standalone
para pruebas locales. Reutiliza `transform.process_event`, ya verificado.

Modos de auth (KAFKA_AUTH): "iam" (MSK real) | "plaintext" (Kafka/Redpanda local).
"""
from __future__ import annotations

import json
import logging
import os
import sys

from confluent_kafka import Consumer

from transform import process_event

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("empi.gcp-consumer.kafka")

TOPICS = ["identity.patient.created", "identity.patient.merged"]


def _client_config() -> dict:
    conf = {
        "bootstrap.servers": os.environ["KAFKA_BOOTSTRAP"],
        "group.id": os.environ.get("KAFKA_GROUP_ID", "empi-gcp-consumer"),
        "auto.offset.reset": "earliest",
        "enable.auto.commit": True,
    }
    if os.environ.get("KAFKA_AUTH", "iam") == "iam":
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

        region = os.environ.get("KAFKA_REGION", "us-east-1")

        def oauth_cb(_config: str):
            token, expiry_ms = MSKAuthTokenProvider.generate_auth_token(region)
            return token, expiry_ms / 1000

        conf.update({
            "security.protocol": "SASL_SSL",
            "sasl.mechanisms": "OAUTHBEARER",
            "oauth_cb": oauth_cb,
        })
    return conf


def run(max_messages: int | None = None, apply_side_effects=None) -> int:
    """Bucle de consumo. `apply_side_effects(result)` es inyectable para pruebas
    (evita llamar a GCP real); por defecto solo loguea (igual que main.py sin GCP configurado)."""
    consumer = Consumer(_client_config())
    consumer.subscribe(TOPICS)
    processed = 0
    try:
        while max_messages is None or processed < max_messages:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                log.error("kafka error: %s", msg.error())
                continue
            event = json.loads(msg.value())
            result = process_event(event)
            if apply_side_effects:
                apply_side_effects(result)
            log.info("consumido %s -> retag=%s row=%s", event.get("event_type"),
                     bool(result["dicom_retag"]), bool(result["patient_360_row"]))
            processed += 1
    finally:
        consumer.close()
    return processed


if __name__ == "__main__":
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else None
    n = run(limit)
    log.info("total procesado: %s", n)
