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
  description = "Región Azure (integración clínica/financiera, ADR-A3M-001)."
  type        = string
  default     = "eastus2"
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
  description = "Bootstrap del bus MSK (AWS) alcanzable por la VPN. Se conoce tras aplicar 10-aws-empi + 40-xcloud-net."
  type        = string
  default     = ""
}
