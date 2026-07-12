# =============================================================================
# Consumidor Kafka persistente del adaptador HL7 (services/hl7-adapter/kafka_consumer.py).
# NO se despliega como Azure Functions: el binding Kafka nativo de Functions habla
# SASL PLAIN/SCRAM, incompatible con la autenticación IAM de MSK Serverless (ver
# function_app.py). Se despliega como Azure Container Instance con restart_policy
# Always — un proceso que consume en bucle, igual al que ya verificamos localmente
# contra Redpanda (produjo ADT^A28/A40 y los entregó al HCE mock con 200 OK).
# =============================================================================
resource "azurerm_container_registry" "empi" {
  count               = var.enable_kafka_consumer ? 1 : 0
  name                = "${replace(local.name_prefix, "-", "")}acr"
  resource_group_name = local.rg_name
  location            = local.rg_location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_container_group" "hl7_consumer" {
  count               = var.enable_kafka_consumer ? 1 : 0
  name                = "${local.name_prefix}-hl7-consumer"
  resource_group_name = local.rg_name
  location            = local.rg_location
  os_type             = "Linux"
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.aci.id]
  restart_policy      = "Always"

  image_registry_credential {
    server   = azurerm_container_registry.empi[0].login_server
    username = azurerm_container_registry.empi[0].admin_username
    password = azurerm_container_registry.empi[0].admin_password
  }

  container {
    name   = "hl7-consumer"
    image  = "${azurerm_container_registry.empi[0].login_server}/hl7-adapter:latest"
    cpu    = "0.5"
    memory = "0.5"

    # El consumidor no expone servidor HTTP (es un proceso de solo consumo/salida), pero
    # Azure exige al menos un puerto declarado para un container group con IP privada.
    ports {
      port     = 8080
      protocol = "TCP"
    }

    environment_variables = {
      HCE_ENDPOINT   = "http://${azurerm_container_group.hce.ip_address}:8080"
      KAFKA_GROUP_ID = "empi-hl7-adapter"
      KAFKA_AUTH     = var.kafka_auth_mode
      KAFKA_REGION   = "us-east-1"
    }

    secure_environment_variables = {
      KAFKA_BOOTSTRAP       = var.kafka_bootstrap
      AWS_ACCESS_KEY_ID     = var.aws_access_key_id
      AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
      # Solo si usas credenciales temporales (Learner Lab, ~4h). El signer MSK-IAM la
      # detecta automáticamente vía la cadena de credenciales por defecto de boto3.
      AWS_SESSION_TOKEN = var.aws_session_token
    }
  }

  tags = { role = "kafka-consumer", domain = "empi-integration" }
}

# NOTA de despliegue: la imagen se sube manualmente tras el primer apply:
#   az acr login --name <login_server sin .azurecr.io>
#   docker build -f services/hl7-adapter/Dockerfile -t <login_server>/hl7-adapter:latest services/hl7-adapter
#   docker push <login_server>/hl7-adapter:latest
#   az container restart -g <resource_group> -n <name_prefix>-hl7-consumer
