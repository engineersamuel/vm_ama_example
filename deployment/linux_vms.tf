resource "azurerm_public_ip" "linux" {
  count               = var.linux_vm_count

  name                = "linux-${local.vm_base_name}-pip-${count.index}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "linux" {
  count               = var.linux_vm_count

  name                = "linux-nic-${count.index}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    # TODO: Count here?
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.linux[count.index].id
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  count               = var.linux_vm_count

  name                = "linux-${local.vm_base_name}-${count.index}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.region
  size                = var.vm_size
  admin_username      = "adminuser"

  # Spot can sometimes be unpredictable based on availability, so commenting this out for now
  # priority            = "Spot"
  # eviction_policy     = "Deallocate"

  # https://www.terraform.io/docs/providers/azurerm/r/linux_virtual_machine.html
  # The Azure VM Agent only allows creating SSH Keys at the path
  # /home/{username}/.ssh/authorized_keys - as such this public key will be written to the authorized keys file.
  network_interface_ids = [
    azurerm_network_interface.linux[count.index].id,
  ]

  # https://trstringer.com/azure-linux-vm-ssh-public-key-denied/
  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
    # public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# ------------------------------------------------------------------------------------------------------
# STORE PRIVATE SSH KEYS AT KEYVAULT
# ------------------------------------------------------------------------------------------------------
# resource "azurerm_key_vault_secret" "vm1_ssh_private_key" {
#   name = "${azurerm_linux_virtual_machine.vm1.name}-ssh-pkey"

#   value        = tls_private_key.ssh.private_key_pem
#   key_vault_id = azurerm_key_vault.agents_kv.id
# }

# ------------------------------------------------------------------------------------------------------
# OPTIONALLY DEPLOY N VM SHUTDOWN SCHEDULE
# ------------------------------------------------------------------------------------------------------
resource "azurerm_dev_test_global_vm_shutdown_schedule" "linux_shutdown" {
  count              = var.linux_vm_count

  virtual_machine_id = azurerm_linux_virtual_machine.this[count.index].id
  location           = azurerm_linux_virtual_machine.this[count.index].location
  enabled            = true

  daily_recurrence_time = "0000"
  timezone              = var.timezones["vm"]

  notification_settings {
    enabled = false
  }
}

# TODO: Consider remote exec for stress: https://github.com/hashicorp/terraform/issues/21665
# ------------------------------------------------------------------------------------------------------
# Custom linux libraries
# ------------------------------------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "linux_custom_commands" {
  count                = var.linux_vm_count

  name                 = "custom_commands"
  virtual_machine_id   = azurerm_linux_virtual_machine.this[count.index].id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  #
  settings = <<SETTINGS
    {
        "commandToExecute": "sudo apt-get update && sudo apt-get -y install stress && sudo timedatectl set-timezone ${var.timezones["cli"]}"
    }
SETTINGS

}

# ------------------------------------------------------------------------------------------------------
# Install Dependency Agent to get VM Insights into individual processes
# ------------------------------------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "linux_da" {
  count                       = var.linux_vm_count

  name                       = "DAExtension"
  virtual_machine_id         =  azurerm_linux_virtual_machine.this[count.index].id
  publisher                  = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                       = "DependencyAgentLinux"
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
# Install Azure Monitor Agent
# ------------------------------------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "linux_ama" {
  count                       = var.linux_vm_count

  name                        = "ama-windows-${count.index}"
  virtual_machine_id          = azurerm_linux_virtual_machine.this[count.index].id
  publisher                   = "Microsoft.Azure.Monitor"
  type                        = "AzureMonitorLinuxAgent"
  type_handler_version        = "1.14"
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

# $command = 'dir "c:\program files" '
# $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
# $encodedCommand = [Convert]::ToBase64String($bytes)
# pwsh -encodedcommand $encodedCommand
# New-AzDataCollectionRule -Location '${var.region}' -ResourceGroupName '${azurerm_resource_group.this.name}' -RuleName '${azurerm_linux_virtual_machine.vm1.name}-dcr' -RuleFile './templates/dcr.test.json'

