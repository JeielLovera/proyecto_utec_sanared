# Evidencia golden path B2 — corrida 20260712T035642Z

| Paso | Resultado | Archivo |
|---|---|---|
| 1. Alta survivor (Flujo A) | empi_id=EMPI-20260712-0709E2B5 | 01_register_survivor.json |
| 2. Alta entrante sin DNI -> B2 | decision=MERGED, survivor=EMPI-20260712-0709E2B5 | 02_register_duplicate_merge.json |
| 3. Golden record (API) | — | 03_golden_record_api.json |
| 4. Espera consumidores cross-cloud | 30s | — |
| 5. RDS: golden_record_view/crosswalk/audit_trail | — | 05_evidencia_rds.txt |
| 6. Azure: ADT^A40 (HCE mock, echo) | — | 06_hce_mock_adt_a40.log |
| 7. GCP: fila patient_360 | — | 07_patient_360.json |

Trazabilidad: doc 08 §5 (golden path B2), doc 06 §4-6 (flujo), doc 07 §3.7/§7 (audit_trail/patient_360).
