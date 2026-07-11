provider "azurerm" {
  features {}
  # subscription_id/tenant_id se toman de az CLI o de variables de entorno ARM_*.
  subscription_id = var.subscription_id != "" ? var.subscription_id : null
}
