# =============================================================================
# Plano 4 (referencia) — SSM Parameter Store
# Ref: §5.2. Umbrales/precedencia configurables EN CALIENTE (RNF-06.2) + descubrimiento
# de infraestructura por la app/adaptadores (endpoints).
# =============================================================================

# --- match_config (umbrales del matcher, doc §5.2) ------------------------------
resource "aws_ssm_parameter" "threshold_auto" {
  name  = "/empi/${var.environment}/match/threshold_auto"
  type  = "String"
  value = "0.95"
  tags  = { component = "match-config" }
}

resource "aws_ssm_parameter" "threshold_review" {
  name  = "/empi/${var.environment}/match/threshold_review"
  type  = "String"
  value = "0.85"
  tags  = { component = "match-config" }
}

resource "aws_ssm_parameter" "model_version" {
  name  = "/empi/${var.environment}/match/model_version"
  type  = "String"
  value = "fs-2026.1"
  tags  = { component = "match-config" }
}

# --- descubrimiento de infraestructura (la app arma sus DSN desde aquí) ----------
resource "aws_ssm_parameter" "db_host" {
  name  = "/empi/${var.environment}/db/host"
  type  = "String"
  value = aws_db_instance.empi.address
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/empi/${var.environment}/db/port"
  type  = "String"
  value = tostring(aws_db_instance.empi.port)
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/empi/${var.environment}/db/name"
  type  = "String"
  value = aws_db_instance.empi.db_name
}

# ARN del secreto (usuario/clave) que AWS gestiona para RDS; la app lo resuelve en runtime.
resource "aws_ssm_parameter" "db_secret_arn" {
  name  = "/empi/${var.environment}/db/secret_arn"
  type  = "String"
  value = aws_db_instance.empi.master_user_secret[0].secret_arn
}

resource "aws_ssm_parameter" "redis_endpoint" {
  name  = "/empi/${var.environment}/redis/endpoint"
  type  = "String"
  value = aws_elasticache_replication_group.empi.primary_endpoint_address
}

resource "aws_ssm_parameter" "opensearch_endpoint" {
  count = var.enable_opensearch ? 1 : 0
  name  = "/empi/${var.environment}/opensearch/endpoint"
  type  = "String"
  value = aws_opensearch_domain.empi[0].endpoint
}
