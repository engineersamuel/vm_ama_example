resource "azurerm_public_ip" "windows" {
  count               = var.windows_vm_count

  name                = "windows-${local.vm_base_name}-pip-${count.index}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "windows" {
  count               = var.windows_vm_count

  name                = "windows-nic-${count.index}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.windows[count.index].id
  }
}

resource "azurerm_windows_virtual_machine" "this" {
  count               = var.windows_vm_count

  name                = "windows-${local.vm_base_name}-${count.index}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.region
  size                = var.vm_size
  admin_username      = "adminuser"
  admin_password      = var.windows_admin_password

  # Spot can sometimes be unpredictable based on availability, so commenting this out for now
  # priority            = "Spot"
  # eviction_policy     = "Deallocate"

  # https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine#timezone
  timezone = var.timezones["vm"]

  # https://www.terraform.io/docs/providers/azurerm/r/linux_virtual_machine.html
  # The Azure VM Agent only allows creating SSH Keys at the path
  # /home/{username}/.ssh/authorized_keys - as such this public key will be written to the authorized keys file.
  network_interface_ids = [
    azurerm_network_interface.windows[count.index].id,
  ]

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  identity {
    type = "SystemAssigned"
  }
}

# ------------------------------------------------------------------------------------------------------
# OPTIONALLY DEPLOY N VM SHUTDOWN SCHEDULE
# ------------------------------------------------------------------------------------------------------
resource "azurerm_dev_test_global_vm_shutdown_schedule" "windows_shutdown" {
  count              = var.windows_vm_count

  virtual_machine_id = azurerm_windows_virtual_machine.this[count.index].id
  location           = azurerm_windows_virtual_machine.this[count.index].location
  enabled            = true

  daily_recurrence_time = "0000"
  timezone              = var.timezones["vm"]

  notification_settings {
    enabled = false
  }
}

# ------------------------------------------------------------------------------------------------------
# Install Dependency Agent to get VM Insights into individual processes
# ------------------------------------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "windows_da" {
  count                      = var.windows_vm_count

  name                       = "DAExtension"
  virtual_machine_id         =  azurerm_windows_virtual_machine.this[count.index].id
  publisher                  = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                       = "DependencyAgentWindows"
  type_handler_version       = "9.10"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "workspaceId" : "${azurerm_log_analytics_workspace.this.workspace_id}"
    }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "workspaceKey" : "${azurerm_log_analytics_workspace.this.primary_shared_key}"
    }
  PROTECTED_SETTINGS
}

# ------------------------------------------------------------------------------------------------------
# Install Windows Azure Monitor Agent
# ------------------------------------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "windows_ama" {
  count                       = var.windows_vm_count

  name                        = "ama-windows-${count.index}"
  virtual_machine_id          = azurerm_windows_virtual_machine.this[count.index].id
  publisher                   = "Microsoft.Azure.Monitor"
  type                        = "AzureMonitorWindowsAgent"
  type_handler_version        = "1.1"
  auto_upgrade_minor_version  = true

  settings = <<SETTINGS
    {
      "workspaceId" : "${azurerm_log_analytics_workspace.this.workspace_id}"
    }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "workspaceKey" : "${azurerm_log_analytics_workspace.this.primary_shared_key}"
    }
  PROTECTED_SETTINGS
}

