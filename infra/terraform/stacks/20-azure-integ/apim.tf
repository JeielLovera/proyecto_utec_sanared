# =============================================================================
# API Management — SALIDA del EMPI hacia legados (HCE/LIS/ERP), ADR-A3M-003.
# APIM es el único punto de egreso; NO recibe tráfico de entrada del EMPI. Inyectado
# en la VNet (modo Internal) para alcanzar los legados on-prem por la VPN.
# Recurso lento/caro: se puede desactivar con var.enable_apim=false en pruebas.
# =============================================================================
resource "azurerm_api_management" "empi" {
  count = var.enable_apim ? 1 : 0

  name                = "${local.name_prefix}-apim"
  location            = local.rg_location
  resource_group_name = local.rg_name
  publisher_name      = "SanaRed EMPI"
  publisher_email     = "empi@sanared.pe"
  sku_name            = "Developer_1"

  virtual_network_type = "Internal"
  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }
}

# API de fachada del HCE legado (destino del ADT que emite el adaptador).
resource "azurerm_api_management_api" "hce" {
  count = var.enable_apim ? 1 : 0

  name                = "hce"
  resource_group_name = local.rg_name
  api_management_name = azurerm_api_management.empi[0].name
  revision            = "1"
  display_name        = "HCE (legado)"
  path                = "hce"
  protocols           = ["https"]

  # Enruta al HCE simulado (en prod: al HCE Oracle on-prem por la VPN).
  service_url = "http://${azurerm_container_group.hce.ip_address}:8080"
}
