# =============================================================================
# BigQuery — Vista analítica 360° (plano 5, §7). Mismo esquema que
# entregables_hito3/07_Scripts_Modelo_Datos/bigquery/patient_360.sql (fuente de verdad
# del DDL); aquí se declara como recurso Terraform para que el stack sea autocontenible.
# =============================================================================
resource "google_bigquery_dataset" "empi" {
  dataset_id                  = local.dataset_id
  location                    = var.region
  default_table_expiration_ms = null
  depends_on                  = [google_project_service.this]
}

resource "google_bigquery_table" "patient_360" {
  dataset_id          = google_bigquery_dataset.empi.dataset_id
  table_id            = "patient_360"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "last_refreshed"
  }

  clustering = ["empi_id"]

  schema = jsonencode([
    { name = "empi_id", type = "STRING", mode = "REQUIRED" },
    {
      name = "identity", type = "RECORD", mode = "NULLABLE",
      fields = [
        { name = "dni", type = "STRING", mode = "NULLABLE" },
        { name = "name", type = "STRING", mode = "NULLABLE" },
        { name = "birth_date", type = "DATE", mode = "NULLABLE" },
        { name = "gender", type = "STRING", mode = "NULLABLE" },
      ]
    },
    {
      name = "identifiers", type = "RECORD", mode = "REPEATED",
      fields = [
        { name = "source_system", type = "STRING", mode = "NULLABLE" },
        { name = "identifier_type", type = "STRING", mode = "NULLABLE" },
        { name = "identifier_value", type = "STRING", mode = "NULLABLE" },
        { name = "assigning_sede", type = "STRING", mode = "NULLABLE" },
        { name = "status", type = "STRING", mode = "NULLABLE" },
      ]
    },
    {
      name = "lab_results", type = "RECORD", mode = "REPEATED",
      fields = [
        { name = "test_code", type = "STRING", mode = "NULLABLE" },
        { name = "test_name", type = "STRING", mode = "NULLABLE" },
        { name = "value", type = "STRING", mode = "NULLABLE" },
        { name = "unit", type = "STRING", mode = "NULLABLE" },
        { name = "ref_range", type = "STRING", mode = "NULLABLE" },
        { name = "abnormal", type = "BOOLEAN", mode = "NULLABLE" },
        { name = "resulted_at", type = "TIMESTAMP", mode = "NULLABLE" },
        { name = "source_mrn", type = "STRING", mode = "NULLABLE" },
      ]
    },
    {
      name = "imaging_studies", type = "RECORD", mode = "REPEATED",
      fields = [
        { name = "accession", type = "STRING", mode = "NULLABLE" },
        { name = "modality", type = "STRING", mode = "NULLABLE" },
        { name = "body_part", type = "STRING", mode = "NULLABLE" },
        { name = "sede", type = "STRING", mode = "NULLABLE" },
        { name = "study_date", type = "DATE", mode = "NULLABLE" },
        { name = "study_uid", type = "STRING", mode = "NULLABLE" },
      ]
    },
    {
      name = "encounters", type = "RECORD", mode = "REPEATED",
      fields = [
        { name = "encounter_id", type = "STRING", mode = "NULLABLE" },
        { name = "sede", type = "STRING", mode = "NULLABLE" },
        { name = "class", type = "STRING", mode = "NULLABLE" },
        { name = "start_at", type = "TIMESTAMP", mode = "NULLABLE" },
        { name = "end_at", type = "TIMESTAMP", mode = "NULLABLE" },
        { name = "reason", type = "STRING", mode = "NULLABLE" },
      ]
    },
    { name = "flags", type = "STRING", mode = "REPEATED" },
    { name = "last_refreshed", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}

# =============================================================================
# Vista consolidada: 1 fila VIGENTE por empi_id.
#
# patient_360 es append-only (cada evento inserta, nunca actualiza -- BigQuery
# streaming insert no tiene upsert nativo). El evento PatientMerged en particular
# inserta una fila con identity/identifiers vacíos (transform.py solo conoce el
# empi_id del survivor en ese punto). Esta vista evita que "la última fila gane"
# borre datos: arrastra el último identity/identifiers NO vacío por empi_id, y
# usa la fila más reciente para lab_results/imaging_studies/encounters/flags.
# =============================================================================
resource "google_bigquery_table" "patient_360_current" {
  dataset_id          = google_bigquery_dataset.empi.dataset_id
  table_id            = "patient_360_current"
  deletion_protection = false

  view {
    use_legacy_sql = false
    query          = <<-SQL
      WITH last_identity AS (
        SELECT empi_id, identity,
               ROW_NUMBER() OVER (PARTITION BY empi_id ORDER BY last_refreshed DESC) AS rn
        FROM `${var.project_id}.${google_bigquery_dataset.empi.dataset_id}.patient_360`
        WHERE identity.dni IS NOT NULL OR identity.name IS NOT NULL
      ),
      last_identifiers AS (
        SELECT empi_id, identifiers,
               ROW_NUMBER() OVER (PARTITION BY empi_id ORDER BY last_refreshed DESC) AS rn
        FROM `${var.project_id}.${google_bigquery_dataset.empi.dataset_id}.patient_360`
        WHERE ARRAY_LENGTH(identifiers) > 0
      ),
      latest_row AS (
        SELECT empi_id, lab_results, imaging_studies, encounters, flags, last_refreshed,
               ROW_NUMBER() OVER (PARTITION BY empi_id ORDER BY last_refreshed DESC) AS rn
        FROM `${var.project_id}.${google_bigquery_dataset.empi.dataset_id}.patient_360`
      )
      SELECT
        l.empi_id,
        i.identity,
        idf.identifiers,
        l.lab_results,
        l.imaging_studies,
        l.encounters,
        l.flags,
        l.last_refreshed
      FROM latest_row l
      LEFT JOIN last_identity i ON i.empi_id = l.empi_id AND i.rn = 1
      LEFT JOIN last_identifiers idf ON idf.empi_id = l.empi_id AND idf.rn = 1
      WHERE l.rn = 1
    SQL
  }
}
