resource "azurerm_virtual_network" "this" {
  name                = "example-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "this" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "vm1" {
  name                = "linux-vm1-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.this.id
  }
}

resource "azurerm_public_ip" "this" {
  name                = local.vm_linux_name_pip
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Dynamic"
}

resource "azurerm_linux_virtual_machine" "vm1" {
  name                = local.vm_linux_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.region
  size                = var.vm-size
  admin_username      = "adminuser"

  # https://www.terraform.io/docs/providers/azurerm/r/linux_virtual_machine.html
  # The Azure VM Agent only allows creating SSH Keys at the path
  # /home/{username}/.ssh/authorized_keys - as such this public key will be written to the authorized keys file.
  network_interface_ids = [
    azurerm_network_interface.vm1.id,
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

# ------------------------------------------------------------------------------------------------------
# OPTIONALLY DEPLOY N VM SHUTDOWN SCHEDULE
# ------------------------------------------------------------------------------------------------------
resource "azurerm_dev_test_global_vm_shutdown_schedule" "vm_nightly_shutdown" {
  virtual_machine_id = azurerm_linux_virtual_machine.vm1.id
  location           = azurerm_linux_virtual_machine.vm1.location
  enabled            = true

  daily_recurrence_time = "0000"
  timezone              = var.time_zone

  notification_settings {
    enabled = false
  }
}

# ------------------------------------------------------------------------------------------------------
# Custom linux libraries
# ------------------------------------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "custom_commands" {
  name                 = "custom_commands"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm1.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
        "commandToExecute": "sudo apt-get update && sudo apt-get -y install stress && sudo timedatectl set-timezone America/New_York"
    }
SETTINGS


  #protected_settings = <<SETTINGS
  #  "script": "${base64encode(file(var.linux_installation_script))}"
#SETTINGS
}

resource "azurerm_virtual_machine_extension" "ama" {
  name = "AMALinux"
  virtual_machine_id = azurerm_linux_virtual_machine.vm1.id
  publisher = "Microsoft.Azure.Monitor"
  type = "AzureMonitorLinuxAgent"
  type_handler_version = "1.12"
  auto_upgrade_minor_version = true
}

# resource "null_resource" "dcr" {
#   provisioner "local-exec" {
#     command = <<EOC
#       New-AzDataCollectionRule -Location '${var.region}' -ResourceGroupName '${azurerm_resource_group.this.name}' -RuleName '${local.dcr_name}' -RuleFile './templates/dcr.test.json'

#       az rest --subscription ${data.azurerm_client_config.current.subscription_id} \
#               --method PUT \
#               --url https://management.azure.com${azurerm_linux_virtual_machine.vm.id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${azurerm_linux_virtual_machine.vm.name}-dcrassociation?api-version=2019-11-01-preview \
#               --body '{"properties":{"dataCollectionRuleId": "${var.azure_monitor_data_collection_rule_id}"}}'
#     EOC
#   }

#   triggers = {
#     # dcr_id = var.azure_monitor_data_collection_rule_id
#     vm_id  = azurerm_linux_virtual_machine.vm.id
#   }
# }

    # DESTINATION_NAME="log-analytics-log-destination" \
    # WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace list -g ama_test | jq -r '.[0].id') \
    # jq '.properties.destinations.logAnalytics[0].workspaceResourceId |= env.WORKSPACE_RESOURCE_ID | .properties.destinations.logAnalytics[0].name = env.DESTINATION_NAME | .properties.dataFlows[0].destinations |= [ env.DESTINATION_NAME ]' templates/dcr.base.json > templates/dcr.test.json
# module "dcr" {
#   source = "matti/resource/shell"

#   command = <<EOC
#     az rest --subscription ${data.azurerm_client_config.current.subscription_id} \
#             --method PUT \
#             --url https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.vm.name}-dcr?api-version=2019-11-01-preview
#             --body '{"properties":{"dataCollectionRuleId": "${var.azure_monitor_data_collection_rule_id}"}}'
#   EOC
# }

      # az rest --subscription "${data.azurerm_client_config.current.subscription_id}" \
      #         --method PUT \
      #         --url "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.vm1.name}-dcr?api-version=2019-11-01-preview" \
              # --body @{templates/dcr.test.json}

# $command = 'dir "c:\program files" '
#         $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
#         $encodedCommand = [Convert]::ToBase64String($bytes)
#         pwsh -encodedcommand $encodedCommand
      # New-AzDataCollectionRule -Location '${var.region}' -ResourceGroupName '${azurerm_resource_group.this.name}' -RuleName '${azurerm_linux_virtual_machine.vm1.name}-dcr' -RuleFile './templates/dcr.test.json'

