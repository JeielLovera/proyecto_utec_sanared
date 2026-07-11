# Mismo backend S3 (AWS) del resto de stacks (consistencia de estado, no de recursos).
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
