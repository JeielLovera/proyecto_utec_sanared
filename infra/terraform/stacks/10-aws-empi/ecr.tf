# Registro de la imagen del servicio EMPI (services/empi-service/).
resource "aws_ecr_repository" "empi" {
  name                 = "${var.project}/empi-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.empi.arn
  }

  tags = { Name = "${local.name_prefix}-ecr" }
}

# Conserva solo las últimas 10 imágenes (higiene/costo).
resource "aws_ecr_lifecycle_policy" "empi" {
  repository = aws_ecr_repository.empi.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantener 10 imagenes"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
