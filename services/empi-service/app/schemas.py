"""Contratos HTTP (pydantic). El comando de admisión es ergonómico; el evento que se
persiste es canónico FHIR-compatible (ver service.build_payload)."""
from __future__ import annotations

from datetime import date
from typing import Literal, Optional

from pydantic import BaseModel, Field

SourceSystem = Literal["RENIEC", "HCE", "LIS", "PORTAL", "PACS", "ERP", "AGENDA"]
IdentifierType = Literal["DNI", "HIST", "MRN", "PID", "ACCESSION", "ACC", "SCHED-ID"]


class IdentifierIn(BaseModel):
    type: IdentifierType
    value: str
    assigning_sede: Optional[str] = None
    use: Literal["official", "secondary", "old"] = "official"


class RegisterPatientRequest(BaseModel):
    """Comando RegisterPatient (Flujo A/B)."""
    dni: Optional[str] = Field(default=None, description="DNI (RENIEC).")
    given_name: str
    family_name: str
    birth_date: Optional[date] = None
    gender: Optional[Literal["male", "female", "other", "unknown"]] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    source_system: SourceSystem = "PORTAL"
    verification_status: Literal["VERIFICADO", "INCOMPLETO"] = "INCOMPLETO"
    # Identificadores locales adicionales del canal (nº de historia, cuenta ERP, etc.)
    identifiers: list[IdentifierIn] = []


class RegisterPatientResponse(BaseModel):
    empi_id: str
    decision: Literal["REGISTERED", "LINKED", "MERGED", "REVIEW"]
    match_score: Optional[float] = None
    survivor_empi_id: Optional[str] = None
    events: list[str] = []


class GoldenRecordOut(BaseModel):
    empi_id: str
    dni: Optional[str] = None
    given_name: Optional[str] = None
    family_name: Optional[str] = None
    birth_date: Optional[date] = None
    gender: Optional[str] = None
    record_status: str
    verification_status: str
    active_empi_id: str
    identifiers: list[dict] = []
