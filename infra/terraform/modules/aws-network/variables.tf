variable "name_prefix" {
  description = "Prefijo de nombres (p. ej. sanared-empi-demo)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Nº de AZs a usar."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "true = 1 NAT compartido (ahorro); false = 1 NAT por AZ (HA)."
  type        = bool
  default     = true
}
