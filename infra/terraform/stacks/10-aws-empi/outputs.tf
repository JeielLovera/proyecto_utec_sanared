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
  description = "ARN del cluster MSK Serverless (null si use_self_hosted_kafka=true o enable_msk=false)."
  value       = local.use_kafka_managed ? aws_msk_serverless_cluster.bus[0].arn : null
}

output "kafka_bootstrap" {
  description = "Bootstrap del bus (host:port). MSK real (SASL/IAM) o Redpanda self-hosted (plaintext) según use_self_hosted_kafka. null si enable_msk=false."
  value = (
    local.use_kafka_managed ? data.aws_msk_bootstrap_brokers.bus[0].bootstrap_brokers_sasl_iam :
    local.use_kafka_selfhosted ? "${aws_lb.kafka[0].dns_name}:9092" :
    null
  )
}

output "kafka_auth_mode" {
  description = "Modo de autenticación del bus: iam (MSK real) | plaintext (Redpanda self-hosted) | null (bus deshabilitado)."
  value = (
    local.use_kafka_managed ? "iam" :
    local.use_kafka_selfhosted ? "plaintext" :
    null
  )
}

output "kafka_xcloud_access_key_id" {
  description = "Access key del usuario IAM de solo-consumo del bus MSK. null si create_iam_roles=false o use_self_hosted_kafka=true (Redpanda no usa IAM: usa el kafka_bootstrap directo, sin credencial)."
  value       = var.create_iam_roles && local.use_kafka_managed ? aws_iam_access_key.kafka_cross_cloud[0].id : null
}

output "kafka_xcloud_secret_access_key" {
  description = "Secret de la access key anterior. Ver nota de kafka_xcloud_access_key_id."
  value       = var.create_iam_roles && local.use_kafka_managed ? aws_iam_access_key.kafka_cross_cloud[0].secret : null
  sensitive   = true
}

output "ecr_repository_url" {
  description = "Destino del push de la imagen del servicio EMPI."
  value       = aws_ecr_repository.empi.repository_url
}

output "internal_alb_dns" {
  description = "DNS del ALB privado + mTLS (entrada de sistemas internos)."
  value       = aws_lb.internal.dns_name
}

output "mtls_ca_cert_pem" {
  description = "Certificado de la CA de demo (para validar el server cert del ALB en el probe mTLS)."
  value       = tls_self_signed_cert.ca.cert_pem
}

output "mtls_admision_client_cert_pem" {
  description = "Certificado cliente de demo (Módulo de Admisión) firmado por la CA del ALB privado."
  value       = tls_locally_signed_cert.client_admision.cert_pem
  sensitive   = true
}

output "mtls_admision_client_key_pem" {
  description = "Clave privada del certificado cliente de demo. Solo para el probe mTLS del ALB interno (no usar fuera del lab)."
  value       = tls_private_key.client_admision.private_key_pem
  sensitive   = true
}

output "patient_api_url" {
  description = "URL pública del paciente (API Gateway + WAF)."
  value       = aws_api_gateway_stage.public.invoke_url
}

output "ecs_cluster" {
  value = aws_ecs_cluster.empi.name
}

output "ecs_service" {
  description = "Nombre del servicio ECS del EMPI (el cluster también aloja el bus self-hosted; hay que filtrar por servicio al listar tareas)."
  value       = aws_ecs_service.empi.name
}
