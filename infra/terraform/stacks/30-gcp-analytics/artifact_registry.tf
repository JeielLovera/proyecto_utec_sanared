# Registro de la imagen del consumidor GCP (services/gcp-consumer/).
resource "google_artifact_registry_repository" "empi" {
  location      = var.region
  repository_id = "${local.name_prefix}-consumer"
  format        = "DOCKER"
  depends_on    = [google_project_service.this]
}
