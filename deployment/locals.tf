#--------------------------------------------------------------
# Local Vars
#--------------------------------------------------------------
locals {
  vm_base_name = lower(var.vm_base_name)
}

locals {
  user_object_id  = "${data.azurerm_client_config.current.object_id}"
  sub_id  = "${data.azurerm_subscription.current.subscription_id}"
  rg  = "${azurerm_resource_group.this.name}"
}