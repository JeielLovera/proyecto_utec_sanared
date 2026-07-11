"""Casos de uso del EMPI: comando -> matching -> evento(s) -> proyección.

Fiel al modelo (07_..._Modelo_Datos.md): el único punto de escritura de verdad es
patient_events (append-only). Las proyecciones (golden_record, crosswalk, ...) se
derivan aquí de forma SÍNCRONA (proyección inline) — simplificación directa del MVP;
en producción el proyector es un consumidor separado, pero el contrato de datos es idéntico.
"""
from __future__ import annotations

import uuid
from datetime import date

from psycopg.types.json import Json

from . import matcher
from .bus import bus
from .config import settings
from .ids import TYPE_TO_SOURCE, TYPE_TO_URI, new_empi_id
from .schemas import RegisterPatientRequest, RegisterPatientResponse

ADMISSION_ACTOR = "SISTEMA:empi"


# ---------------------------------------------------------------------------
# Event Store (append-only) + proyección inline
# ---------------------------------------------------------------------------
def _append_event(conn, *, empi_id, event_type, payload, source_system,
                  correlation_id, actor=ADMISSION_ACTOR, causation_id=None):
    """Inserta en patient_events con concurrencia optimista (version por agregado)."""
    v = conn.execute(
        "SELECT COALESCE(MAX(version), 0) + 1 AS v FROM patient_events WHERE empi_id = %s",
        (empi_id,),
    ).fetchone()["v"]
    row = conn.execute(
        """
        INSERT INTO patient_events
            (empi_id, event_type, version, payload, actor, source_system, correlation_id, causation_id, occurred_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now())
        RETURNING event_id, occurred_at
        """,
        (empi_id, event_type, v, Json(payload), actor, source_system,
         str(correlation_id), causation_id),
    ).fetchone()
    event_id, occurred_at = row["event_id"], row["occurred_at"]
    _project(conn, event_type, empi_id, payload)
    # Publica al bus (NoOp por ahora); eventos internos se ignoran dentro del bus.
    bus.publish(event_type, empi_id, event_id, correlation_id,
                occurred_at.isoformat(), payload)
    return str(event_id)


def _project(conn, event_type, empi_id, payload):
    if event_type == "PatientRegistered":
        _project_registered(conn, empi_id, payload)
    elif event_type == "IdentifierLinked":
        _insert_identifier(conn, empi_id, payload["identifier"])
    elif event_type == "PatientMerged":
        _project_merged(conn, payload)
    # PatientMatchPending: solo cola de revisión (se maneja en el caso de uso)


def _project_registered(conn, empi_id, payload):
    name = payload["name"]
    idents = payload["identifiers"]
    dni = next((i["value"] for i in idents if i["type"] == "DNI"), None)
    phone = next((t["value"] for t in payload.get("telecom", []) if t["system"] == "phone"), None)
    email = next((t["value"] for t in payload.get("telecom", []) if t["system"] == "email"), None)

    conn.execute(
        """
        INSERT INTO golden_record
            (empi_id, dni, given_name, family_name, birth_date, gender,
             primary_phone, primary_email, record_status, verification_status, active_empi_id)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (empi_id) DO NOTHING
        """,
        (empi_id, dni, name["given"], name["family"], payload.get("birth_date"),
         payload.get("gender"), phone, email, payload["record_status"],
         payload["verification_status"], empi_id),
    )
    for ident in idents:
        _insert_identifier(conn, empi_id, ident)

    conn.execute(
        """INSERT INTO patient_name (empi_id, given_name, family_name, use, source_system)
           VALUES (%s, %s, %s, 'official', %s)""",
        (empi_id, name["given"], name["family"], payload["source_system"]),
    )
    if phone:
        conn.execute(
            """INSERT INTO patient_contact (empi_id, system, value, use, source_system, verified)
               VALUES (%s, 'PHONE', %s, 'mobile', %s, false)""",
            (empi_id, phone, payload["source_system"]),
        )
    if email:
        conn.execute(
            """INSERT INTO patient_contact (empi_id, system, value, use, source_system, verified)
               VALUES (%s, 'EMAIL', %s, 'home', %s, false)""",
            (empi_id, email, payload["source_system"]),
        )


