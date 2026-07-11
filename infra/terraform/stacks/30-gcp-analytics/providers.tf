provider "google" {
  project = var.project_id
  region  = var.region
  # Credenciales por gcloud CLI (application-default login) o GOOGLE_APPLICATION_CREDENTIALS.
}
