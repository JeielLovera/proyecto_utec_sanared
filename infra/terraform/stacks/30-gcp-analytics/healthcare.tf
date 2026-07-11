# =============================================================================
# Cloud Healthcare API — DICOM store para el re-tag de estudios inter-sede (§6, §7).
# El consumidor GCP mueve/retagea el PatientID del estudio de merged_empi_id -> survivor.
# =============================================================================
resource "google_healthcare_dataset" "empi" {
  count    = var.enable_healthcare_api ? 1 : 0
  name     = "${replace(local.name_prefix, "-", "_")}_imaging"
  location = var.region

  depends_on = [google_project_service.this]
}

resource "google_healthcare_dicom_store" "empi" {
  count   = var.enable_healthcare_api ? 1 : 0
  name    = "pacs-dicom-store"
  dataset = google_healthcare_dataset.empi[0].id
  labels  = { domain = "empi-imaging" }
}
