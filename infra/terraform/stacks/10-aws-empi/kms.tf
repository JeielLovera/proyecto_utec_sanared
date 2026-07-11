# Cifrado en reposo de todo el plano de datos del EMPI (RNF-03, Ley 29733, doc §10).
# Una CMK con rotación anual cubre RDS, OpenSearch, ElastiCache, Secrets y SSM SecureString.
resource "aws_kms_key" "empi" {
  description             = "${local.name_prefix} — CMK del plano de datos EMPI (PII)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "empi" {
  name          = "alias/${local.name_prefix}-empi"
  target_key_id = aws_kms_key.empi.key_id
}
