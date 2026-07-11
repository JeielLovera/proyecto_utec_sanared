# =============================================================================
# bootstrap — Backend remoto de Terraform (estado LOCAL; aplicar una sola vez)
# Crea el bucket S3 (versionado + cifrado) y la tabla DynamoDB para el lock.
# Los demás stacks usan este backend vía backend.hcl.
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project    = var.project
      component  = "tf-backend"
      managed_by = "terraform"
    }
  }
}

locals {
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  lock_table  = "${var.project}-tflock"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# S3 — almacén del estado
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Protege el estado ante `terraform destroy` accidental de este stack.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB — lock de estado (evita applies concurrentes)
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "lock" {
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
