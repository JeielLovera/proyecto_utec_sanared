output "azure_vpngw_public_ip" {
  value = azurerm_public_ip.vpn.ip_address
}

output "aws_vpn_tunnel1_address" {
  value = aws_vpn_connection.to_azure.tunnel1_address
}

output "aws_vpn_tunnel1_status" {
  description = "Estado del túnel (UP tras el handshake IPSec)."
  value       = aws_vpn_connection.to_azure.tunnel1_vgw_inside_address
}

output "gcp_vpn_static_ip" {
  value = google_compute_address.vpn.address
}

output "aws_vpn_gcp_tunnel1_address" {
  value = aws_vpn_connection.to_gcp.tunnel1_address
}

# ---------------------------------------------------------------------------
# Credenciales cross-cloud del bus (consolidadas aquí para que el operador las
# copie UNA vez a los tfvars de 20-azure-integ / 30-gcp-analytics). No hay un
# broker de secretos compartido entre las 3 nubes en este perfil; ver
# DEPLOYMENT.demo.md / DEPLOYMENT.prod.md §7 para el flujo manual de distribución.
# ---------------------------------------------------------------------------
output "kafka_bootstrap" {
  description = "Pega en kafka_bootstrap de 20-azure-integ y 30-gcp-analytics."
  value       = data.terraform_remote_state.aws.outputs.kafka_bootstrap
}

output "kafka_auth_mode" {
  description = "iam (MSK real, necesita credencial) | plaintext (Redpanda self-hosted, NO necesita credencial AWS)."
  value       = data.terraform_remote_state.aws.outputs.kafka_auth_mode
}

output "kafka_xcloud_access_key_id" {
  description = "Pega en aws_access_key_id de 20-azure-integ y 30-gcp-analytics. null si kafka_auth_mode=plaintext (self-hosted, no hace falta) o si 10-aws-empi usa create_iam_roles=false con MSK (usa credenciales temporales de tu sesión, ver DEPLOYMENT.demo.md §7)."
  # Terraform omite del state los outputs con valor null (ver 10-aws-empi/outputs.tf) ->
  # try() evita "Unsupported attribute" cuando el stack de origen no lo tiene.
  value = try(data.terraform_remote_state.aws.outputs.kafka_xcloud_access_key_id, null)
}

output "kafka_xcloud_secret_access_key" {
  description = "Pega en aws_secret_access_key de 20-azure-integ y 30-gcp-analytics. null si create_iam_roles=false (ver nota arriba)."
  value       = try(data.terraform_remote_state.aws.outputs.kafka_xcloud_secret_access_key, null)
  sensitive   = true
}