def _insert_identifier(conn, empi_id, ident):
    source = TYPE_TO_SOURCE[ident["type"]]
    conn.execute(
        """
        INSERT INTO patient_identifier
            (empi_id, source_system, identifier_type, identifier_value, assigning_sede, use, status)
        VALUES (%s, %s, %s, %s, %s, %s, 'ACTIVE')
        ON CONFLICT DO NOTHING
        """,
        (empi_id, source, ident["type"], ident["value"],
         ident.get("assigning_sede"), ident.get("use", "official")),
    )


def _project_merged(conn, payload):
    survivor = payload["survivor_empi_id"]
    merged = payload["merged_empi_id"]
    # El absorbido queda inactivo y redirige al survivor (§9).
    conn.execute(
        """UPDATE golden_record
           SET record_status = 'INACTIVO_FUSIONADO', active_empi_id = %s, updated_at = now()
           WHERE empi_id = %s""",
        (survivor, merged),
    )
    # Sus identificadores se conservan pero se retiran (§3.2).
    conn.execute(
        "UPDATE patient_identifier SET status = 'RETIRED', use = 'old' WHERE empi_id = %s",
        (merged,),
    )


# ---------------------------------------------------------------------------
# Construcción del payload canónico (FHIR-compatible)
# ---------------------------------------------------------------------------
def _canonical_identifiers(req: RegisterPatientRequest) -> list[dict]:
    idents: list[dict] = []
    if req.dni:
        idents.append({"system": TYPE_TO_URI["DNI"], "type": "DNI",
                       "value": req.dni, "use": "official", "assigning_sede": None})
    for i in req.identifiers:
        idents.append({"system": TYPE_TO_URI[i.type], "type": i.type, "value": i.value,
                       "use": i.use, "assigning_sede": i.assigning_sede})
    return idents


def _registered_payload(empi_id, req: RegisterPatientRequest, record_status: str) -> dict:
    telecom = []
    if req.phone:
        telecom.append({"system": "phone", "value": req.phone, "use": "mobile"})
    if req.email:
        telecom.append({"system": "email", "value": req.email})
    return {
        "empi_id": empi_id,
        "identifiers": _canonical_identifiers(req),
        "name": {"given": req.given_name, "family": req.family_name},
        "birth_date": req.birth_date.isoformat() if req.birth_date else None,
        "gender": req.gender,
        "telecom": telecom,
        "record_status": record_status,
        "verification_status": req.verification_status,
        "source_system": req.source_system,
    }


# ---------------------------------------------------------------------------
# Caso de uso: RegisterPatient (Flujo A / B)
# ---------------------------------------------------------------------------
def register_patient(conn, req: RegisterPatientRequest, correlation_id: uuid.UUID) -> RegisterPatientResponse:
    events: list[str] = []

    # Paso 1 — DNI exacto: misma persona -> enriquecer crosswalk, no duplicar (B1).
    existing = matcher.lookup_exact_dni(conn, req.dni)
    if existing:
        for ident in req.identifiers:
            eid = _append_event(
                conn, empi_id=existing, event_type="IdentifierLinked",
                payload={"empi_id": existing,
                         "identifier": {"system": TYPE_TO_URI[ident.type], "type": ident.type,
                                        "value": ident.value, "assigning_sede": ident.assigning_sede,
                                        "use": ident.use},
                         "source_system": req.source_system},
                source_system=req.source_system, correlation_id=correlation_id)
            events.append(eid)
        return RegisterPatientResponse(empi_id=existing, decision="LINKED",
                                       match_score=1.0, events=events)

    # Paso 2 — blocking + scoring.
    best = matcher.block_and_score(conn, dni=req.dni, family_name=req.family_name,
                                   birth_date=req.birth_date, phone=req.phone)
    band = matcher.decide(best.score) if best else "NO_MATCH"

    if band == "AUTO_MERGE":
        # B2: registrar el entrante y fusionarlo en el survivor.
        new_id = _register(conn, req, correlation_id, record_status="ACTIVO", events=events)
        _merge(conn, survivor=best.empi_id, merged=new_id, candidate=best,
               correlation_id=correlation_id, events=events)
        return RegisterPatientResponse(empi_id=new_id, decision="MERGED",
                                       match_score=best.score, survivor_empi_id=best.empi_id,
                                       events=events)

    if band == "REVIEW":
        # B3: registrar en revisión + encolar para el Operador de Gobierno.
        new_id = _register(conn, req, correlation_id, record_status="EN_REVISION", events=events)
        _flag_for_review(conn, existing=best.empi_id, incoming=new_id, candidate=best,
                         correlation_id=correlation_id, events=events)
        return RegisterPatientResponse(empi_id=new_id, decision="REVIEW",
                                       match_score=best.score, events=events)

    # Flujo A — sin match: alta nueva.
    new_id = _register(conn, req, correlation_id, record_status="ACTIVO", events=events)
    return RegisterPatientResponse(empi_id=new_id, decision="REGISTERED",
                                   match_score=(best.score if best else None), events=events)


