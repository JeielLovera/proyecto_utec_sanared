# =============================================================================
# Bus de eventos — Amazon MSK Serverless (Kafka gestionado, disponibilizado desde AWS)
# Ref: doc §6 y ADR-A3M-008. Productor junto al EMPI (AWS); consumido cross-cloud por
# Azure/GCP vía VPN privada (stack 40-xcloud-net). Autenticación SASL/IAM.
# Nota: los topics identity.patient.{created,updated,merged,deactivated} los crea el
#       servicio EMPI / un job de admin al arranque (MSK Serverless no gestiona topics
#       vía Terraform). El contrato de mensaje está en 07_Scripts_Modelo_Datos/schemas/bus/.
# =============================================================================
resource "aws_security_group" "msk" {
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
    description = "Kafka SASL/IAM desde consumidores cross-cloud (Azure/GCP vía VPN)"
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
  cluster_name = "${local.name_prefix}-bus"

  vpc_config {
    subnet_ids         = module.network.private_subnet_ids
    security_group_ids = [aws_security_group.msk.id]
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
  name  = "/empi/${var.environment}/bus/cluster_arn"
  type  = "String"
  value = aws_msk_serverless_cluster.bus.arn
}
