# =============================================================================
# Cómputo — ECS Fargate: servicio EMPI (services/empi-service/)
# La imagen sale de ECR; las credenciales se inyectan desde SSM/Secrets (no en claro).
# El servicio se registra en dos balanceadores (perímetro por dirección, ADR-A3M-003):
#   - ALB privado + mTLS  -> sistemas internos (Admisión on-prem, Agenda)
#   - NLB (tras API GW+WAF) -> pacientes (público)
# =============================================================================
resource "aws_ecs_cluster" "empi" {
  name = "${local.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "empi" {
  cluster_name       = aws_ecs_cluster.empi.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

locals {
  rds_secret_arn = aws_db_instance.empi.master_user_secret[0].secret_arn
  container_name = "empi"
}

resource "aws_ecs_task_definition" "empi" {
  family                   = "${local.name_prefix}-empi"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.environment == "prod" ? "1024" : "512"
  memory                   = var.environment == "prod" ? "2048" : "1024"
  execution_role_arn       = local.ecs_execution_role_arn
  task_role_arn            = local.ecs_task_role_arn

  container_definitions = jsonencode([{
    name         = local.container_name
    image        = "${aws_ecr_repository.empi.repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 8000, protocol = "tcp" }]

    environment = [
      { name = "EMPI_ENVIRONMENT", value = var.environment },
      { name = "EMPI_MIGRATE", value = "true" }, # aplica el esquema al arranque (VPC)
      { name = "EMPI_BUS_BACKEND", value = "noop" },
    ]

    # Inyección segura: partes de conexión + umbrales desde SSM/Secrets.
    secrets = [
      { name = "EMPI_DB_HOST", valueFrom = aws_ssm_parameter.db_host.arn },
      { name = "EMPI_DB_PORT", valueFrom = aws_ssm_parameter.db_port.arn },
      { name = "EMPI_DB_NAME", valueFrom = aws_ssm_parameter.db_name.arn },
      { name = "EMPI_THRESHOLD_AUTO", valueFrom = aws_ssm_parameter.threshold_auto.arn },
      { name = "EMPI_THRESHOLD_REVIEW", valueFrom = aws_ssm_parameter.threshold_review.arn },
      { name = "EMPI_MODEL_VERSION", valueFrom = aws_ssm_parameter.model_version.arn },
      { name = "EMPI_DB_USER", valueFrom = "${local.rds_secret_arn}:username::" },
      { name = "EMPI_DB_PASSWORD", valueFrom = "${local.rds_secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.empi.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "empi"
      }
    }
  }])
}

resource "aws_ecs_service" "empi" {
  name            = "${local.name_prefix}-empi"
  cluster         = aws_ecs_cluster.empi.id
  task_definition = aws_ecs_task_definition.empi.arn
  desired_count   = var.environment == "prod" ? 2 : 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.network.private_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  # Entrada interna (ALB + mTLS)
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.container_name
    container_port   = 8000
  }

  # Entrada pública (NLB tras API GW + WAF)
  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = local.container_name
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.mtls, aws_lb_listener.api]
}
