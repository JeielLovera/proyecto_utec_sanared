# =============================================================================
# VPN IPSec site-to-site AWS <-> Azure (conectividad privada del bus cross-cloud, §6).
# PrivateLink/PSC son intra-nube; el salto ENTRE nubes es este túnel. Los consumidores
# Azure (adaptadores HL7) alcanzan el bus MSK por aquí.
# =============================================================================
locals {
  aws_vpc_id      = data.terraform_remote_state.aws.outputs.vpc_id
  aws_vpc_cidr    = data.terraform_remote_state.aws.outputs.vpc_cidr
  aws_private_rts = data.terraform_remote_state.aws.outputs.private_route_table_ids
  az_rg           = data.terraform_remote_state.azure.outputs.resource_group_name
  az_location     = data.terraform_remote_state.azure.outputs.location
  az_gw_subnet_id = data.terraform_remote_state.azure.outputs.gateway_subnet_id
}

# ---------------------------------------------------------------------------
# Azure — VPN Gateway
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "vpn" {
  name                = "${var.project}-${var.environment}-vpngw-pip"
  resource_group_name = local.az_rg
  location            = local.az_location
  allocation_method   = "Static"
  sku                 = "Standard"
  # Los SKUs *AZ del VPN Gateway exigen una IP publica zonal (no zone-redundant por defecto).
  zones               = ["1", "2", "3"]
}

resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "${var.project}-${var.environment}-vpngw"
  resource_group_name = local.az_rg
  location            = local.az_location
  type                = "Vpn"
  vpn_type            = "RouteBased"
  # Azure descontinuó los SKUs no-AZ (VpnGw1-5) para gateways nuevos desde 2024;
  # solo se aceptan los *AZ (zonales), ver NonAzSkusNotAllowedForVPNGateway.
  sku                 = "VpnGw1AZ"
  active_active       = false
  enable_bgp          = false

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = local.az_gw_subnet_id
  }
}

# ---------------------------------------------------------------------------
# AWS — VPN Gateway + Customer Gateway (apunta a la IP pública de Azure) + conexión
# ---------------------------------------------------------------------------
resource "aws_vpn_gateway" "vgw" {
  vpc_id = local.aws_vpc_id
  tags   = { Name = "${var.project}-${var.environment}-vgw" }
}

resource "aws_customer_gateway" "azure" {
  bgp_asn    = 65000
  ip_address = azurerm_public_ip.vpn.ip_address
  type       = "ipsec.1"
  tags       = { Name = "${var.project}-${var.environment}-cgw-azure" }
}

resource "aws_vpn_connection" "to_azure" {
  vpn_gateway_id        = aws_vpn_gateway.vgw.id
  customer_gateway_id   = aws_customer_gateway.azure.id
  type                  = "ipsec.1"
  static_routes_only    = true
  tunnel1_preshared_key = var.shared_key
  tags                  = { Name = "${var.project}-${var.environment}-vpn-azure" }
}

# Ruta estática hacia la VNet de Azure y propagación a las route tables privadas.
resource "aws_vpn_connection_route" "azure" {
  destination_cidr_block = var.azure_vnet_cidr
  vpn_connection_id      = aws_vpn_connection.to_azure.id
}

resource "aws_vpn_gateway_route_propagation" "private" {
  count          = length(local.aws_private_rts)
  vpn_gateway_id = aws_vpn_gateway.vgw.id
  route_table_id = local.aws_private_rts[count.index]
}

# ---------------------------------------------------------------------------
# Azure — Local Network Gateway (representa AWS) + conexión IPSec
# ---------------------------------------------------------------------------
resource "azurerm_local_network_gateway" "aws" {
  name                = "${var.project}-${var.environment}-lng-aws"
  resource_group_name = local.az_rg
  location            = local.az_location
  gateway_address     = aws_vpn_connection.to_azure.tunnel1_address
  address_space       = [local.aws_vpc_cidr]
}

resource "azurerm_virtual_network_gateway_connection" "to_aws" {
  name                       = "${var.project}-${var.environment}-cx-aws"
  resource_group_name        = local.az_rg
  location                   = local.az_location
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.aws.id
  shared_key                 = var.shared_key
}