data "template_file" "dcr" {
  template = file(format("%s/templates/dcr.base.json.tpl", path.module))

  vars = {
    location                      = var.region
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
    # log_analytics_workspace_id    = azurerm_log_analytics_workspace.this.workspace_id
    log_analytics_workspace_name  = azurerm_log_analytics_workspace.this.name
    # destination_name              = "log-analytics-log-destination"
    destination_name              = azurerm_log_analytics_workspace.this.name
    # syslog_facility_names      = jsonencode(var.syslog_facilities_names)
    # syslog_levels              = jsonencode(var.syslog_levels)
    # tags                       = jsonencode(merge(local.default_tags, var.extra_tags))
  }
}

      # az config set auto-upgrade.prompt=no \
      # DESTINATION_NAME="log-analytics-log-destination" \
      # WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace list -g ama_test | jq -r '.[0].id') \
      # jq '.properties.destinations.logAnalytics[0].workspaceResourceId |= env.WORKSPACE_RESOURCE_ID | .properties.destinations.logAnalytics[0].name = env.DESTINATION_NAME | .properties.dataFlows[0].destinations |= [ env.DESTINATION_NAME ]' templates/dcr.base.json > templates/dcr.test.json \


      # $command = 'New-AzDataCollectionRule -Location "${var.region}" -ResourceGroupName "${azurerm_resource_group.this.name}" -RuleName "${azurerm_linux_virtual_machine.vm1.name}-dcr" -RuleFile "./templates/dcr.test.json"'
      # $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
      # $encodedCommand = [Convert]::ToBase64String($bytes)
      # pwsh -encodedcommand $encodedCommand

# TODO: Do we need to set the auto-upgrade prompt to no somewhere?  If not I've seen the az cli sit there and wait for user input
# az config set auto-upgrade.prompt=no \
resource "null_resource" "dcr" {
  provisioner "local-exec" {
    command = <<EOC
      az rest --subscription "${data.azurerm_client_config.current.subscription_id}" \
        --method PUT \
        --url "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.vm1.name}-dcr?api-version=2019-11-01-preview" \
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
    vm_id  = azurerm_linux_virtual_machine.vm1.id,
    sub_id  = data.azurerm_client_config.current.subscription_id,
    rg  = azurerm_resource_group.this.name,
    dcr_name = "${azurerm_linux_virtual_machine.vm1.name}-dcr"
    data = md5(data.template_file.dcr.rendered)
  }

  depends_on = [
    azurerm_virtual_machine_extension.ama
  ]
}


              # --url "https://management.azure.com${azurerm_linux_virtual_machine.vm1.id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${azurerm_linux_virtual_machine.vm1.name}-dcra?api-version=2019-11-01-preview" \
      # New-AzDataCollectionRuleAssociation -TargetResourceId '${azurerm_linux_virtual_machine.vm1.id}' -AssociationName '${azurerm_linux_virtual_machine.vm1.name}-dcra' -RuleId '/subscriptions/${local.sub_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.vm1.name}-dcr'


      # az monitor data-collection rule association create --name "${azurerm_linux_virtual_machine.vm1.name}-dcra"
      #  --resource "${azurerm_linux_virtual_machine.vm1.id}"
      #  [--description]
      #  [--rule-id]

      # Ex resource id: "subscriptions/703362b3-f278-4e4b-9179-c76eaf41ffc2/resourceGroups/myResourceGroup/providers/Microsoft.Compute/virtualMachines/myVm"

# NOTE: Destroy won't work if the VM is stopped, it will error that it can't remove the DCRA if the VM is not running
resource "null_resource" "dcra" {

  provisioner "local-exec" {
    command = <<EOC

      az rest --subscription "${data.azurerm_client_config.current.subscription_id}" \
              --method PUT \
              --url "https://management.azure.com/${azurerm_linux_virtual_machine.vm1.id}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${azurerm_linux_virtual_machine.vm1.name}-dcra?api-version=2019-11-01-preview" \
              --body '{"properties":{"dataCollectionRuleId": "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.vm1.name}-dcr"}}'
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
    # vm_name  = azurerm_linux_virtual_machine.vm1.name,
    vm_id  = azurerm_linux_virtual_machine.vm1.id,
    sub_id  = data.azurerm_client_config.current.subscription_id,
    rg  = azurerm_resource_group.this.name,
    dcra_name = "${azurerm_linux_virtual_machine.vm1.name}-dcra",
    dcr_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Insights/dataCollectionRules/${azurerm_linux_virtual_machine.vm1.name}-dcr"
  }

  depends_on = [
    null_resource.dcr
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
resource "azurerm_role_assignment" "current_user_ssh_login" {
  role_definition_name = "Virtual Machine Administrator Login"
  scope                = azurerm_linux_virtual_machine.vm1.id
  principal_id         = local.user_object_id

}