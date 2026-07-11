# =============================================================================
# Plano 3 (índice) — OpenSearch: blocking difuso del matcher (Paso 2, producción)
# Ref: §4.1, ADR-A3M-011. Índice golden-record-idx (ver
# entregables_hito3/07_Scripts_Modelo_Datos/opensearch/golden-record-idx.mapping.json).
# Dominio dentro de la VPC (subredes privadas); cifrado en reposo (CMK) y node-to-node.
# =============================================================================
resource "aws_opensearch_domain" "empi" {
  domain_name    = "${var.project}-${var.environment}-idx"
  engine_version = "OpenSearch_2.13"

  cluster_config {
    instance_type          = local.this.opensearch_instance
    instance_count         = local.this.opensearch_instances
    zone_awareness_enabled = local.this.opensearch_zone_aware

    dynamic "zone_awareness_config" {
      for_each = local.this.opensearch_zone_aware ? [1] : []
      content {
        availability_zone_count = 2
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  vpc_options {
    # 1 subred en demo (single-AZ); 2 en prod (zone awareness).
    subnet_ids         = slice(module.network.private_subnet_ids, 0, local.this.opensearch_instances)
    security_group_ids = [aws_security_group.opensearch.id]
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.empi.key_id
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Seguridad efectiva por VPC + SG. Política restringida a la cuenta.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "es:*"
      Resource  = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.project}-${var.environment}-idx/*"
    }]
  })

  tags = { Name = "${local.name_prefix}-idx" }
}
