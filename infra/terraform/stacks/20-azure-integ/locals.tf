locals {
  name_prefix = "${var.project}-${var.environment}"

  # Subredes de la VNet (10.30.0.0/16).
  subnet_functions = cidrsubnet(var.vnet_cidr, 8, 1)   # 10.30.1.0/24 (integración Functions)
  subnet_apim      = cidrsubnet(var.vnet_cidr, 8, 2)   # 10.30.2.0/24 (APIM interno)
  subnet_aci       = cidrsubnet(var.vnet_cidr, 8, 3)   # 10.30.3.0/24 (mock HCE)
  subnet_gateway   = cidrsubnet(var.vnet_cidr, 8, 254) # 10.30.254.0/24 (GatewaySubnet VPN)
}
