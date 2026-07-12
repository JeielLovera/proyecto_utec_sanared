"""Consumidor Kafka standalone del adaptador HL7 (MSK Serverless real, SASL/IAM).

Corre como proceso persistente (Azure Container Instance) en vez de Azure Functions,
porque el binding Kafka de Functions no soporta la autenticación IAM de MSK Serverless
(ver nota en function_app.py). Reutiliza `consumer_logic.process_event`, ya verificado.

Modos de auth (KAFKA_AUTH):
  - "iam"       -> SASL/OAUTHBEARER firmado con credenciales AWS (producción real).
  - "plaintext" -> sin auth, para probar contra un Kafka/Redpanda local.
"""
from __future__ import annotations

import json
import logging
import os
import sys

from confluent_kafka import Consumer

from consumer_logic import process_event
from tracing import extract_kafka_context, tracer

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("empi.hl7.consumer")

TOPICS = ["identity.patient.created", "identity.patient.merged", "identity.patient.updated"]


def _client_config() -> dict:
    conf = {
        "bootstrap.servers": os.environ["KAFKA_BOOTSTRAP"],
        "group.id": os.environ.get("KAFKA_GROUP_ID", "empi-hl7-adapter"),
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


def run(max_messages: int | None = None) -> int:
    """Bucle de consumo. `max_messages` acota la ejecución (usado en verificación local)."""
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
            ctx = extract_kafka_context(msg.headers())
            with tracer.start_as_current_span("process_event", context=ctx):
                result = process_event(event)
            log.info("consumido %s -> %s", event.get("event_type"), result.get("message_type"))
            processed += 1
    finally:
        consumer.close()
    return processed


if __name__ == "__main__":
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else None
    n = run(limit)
    log.info("total procesado: %s", n)
