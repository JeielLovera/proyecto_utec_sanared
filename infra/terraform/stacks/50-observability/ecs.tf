# =============================================================================
# Jaeger (recolector OTLP + almacenamiento + UI) y Grafana (UI encima de Jaeger)
# en una sola tarea Fargate — mismo ENI, Grafana llega a Jaeger por localhost.
# Almacenamiento de Jaeger en memoria (perfil demo: se pierde en cada redeploy,
# igual de "MVP-able" que el resto del perfil demo del EMPI — ver 10-aws-empi/
# locals.tf perfil demo vs prod).
# =============================================================================
resource "aws_ecs_cluster" "observability" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "observability" {
  cluster_name       = aws_ecs_cluster.observability.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

resource "aws_cloudwatch_log_group" "observability" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "observability" {
  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = local.ecs_execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "jaeger"
      image     = var.jaeger_image
      essential = true
      portMappings = [
        { containerPort = 16686, protocol = "tcp" }, # UI + query API (datasource de Grafana)
        { containerPort = 4317, protocol = "tcp" },  # OTLP gRPC
        { containerPort = 4318, protocol = "tcp" },  # OTLP HTTP
      ]
      environment = [
        { name = "COLLECTOR_OTLP_ENABLED", value = "true" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.observability.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "jaeger"
        }
      }
    },
    {
      name      = "grafana"
      image     = var.grafana_image
      essential = true
      portMappings = [
        { containerPort = 3000, protocol = "tcp" },
      ]
      environment = [
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = var.grafana_admin_password },
        { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },
      ]
      # Provisiona el datasource de Jaeger antes de arrancar (sin imagen custom):
      # escribe el YAML de provisioning y luego invoca el entrypoint oficial de la
      # imagen (/run.sh). Grafana llega a Jaeger por localhost (misma tarea/ENI).
      # OJO: la imagen de Grafana ya trae ENTRYPOINT=["/run.sh"] -- hay que
      # sobreescribir entryPoint (no command), o Docker corre "/run.sh <command>"
      # y el script de provisioning nunca se ejecuta (se pasa como argv ignorado).
      entryPoint = ["sh", "-c"]
      command = [
        "mkdir -p /etc/grafana/provisioning/datasources && cat > /etc/grafana/provisioning/datasources/jaeger.yaml <<'EOF'\napiVersion: 1\ndatasources:\n  - name: Jaeger\n    type: jaeger\n    access: proxy\n    url: http://localhost:16686\n    isDefault: true\n    editable: true\nEOF\nexec /run.sh"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.observability.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "observability" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.observability.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.otel.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.otlp_grpc.arn
    container_name   = "jaeger"
    container_port   = 4317
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.otlp_http.arn
    container_name   = "jaeger"
    container_port   = 4318
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.jaeger_ui.arn
    container_name   = "jaeger"
    container_port   = 16686
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener.otlp_grpc,
    aws_lb_listener.otlp_http,
    aws_lb_listener.jaeger_ui,
    aws_lb_listener.grafana,
  ]
}
