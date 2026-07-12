output "resource_group_name" {
  value = local.rg_name
}

output "location" {
  value = local.rg_location
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
  value = var.enable_function_app ? azurerm_linux_function_app.adapter[0].name : null
}

output "hce_mock_ip" {
  description = "IP privada del HCE simulado."
  value       = azurerm_container_group.hce.ip_address
}

output "hce_mock_container_name" {
  description = "Nombre del ACI del HCE simulado (para `az container logs`, evidencia ADT^A40, Fase 4)."
  value       = azurerm_container_group.hce.name
}

output "apim_gateway_url" {
  value = var.enable_apim ? azurerm_api_management.empi[0].gateway_url : null
}

output "acr_login_server" {
  description = "Registro del consumidor HL7 (docker build/push + az acr login)."
  value       = var.enable_kafka_consumer ? azurerm_container_registry.empi[0].login_server : null
}

output "hl7_consumer_name" {
  value = var.enable_kafka_consumer ? azurerm_container_group.hl7_consumer[0].name : null
}
