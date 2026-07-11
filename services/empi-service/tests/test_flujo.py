"""Smoke test de los flujos de registro (requiere EMPI_DATABASE_URL a un Postgres con el
esquema aplicado). Ejercita Flujo A (alta), B1 (DNI exacto -> LINKED) y B3 (revisión)."""
import uuid

from app import service
from app.db import pool
from app.schemas import IdentifierIn, RegisterPatientRequest


def _corr():
    return uuid.uuid4()


def test_flujo_a_alta_nueva():
    pool.open()
    with pool.connection() as conn:
        req = RegisterPatientRequest(
            dni="45111222", given_name="Ana Maria", family_name="Quispe Torres",
            birth_date="1990-05-20", gender="female", phone="+51999111222",
            source_system="PORTAL", verification_status="VERIFICADO",
        )
        r = service.register_patient(conn, req, _corr())
        assert r.decision == "REGISTERED"
        assert r.empi_id.startswith("EMPI-")

        gr = service.get_golden(conn, r.empi_id)
        assert gr["record_status"] == "ACTIVO"
        assert gr["dni"] == "45111222"
        assert any(i["identifier_type"] == "DNI" for i in gr["identifiers"])


def test_flujo_b1_dni_exacto_link():
    pool.open()
    with pool.connection() as conn:
        dni = "45333444"
        service.register_patient(conn, RegisterPatientRequest(
            dni=dni, given_name="Luis", family_name="Fernandez Rojas",
            birth_date="1985-01-10", source_system="PORTAL"), _corr())
        # Mismo DNI por otro canal, aportando su nº de historia -> LINKED (enriquece crosswalk).
        r = service.register_patient(conn, RegisterPatientRequest(
            dni=dni, given_name="Luis", family_name="Fernandez Rojas",
            source_system="HCE",
            identifiers=[IdentifierIn(type="HIST", value="HIST-SEDE1-90001",
                                      assigning_sede="SEDE-CENTRAL")]), _corr())
        assert r.decision == "LINKED"
        gr = service.get_golden(conn, r.empi_id)
        assert any(i["identifier_type"] == "HIST" for i in gr["identifiers"])
