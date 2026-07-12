"""Lógica del adaptador HL7, sin dependencia de azure.functions ni confluent-kafka.
Separada de function_app.py / kafka_consumer.py para que sea testeable en cualquier
entorno (ver test_hl7.py y el uso en ambos entrypoints)."""
from __future__ import annotations

import logging
import os
import urllib.request

from hl7 import to_hl7

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
    except Exception as exc:  # el HCE simulado puede no estar disponible
        log.warning("HCE no alcanzable: %s", exc)
        return 0
