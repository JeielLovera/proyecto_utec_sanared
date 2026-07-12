# =============================================================================
# Cliente mTLS de demo — Módulo de Admisión (por sede).
# Certificado firmado por la misma CA de demo del ALB privado (ver alb.tf:
# tls_private_key.ca / tls_self_signed_cert.ca). El ALB confía en cualquier
# certificado emitido por esa CA (trust store = aws_lb_trust_store.mtls), así
# que no hace falta tocar el ALB para dar de alta este cliente.
# En producción esto lo emite la PKI corporativa, no Terraform.
# =============================================================================

resource "tls_private_key" "client_admision" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client_admision" {
  private_key_pem = tls_private_key.client_admision.private_key_pem
  subject {
    common_name  = "admision-sede-demo.internal.sanared"
    organization = "SanaRed"
  }
}

resource "tls_locally_signed_cert" "client_admision" {
  cert_request_pem      = tls_cert_request.client_admision.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760
  allowed_uses          = ["client_auth", "digital_signature", "key_encipherment"]
}
