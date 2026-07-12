variable "project" {
  description = "Prefijo de nombres del stack de observabilidad (distinto del EMPI: es infra de soporte, no del dominio). Corto a propósito: ALB/NLB/target group de AWS limitan el nombre a 32 caracteres."
  type        = string
  default     = "sanared-obs"
}

variable "environment" {
  type    = string
  default = "demo"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# --- Cross-stack: lee la VPC/subredes del núcleo EMPI (10-aws-empi) ----------
# Se despliega en la MISMA VPC que el EMPI para heredar, sin trabajo adicional,
# la conectividad cross-cloud ya establecida por 40-xcloud-net (VPN Azure/GCP) —
# el mismo patrón que ya usa el bus Kafka self-hosted (kafka_selfhosted.tf).
variable "state_bucket" {
  description = "Bucket S3 del estado remoto (output de bootstrap/), para leer la VPC de 10-aws-empi."
  type        = string
}

variable "state_region" {
  type    = string
  default = "us-east-1"
}

# --- Perfil de laboratorio (AWS Academy Learner Lab) --------------------------
variable "create_iam_roles" {
  description = "Crear el rol de ejecución ECS propio. En Learner Lab ponlo en false y usa lab_role_arn (igual que 10-aws-empi)."
  type        = bool
  default     = true
}

variable "lab_role_arn" {
  description = "ARN de un rol existente (p.ej. LabRole de Learner Lab) para ECS cuando create_iam_roles=false."
  type        = string
  default     = ""
}

# --- Acceso administrativo (Grafana UI + Jaeger UI) ---------------------------
variable "admin_cidrs" {
  description = "Rangos permitidos para ver Grafana/Jaeger (tu IP). Vacío = autodetecta la IP pública de quien corre `terraform apply` (data.http.myip) y restringe a /32."
  type        = list(string)
  default     = []
}

variable "grafana_admin_password" {
  description = "Password del usuario admin de Grafana (perfil demo/lab). Cámbiala en tu tfvars, no la dejes en el valor por defecto para un despliegue real."
  type        = string
  default     = "SanaRedObsDemo2026!"
  sensitive   = true
}

variable "azure_vnet_cidr" {
  description = "CIDR de la VNet Azure (20-azure-integ), para permitir OTLP desde el hl7-adapter."
  type        = string
  default     = "10.30.0.0/16"
}

variable "gcp_vpc_cidr" {
  description = "CIDR de la VPC GCP (30-gcp-analytics), para permitir OTLP desde el consumer."
  type        = string
  default     = "10.40.0.0/16"
}

variable "jaeger_image" {
  type    = string
  default = "jaegertracing/all-in-one:1.60"
}

variable "grafana_image" {
  type    = string
  default = "grafana/grafana:11.2.0"
}
