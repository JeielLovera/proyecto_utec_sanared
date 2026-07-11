# Security groups del plano de datos. Modelo least-privilege: solo el SG de la app
# (tareas ECS del servicio EMPI) alcanza RDS/Redis/OpenSearch. El SG de la app se
# reutiliza en el paso de cómputo (ecs.tf).
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app"
  description = "Tareas ECS del servicio EMPI"
  vpc_id      = module.network.vpc_id

  egress {
    description = "salida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-app" }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds"
  description = "PostgreSQL Event Store + proyecciones"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "PostgreSQL desde la app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-rds" }
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis"
  description = "ElastiCache Redis (lookup/anti-recalculo)"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "Redis desde la app"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-redis" }
}

resource "aws_security_group" "opensearch" {
  count       = var.enable_opensearch ? 1 : 0
  name        = "${local.name_prefix}-opensearch"
  description = "OpenSearch (blocking del matcher)"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "HTTPS desde la app"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-opensearch" }
}
