output "VmResourceGroupName" {
  value = azurerm_resource_group.this.name
}

output "linux_vm_ssh" {
  value = "ssh -i ~/.ssh/id_rsa adminuser@${azurerm_public_ip.this.ip_address}"
}

# --enable-auto-upgrade true is not currently allowed for this extension
output "linux_vm_add_ama" {
  value = <<EOT
    az vm extension set \
    --name AzureMonitorLinuxAgent \
    --publisher Microsoft.Azure.Monitor \
    --ids "${azurerm_linux_virtual_machine.vm1.id}"
  EOT
}

output "linux_vm_pwsh_dcra" {
  value = <<EOT
    New-AzDataCollectionRule -Location '${var.region}' -ResourceGroupName '${azurerm_resource_group.this.name}' -RuleName '${local.dcr_name}' -RuleFile './templates/dcr.test.json'
    Remove-AzDataCollectionRule -ResourceGroupName '${azurerm_resource_group.this.name}' -RuleName '${local.dcr_name}'
    New-AzDataCollectionRuleAssociation -TargetResourceId '${azurerm_linux_virtual_machine.vm1.id}' -AssociationName '${local.dcr_linux_assoc_name}' -RuleId '/subscriptions/${local.sub_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${local.dcr_name}'
    Remove-AzDataCollectionRuleAssociation -TargetResourceId '${azurerm_linux_virtual_machine.vm1.id}' -AssociationName '${local.dcr_linux_assoc_name}'
  EOT
}

output "rest_dcr" {
  value = <<EOT
    az rest --subscription ${data.azurerm_client_config.current.subscription_id} \
            --method PUT \
            --url https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.vm1.name}-dcr?api-version=2019-11-01-preview
            --body '@{templates.dcr.test.json}'
  EOT
}

output "rest_dcra" {
  value = <<EOT
    az rest --subscription ${data.azurerm_client_config.current.subscription_id} \
            --method PUT \
            --url https://management.azure.com${azurerm_linux_virtual_machine.vm1.id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${azurerm_linux_virtual_machine.vm1.name}-dcra?api-version=2019-11-01-preview \
            --body '{"properties":{"dataCollectionRuleId": "${azurerm_linux_virtual_machine.vm1.name}-dcr"}}'
  EOT
}