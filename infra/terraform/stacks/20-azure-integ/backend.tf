# Estado remoto en el mismo backend S3 (AWS) del resto de stacks (consistencia).
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
