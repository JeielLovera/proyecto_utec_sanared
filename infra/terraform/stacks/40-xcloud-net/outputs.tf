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
