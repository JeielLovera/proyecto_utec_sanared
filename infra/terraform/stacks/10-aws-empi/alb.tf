# =============================================================================
# Edge INTERNO — ALB privado + mTLS (entrada de sistemas internos, ADR-A3M-003)
# Admisión on-prem / Agenda llegan por Direct Connect/VPN y presentan certificado
# cliente. mTLS en modo "verify" contra una CA propia (demo: CA autofirmada generada
# con el provider tls; en prod se usa la PKI corporativa).
# =============================================================================

# --- PKI de demo: CA + certificado de servidor -------------------------------
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 8760
  allowed_uses          = ["cert_signing", "crl_signing", "digital_signature"]
  subject {
    common_name  = "SanaRed EMPI Internal CA"
    organization = "SanaRed"
  }
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem
  dns_names       = ["empi.internal.sanared"]
  subject {
    common_name  = "empi.internal.sanared"
    organization = "SanaRed"
  }
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem      = tls_cert_request.server.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

resource "aws_acm_certificate" "server" {
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem
  tags              = { Name = "${local.name_prefix}-server-cert" }
}

# --- Trust store del ALB (CA que valida los certificados cliente) ------------
resource "aws_s3_bucket" "edge" {
  bucket = "${local.name_prefix}-edge-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "edge" {
  bucket                  = aws_s3_bucket.edge.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "ca_bundle" {
  bucket  = aws_s3_bucket.edge.id
  key     = "mtls/ca.pem"
  content = tls_self_signed_cert.ca.cert_pem
}

resource "aws_lb_trust_store" "mtls" {
  name                             = "${local.name_prefix}-ts"
  ca_certificates_bundle_s3_bucket = aws_s3_bucket.edge.id
  ca_certificates_bundle_s3_key    = aws_s3_object.ca_bundle.key
}

# --- Security group del ALB --------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "ALB privado (mTLS) para sistemas internos"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "HTTPS/mTLS desde sistemas internos (DX/VPN)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.internal_client_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb" }
}

# La app admite tráfico del ALB (y del NLB, vía CIDR de la VPC) en el puerto 8000.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
  description                  = "App desde ALB privado"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_vpc" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8000
  to_port           = 8000
  ip_protocol       = "tcp"
  description       = "App desde NLB (targets IP en la VPC)"
}

# --- ALB + target group + listener mTLS --------------------------------------
resource "aws_lb" "internal" {
  name               = "${local.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = module.network.private_subnet_ids
  security_groups    = [aws_security_group.alb.id]
  tags               = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip" # Fargate awsvpc
  vpc_id      = module.network.vpc_id

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "mtls" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.server.arn

  mutual_authentication {
    mode            = "verify"
    trust_store_arn = aws_lb_trust_store.mtls.arn
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
