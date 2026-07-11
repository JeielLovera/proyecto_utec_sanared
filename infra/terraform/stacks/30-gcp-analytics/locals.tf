locals {
  name_prefix    = "${var.project}-${var.environment}"
  dataset_id     = replace("${local.name_prefix}_analytics", "-", "_") # BigQuery no admite guiones
  consumer_image = var.consumer_image != "" ? var.consumer_image : "us-docker.pkg.dev/cloudrun/container/hello"
}
