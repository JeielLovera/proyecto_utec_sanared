provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { project = var.project, environment = var.environment, component = "xcloud-vpn", managed_by = "terraform" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id != "" ? var.subscription_id : null
}
