"""Identificadores del EMPI: EMPI-ID, hash de DNI y URIs FHIR de sistemas fuente."""
from __future__ import annotations

import hashlib
import secrets
from datetime import date, datetime, timezone


def new_empi_id(when: date | None = None) -> str:
    """Formato canónico EMPI-YYYYMMDD-XXXXXXXX (8 hex mayúsculas), doc §13."""
    d = when or datetime.now(timezone.utc).date()
    return f"EMPI-{d:%Y%m%d}-{secrets.token_hex(4).upper()}"


def dni_hash(dni: str) -> str:
    """SHA-256 del DNI para la clave de caché Redis (nunca en claro, §10)."""
    return hashlib.sha256(dni.encode("utf-8")).hexdigest()


# type -> sistema fuente que lo emite (catálogo source_system.identifier_emitted, §5.1)
TYPE_TO_SOURCE = {
    "DNI": "RENIEC",
    "HIST": "HCE",
    "MRN": "LIS",
    "PID": "PORTAL",
    "ACCESSION": "PACS",
    "ACC": "ERP",
    "SCHED-ID": "AGENDA",
}

# type -> URI canónico FHIR (catálogo identifier_type.fhir_system, §8)
TYPE_TO_URI = {
    "DNI": "urn:pe:reniec:dni",
    "HIST": "urn:sanared:hce",
    "MRN": "urn:sanared:lis",
    "PID": "urn:sanared:portal",
    "ACCESSION": "urn:sanared:pacs",
    "ACC": "urn:sanared:erp",
    "SCHED-ID": "urn:sanared:agenda",
}
