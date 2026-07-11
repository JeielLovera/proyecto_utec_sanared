variable "project" {
  type    = string
  default = "sanared-empi"
}

variable "environment" {
  type    = string
  default = "demo"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "subscription_id" {
  type    = string
  default = ""
}

# Bucket del estado remoto (output de bootstrap/). Necesario para leer los stacks 10 y 20.
variable "state_bucket" {
  description = "Bucket S3 del estado (sanared-empi-tfstate-<account_id>)."
  type        = string
}

variable "state_region" {
  type    = string
  default = "us-east-1"
}

variable "shared_key" {
  description = "Pre-shared key IPSec (debe coincidir en ambos lados). 8-64 chars."
  type        = string
  default     = "SanaRedEmpiXcloud2026Psk"
  sensitive   = true
}

variable "azure_vnet_cidr" {
  description = "CIDR de la VNet Azure (para la ruta AWS->Azure)."
  type        = string
  default     = "10.30.0.0/16"
}

variable "gcp_project_id" {
  description = "ID del proyecto GCP (mismo que 30-gcp-analytics)."
  type        = string
  default     = ""
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_vpc_cidr" {
  description = "CIDR de la VPC GCP (para la ruta AWS->GCP)."
  type        = string
  default     = "10.40.0.0/16"
}

variable "shared_key_gcp" {
  description = "Pre-shared key IPSec para el túnel AWS<->GCP."
  type        = string
  default     = "SanaRedEmpiXcloudGcp2026Psk"
  sensitive   = true
}