# ------------------------------------------------------------------------------------------------------
# Enable the DCR
# ------------------------------------------------------------------------------------------------------
# TODO: Do we need to set the auto-upgrade prompt to no somewhere?  If not I've seen the az cli sit there and wait for user input
# az config set auto-upgrade.prompt=no \
resource "null_resource" "windows_dcr" {
  count = var.windows_vm_count

  provisioner "local-exec" {
    command = <<EOC
      az rest --subscription "${local.sub_id}" \
        --method PUT \
        --url "https://management.azure.com/subscriptions/${local.sub_id}/resourceGroups/${local.rg}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_windows_virtual_machine.this[count.index].name}-dcr?api-version=2019-11-01-preview" \
        --body '${data.template_file.dcr.rendered}'
    EOC
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOC
      az rest --subscription "${self.triggers.sub_id}" \
        --method DELETE \
        --url "https://management.azure.com/subscriptions/${self.triggers.sub_id}/resourceGroups/${self.triggers.rg}/providers/Microsoft.Insights/dataCollectionRules/${self.triggers.dcr_name}?api-version=2019-11-01-preview" \
        --body '{"properties":{"dataCollectionRuleId": "${self.triggers.dcr_name}"}}'
    EOC
    on_failure = continue
  }

  triggers = {
    # Consider a hash check here on the template itself.
    # dcr_id = var.azure_monitor_data_collection_rule_id
    vm_id  = azurerm_windows_virtual_machine.this[count.index].id,
    sub_id  = local.sub_id,
    rg  = azurerm_resource_group.this.name,
    dcr_name = "${azurerm_windows_virtual_machine.this[count.index].name}-dcr"
    data = md5(data.template_file.dcr.rendered)
  }

  depends_on = [
    azurerm_virtual_machine_extension.windows_ama
  ]
}

# ------------------------------------------------------------------------------------------------------
# Enable the DCRa
# ------------------------------------------------------------------------------------------------------
resource "null_resource" "windows_dcra" {
  count = var.windows_vm_count

  provisioner "local-exec" {
    command = <<EOC

      az rest --subscription "${local.sub_id}" \
              --method PUT \
              --url "https://management.azure.com/${azurerm_windows_virtual_machine.this[count.index].id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${azurerm_windows_virtual_machine.this[count.index].name}-dcra?api-version=2019-11-01-preview" \
              --body '{"properties":{"dataCollectionRuleId": "/subscriptions/${local.sub_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_windows_virtual_machine.this[count.index].name}-dcr"}}'
    EOC
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOC
      az rest --subscription "${self.triggers.sub_id}" \
        --method DELETE \
        --url "https://management.azure.com/${self.triggers.vm_id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${self.triggers.dcra_name}?api-version=2019-11-01-preview" \
        --body '{"properties":{"dataCollectionRuleId": "${self.triggers.dcr_id}"}}'
    EOC
    on_failure = continue
  }

  triggers = {
    vm_id  = azurerm_windows_virtual_machine.this[count.index].id,
    sub_id  = data.azurerm_client_config.current.subscription_id,
    rg  = azurerm_resource_group.this.name,
    dcra_name = "${azurerm_windows_virtual_machine.this[count.index].name}-dcra",
    dcr_id = "/subscriptions/${local.sub_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_windows_virtual_machine.this[count.index].name}-dcr"
  }

  depends_on = [
    null_resource.windows_dcr
  ]
}


# $command = 'New-AzDataCollectionRule -Location "${var.region}" -ResourceGroupName "${azurerm_resource_group.this.name}" -RuleName "${azurerm_linux_virtual_machine.vm1.name}-dcr" -RuleFile "./templates/dcr.test.json"'
# $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
# $encodedCommand = [Convert]::ToBase64String($bytes)
# pwsh -encodedcommand $encodedCommand

# resource "null_resource" "install_choco" {
#   count                       = var.windows_vm_count

#   provisioner "local-exec" {
#     # Install Chocolatey
#     # https://community.chocolatey.org/packages/heavyload.portable#description
#     # https://manuals.jam-software.com/heavyload/EN/?quickstart.html
#     command = <<EOC
#       az vm run-command invoke  --command-id RunPowerShellScript --name ${azurerm_windows_virtual_machine.this[count.index].name} -g ${azurerm_resource_group.this.name} \
#         --scripts 'Set-ExecutionPolicy Bypass -Scope Process -Force' \
#         '[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072' \
#         'iex ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))' \
#         --parameters 'arg1=somefoo' 'arg2=somebar'
#     EOC
#   }
# }

