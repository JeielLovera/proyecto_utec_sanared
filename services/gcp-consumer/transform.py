"""Transformaciones puras del consumidor GCP (sin dependencias de Google Cloud).

Dos responsabilidades del consumidor tras un evento del bus (§6, §7):
  1. Re-etiquetar el estudio DICOM del absorbido -> survivor (Cloud Healthcare API).
  2. Refrescar la fila patient_360 en BigQuery (vista analítica 360°).

Ambas se modelan aquí como funciones puras (evento -> plan de acción) para que sean
verificables con pytest sin credenciales ni clientes de GCP.
"""
from __future__ import annotations

from datetime import datetime, timezone


def dicom_retag_plan(event: dict) -> dict | None:
    """PatientMerged -> plan de re-etiquetado DICOM (§6, doc 03 §... GCP re-tag).

    El Healthcare API identifica estudios por el tag DICOM PatientID (0010,0020), que
    en nuestro dominio es el EMPI-ID. El plan dice: busca estudios con PatientID=merged
    y reescribe el tag a PatientID=survivor."""
    if event.get("event_type") != "PatientMerged":
        return None
    data = event.get("data", event)
    survivor = data["survivor_empi_id"]
    merged = data["merged_empi_id"]
    return {
        "action": "retag_patient_id",
        "dicom_tag": "00100020",  # PatientID
        "from_patient_id": merged,
        "to_patient_id": survivor,
        "event_id": event.get("event_id"),
    }


def _to_crosswalk_identifier(ident: dict) -> dict:
    """Traduce el identificador FHIR-ish del evento del bus (system/type/value/use/
    assigning_sede, ver empi-service/app/service.py:_canonical_identifiers) a la forma
    del STRUCT de patient_360.identifiers (source_system/identifier_type/identifier_value/
    assigning_sede/status, ver bigquery/patient_360.sql)."""
    return {
        "source_system": ident.get("system"),
        "identifier_type": ident.get("type"),
        "identifier_value": ident.get("value"),
        "assigning_sede": ident.get("assigning_sede"),
        "status": "ACTIVE",
    }


def build_patient_360_row(
    *,
    empi_id: str,
    dni: str | None = None,
    name: str | None = None,
    birth_date: str | None = None,
    gender: str | None = None,
    identifiers: list[dict] | None = None,
    flags: list[str] | None = None,
    now: datetime | None = None,
) -> dict:
    """Construye una fila de patient_360 (esquema de bigquery.tf / doc §7).

    En el consumidor real, identifiers/lab_results/imaging_studies se completan
    consultando el crosswalk (RDS) y los adaptadores (LIS/PACS); aquí se arma la
    forma canónica de la fila con lo que trae el evento."""
    return {
        "empi_id": empi_id,
        "identity": {
            "dni": dni,
            "name": name,
            "birth_date": birth_date,
            "gender": gender,
        },
        "identifiers": [_to_crosswalk_identifier(i) for i in (identifiers or [])],
        "lab_results": [],
        "imaging_studies": [],
        "encounters": [],
        "flags": flags or [],
        "last_refreshed": (now or datetime.now(timezone.utc)).isoformat(),
    }


def process_event(event: dict) -> dict:
    """Orquesta ambas transformaciones para un evento del bus."""
    retag = dicom_retag_plan(event)
    data = event.get("data", event)

    row = None
    if event.get("event_type") == "PatientMerged":
        row = build_patient_360_row(empi_id=data["survivor_empi_id"])
    elif event.get("event_type") == "PatientRegistered":
        idents = data.get("identifiers", [])
        row = build_patient_360_row(empi_id=event["empi_id"], identifiers=idents)

    return {"event_type": event.get("event_type"), "dicom_retag": retag, "patient_360_row": row}
