# =============================================================================
# Bus de eventos — Amazon MSK Serverless (Kafka gestionado, disponibilizado desde AWS)
# Ref: doc §6 y ADR-A3M-008. Productor junto al EMPI (AWS); consumido cross-cloud por
# Azure/GCP vía VPN privada (stack 40-xcloud-net). Autenticación SASL/IAM.
#
# Activo solo si use_self_hosted_kafka=false (default). En cuentas que bloquean
# kafka:CreateClusterV2 (p. ej. AWS Academy Learner Lab) usa use_self_hosted_kafka=true
# -> ver kafka_selfhosted.tf (Redpanda en ECS Fargate, mismo protocolo, sin tocar la app).
#
# Nota: los topics identity.patient.{created,updated,merged,deactivated} los crea el
#       propio servicio EMPI al arrancar (MSK Serverless no gestiona topics vía Terraform).
#       El contrato de mensaje está en 07_Scripts_Modelo_Datos/schemas/bus/.
# =============================================================================
resource "aws_security_group" "msk" {
  count       = local.use_kafka_managed ? 1 : 0
  name        = "${local.name_prefix}-msk"
  description = "MSK Serverless (bus de eventos)"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "Kafka SASL/IAM desde la app"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # Ingreso desde las otras nubes (rango de la VPN cross-cloud). Se afina en 40-xcloud-net.
  ingress {
    description = "Kafka SASL/IAM desde consumidores cross-cloud (Azure/GCP via VPN)"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = ["10.30.0.0/16", "10.40.0.0/16"] # Azure VNet / GCP VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-msk" }
}

resource "aws_msk_serverless_cluster" "bus" {
  count        = local.use_kafka_managed ? 1 : 0
  cluster_name = "${local.name_prefix}-bus"

  vpc_config {
    subnet_ids         = module.network.private_subnet_ids
    security_group_ids = [aws_security_group.msk[0].id]
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  tags = { Name = "${local.name_prefix}-bus" }
}

# El bootstrap server de un cluster serverless se resuelve por ARN
# (aws kafka get-bootstrap-brokers --cluster-arn ...). La app lo descubre desde SSM.
resource "aws_ssm_parameter" "bus_cluster_arn" {
  count = local.use_kafka_managed ? 1 : 0
  name  = "/empi/${var.environment}/bus/cluster_arn"
  type  = "String"
  value = aws_msk_serverless_cluster.bus[0].arn
}

# Bootstrap real (SASL/IAM) que consumen el servicio EMPI (productor) y los consumidores
# cross-cloud (Azure/GCP, vía sus propias credenciales AWS — ver iam_kafka_cross_cloud.tf).
data "aws_msk_bootstrap_brokers" "bus" {
  count       = local.use_kafka_managed ? 1 : 0
  cluster_arn = aws_msk_serverless_cluster.bus[0].arn
}

resource "aws_ssm_parameter" "bus_bootstrap" {
  count = local.use_kafka_managed ? 1 : 0
  name  = "/empi/${var.environment}/bus/bootstrap"
  type  = "String"
  value = data.aws_msk_bootstrap_brokers.bus[0].bootstrap_brokers_sasl_iam
}
