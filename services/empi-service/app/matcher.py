"""Matcher: Paso 1 (lookup exacto), Paso 2 (blocking difuso) y scoring/decisión.
Perfil demo: blocking con pg_trgm sobre golden_record (§4.1/§12). En prod, OpenSearch.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Optional

from . import cache
from .config import settings


@dataclass
class Candidate:
    empi_id: str
    score: float
    features: dict


def lookup_exact_dni(conn, dni: Optional[str]) -> Optional[str]:
    """Paso 1: DNI exacto (§4.2). Redis primero (cache-aside); SQL como fuente/fallback.
    Un hit en Redis evita tocar RDS por completo (early exit, < 10 ms, doc 06 §2)."""
    if not dni:
        return None

    cached = cache.get_dni(dni)
    if cached:
        return cached

    row = conn.execute(
        """
        SELECT empi_id FROM patient_identifier
        WHERE identifier_type = 'DNI' AND identifier_value = %s AND status = 'ACTIVE'
        LIMIT 1
        """,
        (dni,),
    ).fetchone()
    if row:
        cache.set_dni(dni, row["empi_id"])
        return row["empi_id"]
    return None


def block_and_score(
    conn,
    *,
    dni: Optional[str],
    family_name: str,
    birth_date: Optional[date],
    phone: Optional[str],
) -> Optional[Candidate]:
    """Paso 2 + scoring. Bloquea por similitud de apellido (trigram) y puntúa por
    apellido + fecha de nacimiento + teléfono. Devuelve el mejor candidato o None."""
    rows = conn.execute(
        """
        SELECT empi_id, given_name, family_name, dni, birth_date, primary_phone,
               similarity(family_name, %(fam)s) AS sim
        FROM golden_record
        WHERE record_status = 'ACTIVO'
          AND family_name %% %(fam)s          -- pg_trgm: bloqueo difuso
        ORDER BY sim DESC
        LIMIT 25
        """,
        {"fam": family_name},
    ).fetchall()

    best: Optional[Candidate] = None
    for r in rows:
        dni_equal = bool(dni and r["dni"] and r["dni"] == dni)
        dob_equal = bool(birth_date and r["birth_date"] and r["birth_date"] == birth_date)
        phone_equal = bool(phone and r["primary_phone"] and r["primary_phone"] == phone)
        name_sim = float(r["sim"] or 0.0)

        # DNI igual sería match exacto (lo resuelve el Paso 1); aquí ponderamos lo biográfico.
        score = round(0.60 * name_sim + 0.25 * dob_equal + 0.15 * phone_equal, 3)

        features = {
            "name_similarity": round(name_sim, 3),
            "dob_equal": dob_equal,
            "phone_equal": phone_equal,
            "dni_equal": dni_equal,
        }
        if best is None or score > best.score:
            best = Candidate(empi_id=r["empi_id"], score=score, features=features)
    return best


def decide(score: float) -> str:
    """AUTO_MERGE / REVIEW / NO_MATCH según los umbrales (§2.2, §5.2)."""
    if score >= settings.threshold_auto:
        return "AUTO_MERGE"
    if score >= settings.threshold_review:
        return "REVIEW"
    return "NO_MATCH"
