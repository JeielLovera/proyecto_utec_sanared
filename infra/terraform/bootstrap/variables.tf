variable "project" {
  description = "Prefijo de nombres del proyecto."
  type        = string
  default     = "sanared-empi"
}

variable "aws_region" {
  description = "Región AWS donde vive el estado remoto (y el núcleo EMPI)."
  type        = string
  default     = "us-east-1"
}
