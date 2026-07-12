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

    # min_instance_count=1: mantiene el contenedor vivo para el hilo de fondo del
    # consumidor Kafka (main.py lo arranca si KAFKA_BOOTSTRAP está seteado). Sin esto,
    # Cloud Run escala a cero y el consumidor no correría de forma continua.
    # max_instance_count fijo (no lo dejamos en null): si no se fija, Google le pone 100
    # por defecto al crear el recurso y cada plan posterior lo muestra como drift (100 -> null)
    # sin que nada haya cambiado.
    scaling {
      min_instance_count = var.kafka_bootstrap != "" ? 1 : 0
      max_instance_count = var.consumer_max_instances
    }

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
        value = var.kafka_bootstrap
      }
      env {
        name  = "KAFKA_AUTH"
        value = var.kafka_auth_mode
      }
      env {
        name  = "KAFKA_REGION"
        value = "us-east-1"
      }
      # Credencial cross-cloud del consumidor Kafka (solo-lectura del bus, §40-xcloud-net).
      # Vacías si no se proveen; el consumidor de fondo solo arranca si KAFKA_BOOTSTRAP != "".
      env {
        name  = "AWS_ACCESS_KEY_ID"
        value = var.aws_access_key_id
      }
      env {
        name  = "AWS_SECRET_ACCESS_KEY"
        value = var.aws_secret_access_key
      }
      # Solo si usas credenciales temporales (Learner Lab, ~4h). El signer MSK-IAM la
      # detecta automáticamente vía la cadena de credenciales por defecto de boto3.
      env {
        name  = "AWS_SESSION_TOKEN"
        value = var.aws_session_token
      }
    }
  }

  depends_on = [google_project_service.this]
}