def _register(conn, req, correlation_id, *, record_status, events) -> str:
    empi_id = new_empi_id()
    payload = _registered_payload(empi_id, req, record_status)
    events.append(_append_event(conn, empi_id=empi_id, event_type="PatientRegistered",
                                payload=payload, source_system=req.source_system,
                                correlation_id=correlation_id))
    return empi_id


def _merge(conn, *, survivor, merged, candidate, correlation_id, events):
    retired = conn.execute(
        """SELECT source_system, identifier_type AS type, identifier_value AS value
           FROM patient_identifier WHERE empi_id = %s AND status = 'ACTIVE'""",
        (merged,),
    ).fetchall()
    payload = {
        "survivor_empi_id": survivor,
        "merged_empi_id": merged,
        "decided_by": "AUTO",
        "match_score": candidate.score,
        "model_version": settings.model_version,
        "retired_identifiers": [
            {"system": TYPE_TO_URI[r["type"]], "type": r["type"], "value": r["value"]}
            for r in retired
        ],
    }
    event_id = _append_event(conn, empi_id=survivor, event_type="PatientMerged",
                             payload=payload, source_system="HCE",
                             correlation_id=correlation_id)
    events.append(event_id)
    # Evidencia + linaje.
    conn.execute(
        """INSERT INTO match_candidate
               (empi_id_a, empi_id_b_or_stg, match_score, features, band, model_version, correlation_id)
           VALUES (%s, %s, %s, %s, 'AUTO_MERGE', %s, %s)""",
        (survivor, merged, candidate.score, Json(candidate.features),
         settings.model_version, str(correlation_id)),
    )
    conn.execute(
        """INSERT INTO merge_link
               (survivor_empi_id, merged_empi_id, match_score, decided_by, merge_event_id)
           VALUES (%s, %s, %s, 'AUTO', %s)""",
        (survivor, merged, candidate.score, event_id),
    )


def _flag_for_review(conn, *, existing, incoming, candidate, correlation_id, events):
    cand = conn.execute(
        """INSERT INTO match_candidate
               (empi_id_a, empi_id_b_or_stg, match_score, features, band, model_version, correlation_id)
           VALUES (%s, %s, %s, %s, 'REVIEW', %s, %s)
           RETURNING candidate_pair_id""",
        (existing, incoming, candidate.score, Json(candidate.features),
         settings.model_version, str(correlation_id)),
    ).fetchone()
    conn.execute(
        """INSERT INTO review_queue (candidate_pair_id, priority, status)
           VALUES (%s, %s, 'PENDING')""",
        (cand["candidate_pair_id"], candidate.score),
    )
    events.append(_append_event(
        conn, empi_id=incoming, event_type="PatientMatchPending",
        payload={"candidate_pair_id": str(cand["candidate_pair_id"]),
                 "empi_id_existing": existing, "incoming_ref": incoming,
                 "match_score": candidate.score, "band": "REVIEW",
                 "features": candidate.features},
        source_system="HCE", correlation_id=correlation_id))


# ---------------------------------------------------------------------------
# Lectura
# ---------------------------------------------------------------------------
def get_golden(conn, empi_id: str):
    gr = conn.execute("SELECT * FROM golden_record WHERE empi_id = %s", (empi_id,)).fetchone()
    if not gr:
        return None
    idents = conn.execute(
        """SELECT source_system, identifier_type, identifier_value, assigning_sede, use, status
           FROM patient_identifier WHERE empi_id = %s ORDER BY identifier_type""",
        (empi_id,),
    ).fetchall()
    gr["identifiers"] = idents
    return gr
