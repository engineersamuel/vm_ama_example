# ------------------------------------------------------------------------------------------------------
# DEPLOY LOG ANALYTICS WORKSPACE
// https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/oms-linux
# ------------------------------------------------------------------------------------------------------
resource "azurecaf_name" "laws_name" {
  name          = "agents-ws"
  resource_type = "azurerm_log_analytics_workspace"
  random_length = 5
  clean_input   = true
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = azurecaf_name.laws_name.result
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 180
}
