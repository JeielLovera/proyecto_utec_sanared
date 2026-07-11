output "vpc_id" {
  description = "ID de la VPC del EMPI (consumido por 40-xcloud-net)."
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  value = var.vpc_cidr
}

output "private_subnet_ids" {
  description = "Subredes privadas (RDS, Redis, OpenSearch, MSK, ECS)."
  value       = module.network.private_subnet_ids
}

output "private_route_table_ids" {
  description = "Route tables privadas (para propagación de rutas de la VPN cross-cloud)."
  value       = module.network.private_route_table_ids
}

output "public_subnet_ids" {
  description = "Subredes públicas (edge: ALB/API GW público)."
  value       = module.network.public_subnet_ids
}

output "kms_key_arn" {
  description = "CMK del plano de datos EMPI."
  value       = aws_kms_key.empi.arn
}

output "rds_endpoint" {
  description = "Endpoint del Event Store + proyecciones."
  value       = aws_db_instance.empi.address
}

output "rds_secret_arn" {
  description = "Secreto (Secrets Manager) con la credencial maestra de RDS."
  value       = aws_db_instance.empi.master_user_secret[0].secret_arn
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.empi.primary_endpoint_address
}

output "opensearch_endpoint" {
  value = var.enable_opensearch ? aws_opensearch_domain.empi[0].endpoint : null
}

output "app_security_group_id" {
  description = "SG de las tareas ECS del servicio EMPI (reutilizado en cómputo)."
  value       = aws_security_group.app.id
}

output "bus_cluster_arn" {
  description = "ARN del cluster MSK Serverless (bus de eventos)."
  value       = var.enable_msk ? aws_msk_serverless_cluster.bus[0].arn : null
}

output "ecr_repository_url" {
  description = "Destino del push de la imagen del servicio EMPI."
  value       = aws_ecr_repository.empi.repository_url
}

output "internal_alb_dns" {
  description = "DNS del ALB privado + mTLS (entrada de sistemas internos)."
  value       = aws_lb.internal.dns_name
}

output "patient_api_url" {
  description = "URL pública del paciente (API Gateway + WAF)."
  value       = aws_api_gateway_stage.public.invoke_url
}

output "ecs_cluster" {
  value = aws_ecs_cluster.empi.name
}
