output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "network_id" {
  description = "Consumido por 40-xcloud-net (VPN)."
  value       = google_compute_network.empi.id
}

output "network_name" {
  value = google_compute_network.empi.name
}

output "subnet_cidr" {
  value = var.vpc_cidr
}

output "bigquery_dataset" {
  value = google_bigquery_dataset.empi.dataset_id
}

output "dicom_store_path" {
  value = var.enable_healthcare_api ? google_healthcare_dicom_store.empi[0].name : null
}

output "cloud_run_url" {
  value = google_cloud_run_v2_service.consumer.uri
}

output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.empi.repository_id}"
}
