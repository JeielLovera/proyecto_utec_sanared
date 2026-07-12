# =============================================================================
# Bus self-hosted (Redpanda en ECS Fargate) — sustituye a MSK Serverless en cuentas
# que bloquean kafka:CreateClusterV2 (p. ej. AWS Academy Learner Lab). Mismo protocolo
# Kafka; el broker es reemplazable sin tocar el código de la app (ADR-A3M-008, doc §6).
# Sin autenticación IAM: el perímetro lo da el security group (solo la app y el rango
# de la VPN cross-cloud alcanzan el puerto 9092) — razonable en perfil demo/lab.
# Activo solo si use_self_hosted_kafka=true.
# =============================================================================
resource "aws_security_group" "redpanda" {
  count       = local.use_kafka_selfhosted ? 1 : 0
  name        = "${local.name_prefix}-redpanda"
  description = "Bus self-hosted Redpanda (sustituto de MSK en cuentas restringidas)"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "Kafka desde la app"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # El health check del NLB llega desde la propia IP del NLB dentro de la VPC (no desde
  # el SG de la app) — sin esta regla el target queda "unhealthy" aunque Redpanda esté
  # arriba y escuchando (visto en un despliegue real: broker OK, NLB nunca lo marcaba sano).
  ingress {
    description = "Health check del NLB interno (origen: la propia VPC)"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Kafka desde consumidores cross-cloud (Azure/GCP via VPN)"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["10.30.0.0/16", "10.40.0.0/16"] # Azure VNet / GCP VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-redpanda" }
}

resource "aws_cloudwatch_log_group" "redpanda" {
  count             = local.use_kafka_selfhosted ? 1 : 0
  name              = "/ecs/${local.name_prefix}-redpanda"
  retention_in_days = 14
}

# NLB interno: da un nombre DNS estable al broker (Fargate no tiene IP fija).
resource "aws_lb" "kafka" {
  count              = local.use_kafka_selfhosted ? 1 : 0
  name               = "${local.name_prefix}-kafka-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.network.private_subnet_ids
  tags               = { Name = "${local.name_prefix}-kafka-nlb" }
}

resource "aws_lb_target_group" "kafka" {
  count       = local.use_kafka_selfhosted ? 1 : 0
  name        = "${local.name_prefix}-tg-kafka"
  port        = 9092
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = module.network.vpc_id

  health_check {
    protocol            = "TCP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "kafka" {
  count             = local.use_kafka_selfhosted ? 1 : 0
  load_balancer_arn = aws_lb.kafka[0].arn
  port              = 9092
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka[0].arn
  }
}

resource "aws_ecs_task_definition" "redpanda" {
  count                    = local.use_kafka_selfhosted ? 1 : 0
  family                   = "${local.name_prefix}-redpanda"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = local.ecs_execution_role_arn
  task_role_arn            = local.ecs_task_role_arn

  container_definitions = jsonencode([{
    name         = "redpanda"
    image        = "docker.redpanda.com/redpandadata/redpanda:v24.2.4"
    essential    = true
    portMappings = [{ containerPort = 9092, protocol = "tcp" }]
    # El bootstrap anunciado es el DNS del NLB (estable aunque la tarea se recree).
    command = [
      "redpanda", "start",
      "--smp", "1", "--memory", "768M", "--overprovisioned",
      "--node-id", "0", "--check=false",
      "--kafka-addr", "PLAINTEXT://0.0.0.0:9092",
      "--advertise-kafka-addr", "PLAINTEXT://${aws_lb.kafka[0].dns_name}:9092",
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.redpanda[0].name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "redpanda"
      }
    }
  }])
}

resource "aws_ecs_service" "redpanda" {
  count           = local.use_kafka_selfhosted ? 1 : 0
  name            = "${local.name_prefix}-redpanda"
  cluster         = aws_ecs_cluster.empi.id
  task_definition = aws_ecs_task_definition.redpanda[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.network.private_subnet_ids
    security_groups  = [aws_security_group.redpanda[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kafka[0].arn
    container_name   = "redpanda"
    container_port   = 9092
  }

  depends_on = [aws_lb_listener.kafka]
}

resource "aws_ssm_parameter" "bus_bootstrap_selfhosted" {
  count = local.use_kafka_selfhosted ? 1 : 0
  name  = "/empi/${var.environment}/bus/bootstrap"
  type  = "String"
  value = "${aws_lb.kafka[0].dns_name}:9092"
}
