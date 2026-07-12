# =============================================================================
# Security group de la tarea Jaeger+Grafana.
#   - OTLP (4317 gRPC / 4318 HTTP): interno — VPC del EMPI + Azure/GCP (cross-cloud
#     via VPN de 40-xcloud-net), igual que el bus Kafka self-hosted en 10-aws-empi.
#   - Grafana (3000) / Jaeger UI (16686): público, restringido a admin_cidrs.
#   - Los health checks de un NLB llegan desde direcciones dentro de la propia VPC
#     (visto también en kafka_selfhosted.tf), por eso vpc_cidr se agrega a ambos.
# =============================================================================
resource "aws_security_group" "otel" {
  name        = "${local.name_prefix}-otel"
  description = "Jaeger (OTLP + UI) y Grafana"
  vpc_id      = local.vpc_id

  ingress {
    description = "OTLP gRPC desde la VPC del EMPI"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }
  ingress {
    description = "OTLP HTTP desde la VPC del EMPI"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }
  ingress {
    description = "OTLP gRPC desde consumidores cross-cloud (Azure/GCP via VPN)"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = [var.azure_vnet_cidr, var.gcp_vpc_cidr]
  }
  ingress {
    description = "OTLP HTTP desde consumidores cross-cloud (Azure/GCP via VPN)"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = [var.azure_vnet_cidr, var.gcp_vpc_cidr]
  }

  ingress {
    description = "Grafana UI (admin)"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = concat(local.admin_cidrs, [local.vpc_cidr])
  }
  ingress {
    description = "Jaeger UI (admin)"
    from_port   = 16686
    to_port     = 16686
    protocol    = "tcp"
    cidr_blocks = concat(local.admin_cidrs, [local.vpc_cidr])
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-otel" }
}
