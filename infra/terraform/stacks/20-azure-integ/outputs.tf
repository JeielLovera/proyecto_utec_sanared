output "resource_group_name" {
  value = azurerm_resource_group.empi.name
}

output "location" {
  value = azurerm_resource_group.empi.location
}

output "vnet_id" {
  description = "Consumido por 40-xcloud-net (VPN)."
  value       = azurerm_virtual_network.empi.id
}

output "vnet_name" {
  value = azurerm_virtual_network.empi.name
}

output "gateway_subnet_id" {
  description = "GatewaySubnet para el VPN Gateway (stack 40)."
  value       = azurerm_subnet.gateway.id
}

output "function_app_name" {
  value = azurerm_linux_function_app.adapter.name
}

output "hce_mock_ip" {
  description = "IP privada del HCE simulado."
  value       = azurerm_container_group.hce.ip_address
}

output "apim_gateway_url" {
  value = var.enable_apim ? azurerm_api_management.empi[0].gateway_url : null
}
