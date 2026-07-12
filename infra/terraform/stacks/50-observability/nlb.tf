# =============================================================================
# NLB interno — ingesta OTLP (4317 gRPC / 4318 HTTP). Mismo patrón que el NLB del
# bus Kafka self-hosted (10-aws-empi/kafka_selfhosted.tf): DNS estable para un
# Fargate que no tiene IP fija, alcanzable desde el EMPI y, via VPN cross-cloud,
# desde Azure/GCP.
# =============================================================================
resource "aws_lb" "otlp" {
  name               = "${local.name_prefix}-otlp-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = local.private_subnet_ids
  tags               = { Name = "${local.name_prefix}-otlp-nlb" }
}

resource "aws_lb_target_group" "otlp_grpc" {
  name        = "${local.name_prefix}-tg-otlp-grpc"
  port        = 4317
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = local.vpc_id
  health_check {
    protocol            = "TCP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "otlp_http" {
  name        = "${local.name_prefix}-tg-otlp-http"
  port        = 4318
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = local.vpc_id
  health_check {
    protocol            = "TCP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "otlp_grpc" {
  load_balancer_arn = aws_lb.otlp.arn
  port              = 4317
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.otlp_grpc.arn
  }
}

resource "aws_lb_listener" "otlp_http" {
  load_balancer_arn = aws_lb.otlp.arn
  port              = 4318
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.otlp_http.arn
  }
}

# =============================================================================
# NLB público — solo las UIs (Grafana, Jaeger), restringido por security group a
# admin_cidrs. Un NLB "internet-facing" puede apuntar a targets con IP privada en
# subredes privadas (el tráfico no sale de la VPC); por eso vive en las subredes
# públicas pero la tarea ECS sigue sin IP pública propia.
# =============================================================================
resource "aws_lb" "ui" {
  name               = "${local.name_prefix}-ui-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = local.public_subnet_ids
  tags               = { Name = "${local.name_prefix}-ui-nlb" }
}

resource "aws_lb_target_group" "grafana" {
  name        = "${local.name_prefix}-tg-grafana"
  port        = 3000
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = local.vpc_id
  health_check {
    protocol            = "TCP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "jaeger_ui" {
  name        = "${local.name_prefix}-tg-jaeger-ui"
  port        = 16686
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = local.vpc_id
  health_check {
    protocol            = "TCP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "grafana" {
  load_balancer_arn = aws_lb.ui.arn
  port              = 3000
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_lb_listener" "jaeger_ui" {
  load_balancer_arn = aws_lb.ui.arn
  port              = 16686
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jaeger_ui.arn
  }
}
