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
