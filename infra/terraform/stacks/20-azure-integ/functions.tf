# =============================================================================
# Adaptadores HL7 — Azure Functions (services/hl7-adapter/)
# Consume identity.patient.* del bus MSK (por la VPN) y emite ADT^A28/A40 al HCE
# (por APIM de salida). Plan Elastic Premium para permitir integración con la VNet.
# =============================================================================
resource "azurerm_service_plan" "func" {
  name                = "${local.name_prefix}-plan"
  resource_group_name = azurerm_resource_group.empi.name
  location            = azurerm_resource_group.empi.location
  os_type             = "Linux"
  sku_name            = var.environment == "prod" ? "EP2" : "EP1"
}

resource "azurerm_linux_function_app" "adapter" {
  name                = "${local.name_prefix}-hl7"
  resource_group_name = azurerm_resource_group.empi.name
  location            = azurerm_resource_group.empi.location
  service_plan_id     = azurerm_service_plan.func.id

  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key
  virtual_network_subnet_id  = azurerm_subnet.functions.id

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "python"
    # Bus MSK (AWS) alcanzable por la VPN (SASL/IAM). Las credenciales del consumidor
    # cross-cloud (AWS_ACCESS_KEY_ID/SECRET) deben ir a Key Vault; aquí solo el endpoint.
    "KAFKA_BOOTSTRAP" = var.kafka_bootstrap
    "KAFKA_TOPICS"    = "identity.patient.merged,identity.patient.created"
    "AWS_REGION"      = "us-east-1"
    # Destino de salida: APIM (si está habilitado) o directo al HCE simulado.
    "HCE_ENDPOINT" = var.enable_apim ? "${azurerm_api_management.empi[0].gateway_url}/hce" : "http://${azurerm_container_group.hce.ip_address}:8080"
  }

  tags = { domain = "empi-integration" }
}
