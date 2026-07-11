variable "project" {
  description = "Prefijo de nombres del proyecto."
  type        = string
  default     = "sanared-empi"
}

variable "environment" {
  description = "Perfil de despliegue: demo (SKUs mínimos) o prod (SKUs del doc §12)."
  type        = string
  default     = "demo"
  validation {
    condition     = contains(["demo", "prod"], var.environment)
    error_message = "environment debe ser 'demo' o 'prod'."
  }
}

variable "aws_region" {
  description = "Región AWS del núcleo EMPI (dominio paciente, ADR-A3M-001)."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC del EMPI. No debe solapar con Azure/GCP (cross-cloud VPN)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Nº de zonas de disponibilidad (alta disponibilidad RNF-02)."
  type        = number
  default     = 2
}

variable "internal_client_cidrs" {
  description = "Rangos de sistemas internos (Admisión on-prem, Agenda) que alcanzan el ALB privado por Direct Connect/VPN (ADR-A3M-003)."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}
