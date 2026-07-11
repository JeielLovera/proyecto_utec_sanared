# Storage account requerido por la Function App (runtime + triggers).
resource "random_string" "sa" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "func" {
  name                     = "empi${var.environment}${random_string.sa.result}" # <=24, minúsculas
  resource_group_name      = azurerm_resource_group.empi.name
  location                 = azurerm_resource_group.empi.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}
