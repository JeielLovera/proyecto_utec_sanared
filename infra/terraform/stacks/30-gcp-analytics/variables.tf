variable "project" {
  type    = string
  default = "sanared-empi"
}

variable "environment" {
  type    = string
  default = "demo"
  validation {
    condition     = contains(["demo", "prod"], var.environment)
    error_message = "environment debe ser 'demo' o 'prod'."
  }
}

variable "project_id" {
  description = "ID del proyecto GCP (cuenta de laboratorio o real)."
  type        = string
}

variable "region" {
  description = "Región GCP (imágenes + analítica, ADR-A3M-001)."
  type        = string
  default     = "us-central1"
}

variable "vpc_cidr" {
  description = "CIDR de la subred GCP. No debe solapar con AWS (10.20/16) ni Azure (10.30/16)."
  type        = string
  default     = "10.40.0.0/16"
}

variable "aws_cidr" {
  description = "CIDR de la VPC AWS (para el firewall que permite tráfico desde la VPN)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "enable_healthcare_api" {
  description = "Provisiona Cloud Healthcare API (dataset + DICOM store). Requiere habilitar el API en el proyecto."
  type        = bool
  default     = true
}

variable "consumer_image" {
  description = "Imagen del consumidor GCP en Artifact Registry. Vacío = usa una imagen pública de placeholder hasta el primer build."
  type        = string
  default     = ""
}

variable "consumer_max_instances" {
  description = "Tope de instancias del consumidor Cloud Run (fijo para evitar drift: sin este valor Google le pone 100 por defecto y cada plan posterior lo marca como cambio)."
  type        = number
  default     = 3
}

variable "kafka_bootstrap" {
  description = "Bootstrap del bus (host:port). Output kafka_bootstrap de 10-aws-empi."
  type        = string
  default     = ""
}

variable "kafka_auth_mode" {
  description = "iam (MSK Serverless real) | plaintext (Redpanda self-hosted, sin credencial AWS). Output kafka_auth_mode de 10-aws-empi."
  type        = string
  default     = "iam"
}

variable "aws_access_key_id" {
  description = "Access key del usuario IAM de solo-consumo del bus (output kafka_xcloud_access_key_id de 10-aws-empi)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "Secret de la access key anterior (output kafka_xcloud_secret_access_key de 10-aws-empi)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_session_token" {
  description = "Session token, SOLO si usas credenciales temporales (p. ej. AWS Academy Learner Lab, ~4h de vigencia) en vez de un usuario IAM dedicado. Vacío si usas access key permanente."
  type        = string
  default     = ""
  sensitive   = true
}
