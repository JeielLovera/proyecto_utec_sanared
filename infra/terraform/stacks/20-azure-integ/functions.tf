# =============================================================================
# Adaptadores HL7 — Azure Functions (services/hl7-adapter/)
# Consume identity.patient.* del bus MSK (por la VPN) y emite ADT^A28/A40 al HCE
# (por APIM de salida). Plan Elastic Premium por defecto para integración con la VNet;
# usa functions_plan_sku="Y1" (Consumption) si la suscripción no tiene cuota de VM
# dedicada, o enable_function_app=false si NINGÚN SKU de App Service Plan tiene cuota
# (visto en una suscripción académica real: EP1 y Y1 devuelven el mismo 401
# "Operation cannot be completed without additional quota", Current Limit=0).
#
# Nota: esta Function App es solo el disparador HTTP de demo — el consumo real del
# bus corre en el ACI de hl7_consumer.tf (kafka_consumer.py), que no depende de esto.
# =============================================================================
resource "azurerm_service_plan" "func" {
  count               = var.enable_function_app ? 1 : 0
  name                = "${local.name_prefix}-plan"
  resource_group_name = local.rg_name
  location            = local.rg_location
  os_type             = "Linux"
  sku_name            = var.functions_plan_sku != "" ? var.functions_plan_sku : (var.environment == "prod" ? "EP2" : "EP1")
}

resource "azurerm_linux_function_app" "adapter" {
  count               = var.enable_function_app ? 1 : 0
  name                = "${local.name_prefix}-hl7"
  resource_group_name = local.rg_name
  location            = local.rg_location
  service_plan_id     = azurerm_service_plan.func[0].id

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
