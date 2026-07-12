# APIs de GCP requeridas por este stack.
locals {
  required_apis = [
    "compute.googleapis.com",
    "healthcare.googleapis.com",
    "bigquery.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "vpcaccess.googleapis.com", # requerido por google_vpc_access_connector (Cloud Run -> VPC)
  ]
}

resource "google_project_service" "this" {
  for_each                   = toset(local.required_apis)
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}
