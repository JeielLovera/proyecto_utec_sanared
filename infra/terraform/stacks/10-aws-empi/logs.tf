resource "aws_cloudwatch_log_group" "empi" {
  name              = "/ecs/${local.name_prefix}-empi"
  retention_in_days = var.environment == "prod" ? 90 : 14
}
