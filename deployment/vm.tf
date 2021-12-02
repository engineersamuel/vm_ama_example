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