data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# VPC/subredes del núcleo EMPI (ver variables.tf: mismo VPC, hereda la VPN cross-cloud).
data "terraform_remote_state" "empi" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "stacks/10-aws-empi/terraform.tfstate"
    region = var.state_region
  }
}

# Autodetección de la IP del deployer cuando no se especifica admin_cidrs (ver variables.tf).
data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}
