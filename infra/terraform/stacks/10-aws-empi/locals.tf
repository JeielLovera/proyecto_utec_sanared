locals {
  name_prefix = "${var.project}-${var.environment}"

  # Perfiles demo vs prod (concordancia con doc §12: misma topología, distinto motor/tamaño).
  profile = {
    demo = {
      single_nat_gateway    = true # 1 NAT (ahorro)
      rds_instance_class    = "db.t4g.micro"
      rds_multi_az          = false
      redis_node_type       = "cache.t4g.micro"
      redis_num_nodes       = 1
      redis_auto_failover   = false
      opensearch_instance   = "t3.small.search"
      opensearch_instances  = 1
      opensearch_zone_aware = false
    }
    prod = {
      single_nat_gateway    = false # 1 NAT por AZ (HA)
      rds_instance_class    = "db.r6g.large"
      rds_multi_az          = true
      redis_node_type       = "cache.r6g.large"
      redis_num_nodes       = 2
      redis_auto_failover   = true
      opensearch_instance   = "r6g.large.search"
      opensearch_instances  = 2
      opensearch_zone_aware = true
    }
  }

  this = local.profile[var.environment]

  # Modo del bus: gestionado (MSK Serverless) vs self-hosted (Redpanda en ECS, cuentas
  # que bloquean kafka:CreateClusterV2, p. ej. Learner Lab). Mutuamente excluyentes.
  use_kafka_managed    = var.enable_msk && !var.use_self_hosted_kafka
  use_kafka_selfhosted = var.enable_msk && var.use_self_hosted_kafka

  # ARN del parámetro SSM con el bootstrap del bus, sea cual sea el modo activo.
  bus_bootstrap_ssm_arn = (
    local.use_kafka_managed ? try(aws_ssm_parameter.bus_bootstrap[0].arn, null) :
    local.use_kafka_selfhosted ? try(aws_ssm_parameter.bus_bootstrap_selfhosted[0].arn, null) :
    null
  )
}
