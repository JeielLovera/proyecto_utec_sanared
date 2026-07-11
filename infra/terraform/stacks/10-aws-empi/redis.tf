# =============================================================================
# Plano 3 (caché) — ElastiCache Redis
# Ref: §4.2. Lookup exacto (Paso 1) + anti-recálculo de scoring. DNI hasheado (SHA-256),
# nunca en claro. Cifrado en reposo (CMK) y en tránsito (TLS).
# =============================================================================
resource "aws_elasticache_subnet_group" "empi" {
  name       = "${local.name_prefix}-redis"
  subnet_ids = module.network.private_subnet_ids
}

resource "aws_elasticache_replication_group" "empi" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "EMPI cache: lookup DNI/ID + anti-recalculo (sec 4.2)"

  engine         = "redis"
  engine_version = "7.1"
  node_type      = local.this.redis_node_type
  port           = 6379

  num_cache_clusters         = local.this.redis_num_nodes
  automatic_failover_enabled = local.this.redis_auto_failover
  multi_az_enabled           = local.this.redis_auto_failover

  subnet_group_name  = aws_elasticache_subnet_group.empi.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.empi.arn
  transit_encryption_enabled = true

  parameter_group_name = "default.redis7"
  apply_immediately    = true

  tags = { Name = "${local.name_prefix}-redis" }
}
