provider "aws" {
  region = var.aws_region

  # Gobernanza: toda pieza EMPI lleva estas etiquetas (auditoría, costo, Ley 29733).
  default_tags {
    tags = {
      project             = var.project
      environment         = var.environment
      domain              = "empi"
      managed_by          = "terraform"
      data_classification = "PII"
      cost_center         = "hito3-empi"
    }
  }
}
