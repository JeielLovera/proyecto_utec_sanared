"""Publicación de eventos al bus (topics identity.patient.*, §6).

Dos backends:
  - NoOpBus:   registra el envelope en el log (perfil sin MSK / pruebas).
  - KafkaBus:  publica de verdad. Dos modos de autenticación:
      * "iam"       -> SASL/OAUTHBEARER firmado con credenciales AWS (MSK Serverless real,
                       vía aws-msk-iam-sasl-signer). Cross-cloud: Azure/GCP firman igual,
                       solo necesitan una credencial AWS con permiso kafka-cluster:*.
      * "plaintext" -> sin auth, para probar el wiring contra un Kafka/Redpanda local.

El envelope es un SUBCONJUNTO del evento (minimización §10) y sigue el contrato de
07_Scripts_Modelo_Datos/schemas/bus/.
"""
from __future__ import annotations

import json
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

ALL_TOPICS = sorted(set(TOPICS.values()))


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
    """Registra el envelope en el log. Suficiente para correr sin bus real."""

    def publish(self, event_type: str, empi_id: str, event_id: str, correlation_id: str,
                occurred_at: str, payload: dict) -> None:
        topic = TOPICS.get(event_type)
        if not topic:
            return  # evento interno (PatientMatchPending / PatientAccessed)
        env = build_envelope(event_type, empi_id, event_id, correlation_id, occurred_at, payload)
        log.info("BUS %s -> %s", topic, env)


class KafkaBus:
    """Productor real (confluent-kafka). Crea los topics si no existen (MSK Serverless
    no los autocrea) y publica el envelope con empi_id como key (particionado estable)."""

    def __init__(self):
        from confluent_kafka import Producer
        from confluent_kafka.admin import AdminClient, NewTopic

        conf = self._client_config()
        self._producer = Producer(conf)
        self._ensure_topics(AdminClient(conf), NewTopic)

    def _client_config(self) -> dict:
        conf = {"bootstrap.servers": settings.kafka_bootstrap}
        if settings.kafka_auth == "iam":
            conf.update({
                "security.protocol": "SASL_SSL",
                "sasl.mechanisms": "OAUTHBEARER",
                "sasl.oauthbearer.config": f"region={settings.kafka_region}",
                "oauth_cb": self._iam_oauth_cb,
            })
        # "plaintext": sin security.protocol -> PLAINTEXT por defecto (Redpanda local).
        return conf

    @staticmethod
    def _iam_oauth_cb(oauth_config: str):
        """Callback OAUTHBEARER: firma un token MSK-IAM con las credenciales AWS del
        entorno (rol de tarea ECS, o un usuario IAM dedicado si es un consumidor
        cross-cloud fuera de AWS). Ver aws-msk-iam-sasl-signer-python."""
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

        region = dict(kv.split("=") for kv in oauth_config.split(",")).get(
            "region", settings.kafka_region
        )
        token, expiry_ms = MSKAuthTokenProvider.generate_auth_token(region)
        return token, expiry_ms / 1000

    def _ensure_topics(self, admin, new_topic_cls) -> None:
        existing = set(admin.list_topics(timeout=10).topics.keys())
        missing = [t for t in ALL_TOPICS if t not in existing]
        if not missing:
            return
        futures = admin.create_topics(
            [new_topic_cls(t, num_partitions=3, replication_factor=settings.kafka_replication_factor)
             for t in missing]
        )
        for topic, fut in futures.items():
            try:
                fut.result()
                log.info("topic creado: %s", topic)
            except Exception as exc:  # ya existe / carrera con otro productor
                log.info("topic %s no creado (%s) — probablemente ya existe", topic, exc)

    def publish(self, event_type: str, empi_id: str, event_id: str, correlation_id: str,
                occurred_at: str, payload: dict) -> None:
        topic = TOPICS.get(event_type)
        if not topic:
            return
        env = build_envelope(event_type, empi_id, event_id, correlation_id, occurred_at, payload)
        self._producer.produce(topic, key=empi_id, value=json.dumps(env))
        self._producer.flush(timeout=10)
        log.info("BUS(kafka) %s -> %s", topic, env)


def get_bus():
    if settings.bus_backend == "kafka":
        return KafkaBus()
    return NoOpBus()


bus = get_bus()
