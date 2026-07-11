# =============================================================================
# NLB interno — front del servicio EMPI para el API Gateway público (VPC Link).
# El API Gateway REST integra por VPC Link contra un NLB (requisito de REST API v1).
# =============================================================================
resource "aws_lb" "api" {
  name               = "${local.name_prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.network.private_subnet_ids
  tags               = { Name = "${local.name_prefix}-nlb" }
}

resource "aws_lb_target_group" "api" {
  name        = "${local.name_prefix}-tg-api"
  port        = 8000
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = module.network.vpc_id

  health_check {
    protocol            = "HTTP"
    path                = "/health"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
