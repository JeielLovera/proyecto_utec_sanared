"""Publicación de eventos al bus (topics identity.patient.*, §6).

Perfil actual: NoOp (log). El envelope es un SUBCONJUNTO del evento (minimización §10)
y respeta el contrato de 07_Scripts_Modelo_Datos/schemas/bus/. La implementación Kafka
(MSK SASL/IAM) se habilita en Fase 2/3 sin cambiar este contrato.
"""
from __future__ import annotations

import logging

from .config import settings

log = logging.getLogger("empi.bus")

# event_type -> topic. Los eventos internos no se publican.
TOPICS = {
    "PatientRegistered": "identity.patient.created",
    "IdentifierLinked": "identity.patient.updated",
    "ContactUpdated": "identity.patient.updated",
    "PatientMerged": "identity.patient.merged",
    "MergeReverted": "identity.patient.merged",
    "PatientDeactivated": "identity.patient.deactivated",
}


def build_envelope(event_type: str, empi_id: str, event_id: str, correlation_id: str,
                   occurred_at: str, payload: dict) -> dict:
    """Envelope mínimo por tipo de evento (§6)."""
    if event_type in ("PatientMerged", "MergeReverted"):
        data = {
            "survivor_empi_id": payload.get("survivor_empi_id"),
            "merged_empi_id": payload.get("merged_empi_id"),
            "retired_identifiers": payload.get("retired_identifiers", []),
        }
    else:
        data = {"identifiers": payload.get("identifiers", [])}
    return {
        "event_id": str(event_id),
        "event_type": event_type,
        "empi_id": empi_id,
        "correlation_id": str(correlation_id),
        "occurred_at": occurred_at,
        "data": data,
    }


class NoOpBus:
    """Registra el envelope en el log. Suficiente para Flujo A en AWS (sin Azure/GCP)."""

    def publish(self, event_type: str, empi_id: str, event_id: str, correlation_id: str,
                occurred_at: str, payload: dict) -> None:
        topic = TOPICS.get(event_type)
        if not topic:
            return  # evento interno (PatientMatchPending / PatientAccessed)
        env = build_envelope(event_type, empi_id, event_id, correlation_id, occurred_at, payload)
        log.info("BUS %s -> %s", topic, env)


def get_bus():
    # Punto de extensión: if settings.bus_backend == "kafka": return KafkaBus(...)
    return NoOpBus()


bus = get_bus()
