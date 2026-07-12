# =============================================================================
# Red Azure — VNet de integración clínica/financiera (ADR-A3M-001).
# Subredes: Functions (integración), APIM (interno), ACI (mock HCE), GatewaySubnet (VPN).
#
# Resource Group: por defecto se crea uno nuevo. En suscripciones académicas/tenant
# restringido (p. ej. sin permiso Microsoft.Resources/subscriptions/resourcegroups/write
# a nivel de suscripción, solo Contributor sobre un RG ya asignado) usa
# create_resource_group=false + existing_resource_group_name.
# =============================================================================
resource "azurerm_resource_group" "empi" {
  count    = var.create_resource_group ? 1 : 0
  name     = "${local.name_prefix}-integ"
  location = var.location
  tags     = { project = var.project, environment = var.environment, domain = "empi-integration" }
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.existing_resource_group_name
}

resource "azurerm_virtual_network" "empi" {
  name                = "${local.name_prefix}-vnet"
  location            = local.rg_location
  resource_group_name = local.rg_name
  address_space       = [var.vnet_cidr]
}

# Integración regional de la Function App (salida hacia el bus/HCE por la VNet/VPN).
resource "azurerm_subnet" "functions" {
  name                 = "snet-functions"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.empi.name
  address_prefixes     = [local.subnet_functions]

  delegation {
    name = "webserverfarms"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "apim" {
  name                 = "snet-apim"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.empi.name
  address_prefixes     = [local.subnet_apim]
}

resource "azurerm_subnet" "aci" {
  name                 = "snet-aci"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.empi.name
  address_prefixes     = [local.subnet_aci]

  delegation {
    name = "aci"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# GatewaySubnet (nombre EXACTO exigido por Azure) — la usa el VPN Gateway del stack 40.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.empi.name
  address_prefixes     = [local.subnet_gateway]
}