# https://superuser.com/questions/396501/how-can-i-produce-high-cpu-load-on-windows
# https://docs.microsoft.com/en-us/sysinternals/downloads/cpustres
# https://download.sysinternals.com/files/CPUSTRES.zip

# This is GUI only
# powershell
# (new-object System.Net.WebClient).DownloadFile('https://download.sysinternals.com/files/CPUSTRES.zip','C:\tmp\CPUSTRES.zip')
# [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# curl https://download.sysinternals.com/files/CPUSTRES.zip -O C:\Windows\Temp\CPUSTRES.zip
# Expand-Archive -LiteralPath 'C:\Windows\Temp\CPUSTRES.zip' -DestinationPath C:\ProgramData\cpustres

# resource "null_resource" "install_heavy_load" {
#   count                       = var.windows_vm_count

#   provisioner "local-exec" {

#     # Install and Exec HeavyLoad
#     # https://community.chocolatey.org/packages/heavyload.portable#description
#     # https://manuals.jam-software.com/heavyload/EN/?quickstart.html
#     command = <<EOC
#       az vm run-command invoke  --command-id RunPowerShellScript --name ${azurerm_windows_virtual_machine.this[count.index].name} -g ${azurerm_resource_group.this.name} \
#         --scripts 'C:\ProgramData\chocolatey\bin\choco.exe install --yes heavyload.portable'
#     EOC
#   }

#   depends_on = [
#     null_resource.install_choco
#   ]
# }

# resource "null_resource" "exec_heavy_load" {
#   count                       = var.windows_vm_count

#   provisioner "local-exec" {

#     # Exec HeavyLoad
#     # https://manuals.jam-software.com/heavyload/EN/?quickstart.html
#     command = <<EOC
#       az vm run-command invoke --command-id RunPowerShellScript --name ${azurerm_windows_virtual_machine.this[count.index].name} -g ${azurerm_resource_group.this.name} \
#         --scripts 'C:\Program Files\JAM Software\HeavyLoad\HeavyLoad.exe /CPU 2 /DURATION 1 /AUTOEXIT /START'
#     EOC
#   }

#   triggers = {
#     always_run = "${timestamp()}"
#   }

#   depends_on = [
#     null_resource.install_heavy_load
#   ]
# }


#
#               # --url "https://management.azure.com${azurerm_windows_virtual_machine.vm1.id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${azurerm_windows_virtual_machine.vm1.name}-dcra?api-version=2019-11-01-preview" \
#       # New-AzDataCollectionRuleAssociation -TargetResourceId '${azurerm_windows_virtual_machine.vm1.id}' -AssociationName '${azurerm_windows_virtual_machine.vm1.name}-dcra' -RuleId '/subscriptions/${local.sub_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_windows_virtual_machine.vm1.name}-dcr'


#       # az monitor data-collection rule association create --name "${azurerm_windows_virtual_machine.vm1.name}-dcra"
#       #  --resource "${azurerm_windows_virtual_machine.vm1.id}"
#       #  [--description]
#       #  [--rule-id]

#       # Ex resource id: "subscriptions/703362b3-f278-4e4b-9179-c76eaf41ffc2/resourceGroups/myResourceGroup/providers/Microsoft.Compute/virtualMachines/myVm"

# # NOTE: Destroy won't work if the VM is stopped, it will error that it can't remove the DCRA if the VM is not running
# ------------------------------------------------------------------------------------------------------
# Allow current user to login
# https://docs.microsoft.com/en-us/azure/active-directory/devices/howto-vm-sign-in-azure-ad-windows
# ------------------------------------------------------------------------------------------------------
resource "azurerm_role_assignment" "windows_user_admin_role" {
  count                 = var.windows_vm_count

  role_definition_name  = "Virtual Machine Administrator Login"
  scope                 = azurerm_windows_virtual_machine.this[count.index].id
  principal_id          = local.user_object_id

}