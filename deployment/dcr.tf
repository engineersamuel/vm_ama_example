# ------------------------------------------------------------------------------------------------------
# Create the DCR template
# ------------------------------------------------------------------------------------------------------
data "template_file" "dcr" {
  template = file(format("%s/templates/dcr.base.json.tpl", path.module))

  vars = {
    location                      = var.region
    log_analytics_workspace_id    = azurerm_log_analytics_workspace.this.id
    log_analytics_workspace_name  = azurerm_log_analytics_workspace.this.name
    destination_name              = azurerm_log_analytics_workspace.this.name
  }
}
