output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "linux_vm_ssh" {
  value = {for k, v in azurerm_public_ip.linux: k => "ssh -i ~/.ssh/id_rsa adminuser@${v.ip_address}"}
}

output "windows_vm_rdp" {
  value = {for k, v in azurerm_windows_virtual_machine.this: k => "Get-AzRemoteDesktopFile -ResourceGroupName '${azurerm_resource_group.this.name}' -Name '${v.name}' -Launch"}
}