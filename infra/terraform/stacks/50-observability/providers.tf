provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project     = var.project
      environment = var.environment
      domain      = "observability"
      managed_by  = "terraform"
      cost_center = "hito3-empi"
    }
  }
}
