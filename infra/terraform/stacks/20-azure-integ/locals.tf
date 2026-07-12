locals {
  name_prefix = "${var.project}-${var.environment}"

  # Subredes de la VNet (10.30.0.0/16).
  subnet_functions = cidrsubnet(var.vnet_cidr, 8, 1)   # 10.30.1.0/24 (integración Functions)
  subnet_apim      = cidrsubnet(var.vnet_cidr, 8, 2)   # 10.30.2.0/24 (APIM interno)
  subnet_aci       = cidrsubnet(var.vnet_cidr, 8, 3)   # 10.30.3.0/24 (mock HCE)
  subnet_gateway   = cidrsubnet(var.vnet_cidr, 8, 254) # 10.30.254.0/24 (GatewaySubnet VPN)

  # Resource group: creado o reutilizado (ver create_resource_group, network.tf).
  rg_name     = var.create_resource_group ? azurerm_resource_group.empi[0].name : data.azurerm_resource_group.existing[0].name
  rg_location = var.create_resource_group ? azurerm_resource_group.empi[0].location : data.azurerm_resource_group.existing[0].location

  # Imagen del ACI consumidor HL7: placeholder público hasta el primer build/push real
  # (mismo patrón que consumer_image en 30-gcp-analytics/locals.tf). Sin esto, el primer
  # apply con enable_kafka_consumer=true fallaría por ImagePullFailure contra un ACR
  # recién creado (todavía sin la imagen real).
  hl7_consumer_image = var.hl7_consumer_image != "" ? var.hl7_consumer_image : "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
}
