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

variable "subscription_id" {
  description = "Azure Subscription ID (o vía az CLI / ARM_SUBSCRIPTION_ID)."
  type        = string
  default     = ""
}

variable "location" {
  description = "Región Azure (integración clínica/financiera, ADR-A3M-001). Ignorada si create_resource_group=false (se usa la región del RG existente)."
  type        = string
  default     = "eastus2"
}

variable "create_resource_group" {
  description = "false: reutiliza un Resource Group ya existente (existing_resource_group_name) en vez de crear uno. Úsalo en suscripciones académicas sin permiso de crear RGs a nivel de suscripción."
  type        = bool
  default     = true
}

variable "existing_resource_group_name" {
  description = "Nombre del Resource Group existente a reutilizar (requiere create_resource_group=false)."
  type        = string
  default     = ""
}

variable "functions_plan_sku" {
  description = "SKU del plan de la Function App. Vacío = EP1/EP2 según environment (as-is). Usa 'Y1' (Consumption) en suscripciones académicas donde Elastic Premium devuelve 401 'Operation cannot be completed without additional quota' (cuota de VM dedicada a 0)."
  type        = string
  default     = ""
}

variable "enable_function_app" {
  description = "false: no crea App Service Plan ni Function App. Úsalo si tu suscripción tiene cuota 0 de VMs para Microsoft.Web en la región (Y1 también falla, no solo EP1/EP2). La Function App es solo el disparador HTTP de demo; el consumo REAL del bus corre en el ACI de hl7_consumer.tf (kafka_consumer.py), que no depende de este recurso."
  type        = bool
  default     = true
}

variable "vnet_cidr" {
  description = "CIDR de la VNet Azure. No debe solapar con AWS (10.20/16) ni GCP (10.40/16)."
  type        = string
  default     = "10.30.0.0/16"
}

variable "enable_apim" {
  description = "Provisiona API Management (egress a legados). Es el recurso más lento/caro (~30-45 min)."
  type        = bool
  default     = true
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

variable "enable_kafka_consumer" {
  description = "Despliega el consumidor Kafka persistente (ACI) del adaptador HL7. Requiere kafka_bootstrap + credencial AWS."
  type        = bool
  default     = false
}

variable "hl7_consumer_image" {
  description = "Imagen del ACI consumidor HL7 (services/hl7-adapter). Vacío = imagen placeholder pública hasta el primer build/push real (mismo patrón que consumer_image en 30-gcp-analytics)."
  type        = string
  default     = ""
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

variable "otel_exporter_endpoint" {
  description = "host:puerto OTLP/HTTP del stack 50-observability (output otlp_http_endpoint). Vacío = tracing deshabilitado (tracing.py cae al tracer no-op)."
  type        = string
  default     = ""
}
