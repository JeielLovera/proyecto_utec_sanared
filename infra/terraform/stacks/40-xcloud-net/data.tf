# Lee las salidas de los stacks de cada nube (cableado cross-stack).
data "terraform_remote_state" "aws" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "stacks/10-aws-empi/terraform.tfstate"
    region = var.state_region
  }
}

data "terraform_remote_state" "azure" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "stacks/20-azure-integ/terraform.tfstate"
    region = var.state_region
  }
}

data "terraform_remote_state" "gcp" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "stacks/30-gcp-analytics/terraform.tfstate"
    region = var.state_region
  }
}
