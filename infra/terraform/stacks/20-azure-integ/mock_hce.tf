# =============================================================================
# HCE simulado (legado AS-IS) — Azure Container Instance.
# Recibe el ADT^A28/A40 que emite el adaptador y lo refleja (echo) para evidencia.
# En prod NO se despliega: se apunta al HCE Oracle real por la VPN.
# =============================================================================
resource "azurerm_container_group" "hce" {
  name                = "${local.name_prefix}-hce-mock"
  location            = local.rg_location
  resource_group_name = local.rg_name
  os_type             = "Linux"
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.aci.id]

  container {
    name   = "hce-mock"
    image  = "mendhak/http-https-echo:31"
    cpu    = "0.5"
    memory = "1.0"

    ports {
      port     = 8080
      protocol = "TCP"
    }

    environment_variables = {
      HTTP_PORT = "8080"
    }
  }

  tags = { role = "legacy-mock", system = "HCE" }
}
