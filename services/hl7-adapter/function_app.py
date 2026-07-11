"""Adaptador HL7 (Azure Functions, modelo v2).

Consume identity.patient.* del bus y emite ADT al HCE (por APIM/VPN). Se exponen dos
disparadores que comparten `process_event`:
  - HTTP  (POST /api/events): camino demostrable/pruebas (curl o bridge del bus).
  - Kafka (identity.patient.*): camino de producción (ver nota de autenticación abajo).

NOTA cross-cloud: MSK Serverless usa autenticación AWS IAM (SASL/OAUTHBEARER SigV4). El
binding Kafka de Functions habla SASL PLAIN/SCRAM; por eso, para MSK Serverless el consumo
real se hace con confluent-kafka + aws-msk-iam-sasl-signer y credenciales AWS en Key Vault.
El disparador Kafka de abajo queda como contrato; el HTTP permite ejercitar el golden path.
"""
from __future__ import annotations

import json
import logging
import os
import urllib.request

import azure.functions as func

from hl7 import to_hl7

app = func.FunctionApp()
log = logging.getLogger("empi.hl7")

HCE_ENDPOINT = os.environ.get("HCE_ENDPOINT", "http://localhost:8080")


def process_event(event: dict) -> dict:
    """Traduce el evento a HL7 y lo reenvía al HCE. Devuelve un resumen."""
    message = to_hl7(event)
    if message is None:
        return {"event_type": event.get("event_type"), "hl7": None, "forwarded": False}

    status = _forward_to_hce(message)
    log.info("HL7 %s -> HCE (%s)", event.get("event_type"), status)
    return {
        "event_type": event.get("event_type"),
        "message_type": "ADT^A40" if event.get("event_type") == "PatientMerged" else "ADT^A28",
        "hl7": message,
        "forwarded": True,
        "hce_status": status,
    }


def _forward_to_hce(message: str) -> int:
    req = urllib.request.Request(
        f"{HCE_ENDPOINT}/adt",
        data=message.encode("utf-8"),
        headers={"Content-Type": "application/hl7-v2"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status
    except Exception as exc:  # el HCE simulado puede no estar en local
        log.warning("HCE no alcanzable: %s", exc)
        return 0


@app.route(route="events", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def events_http(req: func.HttpRequest) -> func.HttpResponse:
    try:
        event = req.get_json()
    except ValueError:
        return func.HttpResponse("invalid json", status_code=400)
    result = process_event(event)
    return func.HttpResponse(json.dumps(result), mimetype="application/json")


# Camino de producción (ver nota de autenticación arriba).
@app.kafka_trigger(
    arg_name="messages",
    topic="identity.patient.merged",
    broker_list="%KAFKA_BOOTSTRAP%",
    consumer_group="empi-hl7-adapter",
)
def on_merged(messages: str) -> None:
    for raw in _iter(messages):
        process_event(raw)


@app.kafka_trigger(
    arg_name="messages",
    topic="identity.patient.created",
    broker_list="%KAFKA_BOOTSTRAP%",
    consumer_group="empi-hl7-adapter",
)
def on_created(messages: str) -> None:
    for raw in _iter(messages):
        process_event(raw)


def _iter(messages: str):
    payload = json.loads(messages)
    for item in (payload if isinstance(payload, list) else [payload]):
        # El binding entrega el valor del mensaje; puede venir envuelto.
        value = item.get("Value", item) if isinstance(item, dict) else item
        yield json.loads(value) if isinstance(value, str) else value
