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

# --- Perfil de laboratorio (AWS Academy Learner Lab) --------------------------
variable "create_iam_roles" {
  description = "Crear roles IAM propios de ECS. En Learner Lab ponlo en false (bloquea iam:CreateRole) y usa lab_role_arn."
  type        = bool
  default     = true
}

variable "lab_role_arn" {
  description = "ARN de un rol existente (p.ej. LabRole de Learner Lab) para ECS cuando create_iam_roles=false."
  type        = string
  default     = ""
}

variable "enable_opensearch" {
  description = "Provisiona OpenSearch (blocking de producción). En Learner Lab ponlo en false: el servicio usa pg_trgm."
  type        = bool
  default     = true
}

variable "enable_msk" {
  description = "Provisiona un bus de eventos real (MSK Serverless o Redpanda self-hosted, ver use_self_hosted_kafka). false: el servicio usa bus_backend=noop (Flujo A no lo necesita)."
  type        = bool
  default     = true
}

variable "use_self_hosted_kafka" {
  description = "true: reemplaza MSK Serverless por Redpanda en ECS Fargate (misma VPC). Úsalo si tu cuenta bloquea kafka:CreateClusterV2 (p. ej. AWS Academy Learner Lab). Broker reemplazable sin tocar código (ADR-A3M-008); sin autenticación IAM (perímetro por security group + VPN)."
  type        = bool
  default     = false
}

variable "rds_engine_version" {
  description = "Version del motor PostgreSQL de RDS. Usa el major ('16') para que RDS elija el minor disponible en la region/cuenta."
  type        = string
  default     = "16"
}
