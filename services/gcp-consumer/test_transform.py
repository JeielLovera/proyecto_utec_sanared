"""Verifica las transformaciones puras del consumidor GCP (sin GCP real)."""
from transform import build_patient_360_row, dicom_retag_plan, process_event

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
    "event_id": "ev1",
    "event_type": "PatientRegistered",
    "empi_id": "EMPI-20250115-0A11BB22",
    "data": {"identifiers": [{"system": "urn:pe:reniec:dni", "type": "DNI", "value": "45678912"}]},
}


def test_dicom_retag_plan_para_merge():
    plan = dicom_retag_plan(MERGED)
    assert plan["dicom_tag"] == "00100020"
    assert plan["from_patient_id"] == "EMPI-20260711-8F3A1C7D"
    assert plan["to_patient_id"] == "EMPI-20250115-0A11BB22"


def test_dicom_retag_plan_ignora_otros_eventos():
    assert dicom_retag_plan(REGISTERED) is None


def test_build_patient_360_row_forma_del_esquema():
    row = build_patient_360_row(empi_id="EMPI-1", dni="45678912", flags=["ANTICOAGULADO"])
    assert row["empi_id"] == "EMPI-1"
    assert row["identity"]["dni"] == "45678912"
    assert row["flags"] == ["ANTICOAGULADO"]
    assert row["imaging_studies"] == []  # se completa en el consumidor real
    assert "last_refreshed" in row


def test_process_event_merged_genera_retag_y_row():
    result = process_event(MERGED)
    assert result["dicom_retag"]["to_patient_id"] == "EMPI-20250115-0A11BB22"
    assert result["patient_360_row"]["empi_id"] == "EMPI-20250115-0A11BB22"


def test_process_event_registered_genera_row_sin_retag():
    result = process_event(REGISTERED)
    assert result["dicom_retag"] is None
    assert result["patient_360_row"]["empi_id"] == "EMPI-20250115-0A11BB22"
