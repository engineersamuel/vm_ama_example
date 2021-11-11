#--------------------------------------------------------------
# Local Vars
#--------------------------------------------------------------
locals {
  resource_prefix = lower(var.name)
  dcr_linux_assoc_name = "linux-vm-association"
  dcr_name = "dcr-eastus2"
  log_destination_name="log-analytics-log-destination"
}

locals {
  user_object_id  = "${data.azurerm_client_config.current.object_id}"
  sub_id  = "${data.azurerm_subscription.current.subscription_id}"
}