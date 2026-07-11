# =============================================================================
# Cloud Run — consumidor GCP (services/gcp-consumer/). Recibe identity.patient.merged
# (por la VPN/bus AWS) y: (a) re-etiqueta el estudio DICOM al survivor, (b) refresca
# la fila patient_360 en BigQuery.
# =============================================================================
resource "google_service_account" "consumer" {
  account_id   = "${substr(local.name_prefix, 0, 20)}-consumer"
  display_name = "EMPI GCP consumer (Healthcare API + BigQuery)"
}

resource "google_project_iam_member" "consumer_healthcare" {
  count   = var.enable_healthcare_api ? 1 : 0
  project = var.project_id
  role    = "roles/healthcare.dicomEditor"
  member  = "serviceAccount:${google_service_account.consumer.email}"
}

resource "google_project_iam_member" "consumer_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.consumer.email}"
}

resource "google_cloud_run_v2_service" "consumer" {
  name     = "${local.name_prefix}-consumer"
  location = var.region

  template {
    service_account = google_service_account.consumer.email

    vpc_access {
      connector = google_vpc_access_connector.empi.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = local.consumer_image
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      env {
        name  = "BQ_DATASET"
        value = google_bigquery_dataset.empi.dataset_id
      }
      env {
        name  = "BQ_TABLE"
        value = google_bigquery_table.patient_360.table_id
      }
      env {
        name  = "DICOM_STORE_PATH"
        value = var.enable_healthcare_api ? google_healthcare_dicom_store.empi[0].name : ""
      }
      env {
        name  = "KAFKA_BOOTSTRAP"
        value = "" # se completa tras 10-aws-empi + 40-xcloud-net
      }
    }
  }

  depends_on = [google_project_service.this]
}
