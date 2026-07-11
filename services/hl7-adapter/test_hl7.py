"""Verifica el puente evento -> HL7 v2 (doc §8). Módulo puro, sin Azure/Kafka."""
from hl7 import build_adt_a28, build_adt_a40, to_hl7

MERGED = {
    "event_id": "01920000-0004-7000-8000-000000000004",
    "event_type": "PatientMerged",
    "empi_id": "EMPI-20250115-0A11BB22",
    "data": {
        "survivor_empi_id": "EMPI-20250115-0A11BB22",
        "merged_empi_id": "EMPI-20260711-8F3A1C7D",
        "retired_identifiers": [
            {"system": "urn:sanared:hce", "type": "HIST", "value": "HIST-SEDE3-77123"}
        ],
    },
}

REGISTERED = {
    "event_id": "01920000-0001-7000-8000-000000000001",
    "event_type": "PatientRegistered",
    "empi_id": "EMPI-20250115-0A11BB22",
    "data": {
        "identifiers": [
            {"system": "urn:pe:reniec:dni", "type": "DNI", "value": "45678912"},
            {"system": "urn:sanared:portal", "type": "PID", "value": "PT-99182"},
        ]
    },
}


def test_merged_genera_adt_a40_con_mrg():
    msg = build_adt_a40(MERGED)
    segs = msg.strip().split("\r")
    assert segs[0].startswith("MSH|^~\\&|SANARED-EMPI")
    assert "ADT^A40" in segs[0]
    # PID lleva el survivor; MRG lleva el retirado (par que el HCE fusiona).
    assert any(s.startswith("PID") and "EMPI-20250115-0A11BB22" in s for s in segs)
    mrg = [s for s in segs if s.startswith("MRG")][0]
    assert "EMPI-20260711-8F3A1C7D" in mrg
    assert "HIST-SEDE3-77123" in mrg
    assert "SANARED-HCE" in mrg  # autoridad asignadora derivada del URI


def test_registered_genera_adt_a28():
    msg = build_adt_a28(REGISTERED)
    segs = msg.strip().split("\r")
    assert "ADT^A28" in segs[0]
    pid = [s for s in segs if s.startswith("PID")][0]
    assert "45678912" in pid and "RENIEC" in pid
    assert "PT-99182" in pid and "SANARED-PORTAL" in pid


def test_to_hl7_ignora_eventos_sin_adt():
    assert to_hl7({"event_type": "PatientMatchPending"}) is None
