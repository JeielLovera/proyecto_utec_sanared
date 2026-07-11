"""Construcción de mensajes HL7 v2 a partir de los eventos del bus (§6, §8).

El puente clave es merge -> ADT^A40 + segmento MRG: el par (retired_identifier, survivor)
del evento PatientMerged es literalmente lo que el HCE necesita para unificar historias.
Módulo puro (sin dependencias de Azure/Kafka) -> verificable con pytest.
"""
from __future__ import annotations

from datetime import datetime, timezone

# URI FHIR del sistema fuente -> autoridad asignadora en PID-3/MRG-1 (HL7 v2).
URI_TO_AUTHORITY = {
    "urn:pe:reniec:dni": "RENIEC",
    "urn:sanared:hce": "SANARED-HCE",
    "urn:sanared:lis": "SANARED-LIS",
    "urn:sanared:portal": "SANARED-PORTAL",
    "urn:sanared:pacs": "SANARED-PACS",
    "urn:sanared:erp": "SANARED-ERP",
    "urn:sanared:empi": "SANARED-EMPI",
}

FIELD = "|"
COMP = "^"
CR = "\r"


def _ts(dt: datetime | None = None) -> str:
    return (dt or datetime.now(timezone.utc)).strftime("%Y%m%d%H%M%S")


def _msh(message_type: str, control_id: str, ts: str) -> str:
    # MSH-1=|  MSH-2=^~\&   emisor EMPI -> receptor HCE
    return FIELD.join([
        "MSH", "^~\\&", "SANARED-EMPI", "SANARED", "HCE", "SANARED",
        ts, "", message_type, control_id, "P", "2.5",
    ])


def _pid(empi_id: str, identifiers: list[dict]) -> str:
    # PID-3: lista de identificadores (EMPI + cada sistema fuente), CX repetidos.
    cx = [f"{empi_id}{COMP}{COMP}{COMP}SANARED-EMPI"]
    for ident in identifiers:
        authority = URI_TO_AUTHORITY.get(ident.get("system", ""), "UNKNOWN")
        cx.append(f"{ident['value']}{COMP}{COMP}{COMP}{authority}")
    pid3 = "~".join(cx)
    return FIELD.join(["PID", "1", "", pid3, "", "", "", "", "", "", "", "", "", ""])


def _evn(ts: str) -> str:
    return FIELD.join(["EVN", "", ts])


def build_adt_a28(event: dict) -> str:
    """PatientRegistered -> ADT^A28 (alta de persona en el índice)."""
    ts = _ts()
    data = event.get("data", event)
    empi_id = event["empi_id"]
    identifiers = data.get("identifiers", [])
    segments = [
        _msh("ADT^A28", event["event_id"], ts),
        _evn(ts),
        _pid(empi_id, identifiers),
    ]
    return CR.join(segments) + CR


def build_adt_a40(event: dict) -> str:
    """PatientMerged -> ADT^A40 con segmento MRG (fusión de identidades).

    PID-3 lleva el survivor; MRG-1 lleva el/los identificador(es) retirado(s) que el
    HCE debe fusionar en el survivor (doc §8)."""
    ts = _ts()
    data = event.get("data", event)
    survivor = data["survivor_empi_id"]
    retired = data.get("retired_identifiers", [])

    # MRG-1: identificadores del registro absorbido (los que el HCE citaba).
    merged_empi = data.get("merged_empi_id", "")
    mrg_cx = [f"{merged_empi}{COMP}{COMP}{COMP}SANARED-EMPI"]
    for ident in retired:
        authority = URI_TO_AUTHORITY.get(ident.get("system", ""), "UNKNOWN")
        mrg_cx.append(f"{ident['value']}{COMP}{COMP}{COMP}{authority}")
    mrg = FIELD.join(["MRG", "~".join(mrg_cx)])

    segments = [
        _msh("ADT^A40", event["event_id"], ts),
        _evn(ts),
        _pid(survivor, []),  # el survivor ya va como CX principal del PID-3
        mrg,
    ]
    return CR.join(segments) + CR


# event_type -> (builder, ¿aplica?)
BUILDERS = {
    "PatientRegistered": build_adt_a28,
    "PatientMerged": build_adt_a40,
}


def to_hl7(event: dict) -> str | None:
    """Traduce un evento del bus a HL7 v2, o None si no genera ADT."""
    builder = BUILDERS.get(event.get("event_type"))
    return builder(event) if builder else None
