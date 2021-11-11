output "VmResourceGroupName" {
  value = azurerm_resource_group.this.name
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