# TODO: Do we need to set the auto-upgrade prompt to no somewhere?  If not I've seen the az cli sit there and wait for user input
# az config set auto-upgrade.prompt=no \
resource "null_resource" "linux_dcr" {
  count = var.linux_vm_count

  provisioner "local-exec" {
    command = <<EOC
      az rest --subscription "${local.sub_id}" \
        --method PUT \
        --url "https://management.azure.com/subscriptions/${local.sub_id}/resourceGroups/${local.rg}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.this[count.index].name}-dcr?api-version=2019-11-01-preview" \
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
    vm_id  = azurerm_linux_virtual_machine.this[count.index].id,
    sub_id  = local.sub_id,
    rg  = azurerm_resource_group.this.name,
    dcr_name = "${azurerm_linux_virtual_machine.this[count.index].name}-dcr"
    data = md5(data.template_file.dcr.rendered)
  }

  depends_on = [
    azurerm_virtual_machine_extension.linux_ama
  ]
}


# --url "https://management.azure.com${azurerm_linux_virtual_machine.vm1.id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${azurerm_linux_virtual_machine.vm1.name}-dcra?api-version=2019-11-01-preview" \
# New-AzDataCollectionRuleAssociation -TargetResourceId '${azurerm_linux_virtual_machine.vm1.id}' -AssociationName '${azurerm_linux_virtual_machine.vm1.name}-dcra' -RuleId '/subscriptions/${local.sub_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.vm1.name}-dcr'


# az monitor data-collection rule association create --name "${azurerm_linux_virtual_machine.vm1.name}-dcra"
#  --resource "${azurerm_linux_virtual_machine.vm1.id}"
#  [--description]
#  [--rule-id]

# NOTE: Destroy won't work if the VM is stopped, it will error that it can't remove the DCRA if the VM is not running
resource "null_resource" "linux_dcra" {
  count = var.linux_vm_count

  provisioner "local-exec" {
    command = <<EOC

      az rest --subscription "${local.sub_id}" \
              --method PUT \
              --url "https://management.azure.com/${azurerm_linux_virtual_machine.this[count.index].id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${azurerm_linux_virtual_machine.this[count.index].name}-dcra?api-version=2019-11-01-preview" \
              --body '{"properties":{"dataCollectionRuleId": "/subscriptions/${local.sub_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.this[count.index].name}-dcr"}}'
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
    vm_id  = azurerm_linux_virtual_machine.this[count.index].id,
    sub_id  = data.azurerm_client_config.current.subscription_id,
    rg  = azurerm_resource_group.this.name,
    dcra_name = "${azurerm_linux_virtual_machine.this[count.index].name}-dcra",
    dcr_id = "/subscriptions/${local.sub_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.this[count.index].name}-dcr"
  }

  depends_on = [
    null_resource.linux_dcr
  ]
}

# ------------------------------------------------------------------------------------------------------
# ENABLE AAD SSH in Linux VM(s)
# https://docs.microsoft.com/en-us/azure/active-directory/devices/howto-vm-sign-in-azure-ad-linux
# Currently not working
# ------------------------------------------------------------------------------------------------------
/*
resource "azurerm_virtual_machine_extension" "vm1_aad_ssh" {
  name                 = "${azurerm_linux_virtual_machine.vm1.name}-aad-ssh"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm1.id
  publisher            = "Microsoft.Azure.ActiveDirectory"
  type                 = "AADSSHLoginForLinux"
  type_handler_version = "1.0"
  auto_upgrade_minor_version = true
}
*/

# ------------------------------------------------------------------------------------------------------
# Allow current user to login
# https://docs.microsoft.com/en-us/azure/active-directory/devices/howto-vm-sign-in-azure-ad-linux
# ------------------------------------------------------------------------------------------------------
resource "azurerm_role_assignment" "linux_user_admin_role" {
  count                 = var.linux_vm_count

  role_definition_name  = "Virtual Machine Administrator Login"
  scope                 = azurerm_linux_virtual_machine.this[count.index].id
  principal_id          = local.user_object_id

}