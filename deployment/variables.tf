#--------------------------------------------------------------
# Project variable definitions
#--------------------------------------------------------------
variable "linux_vm_count" {
  description = "Count of Linux VMs to create"
  type = number
  default = 2
}

variable "windows_vm_count" {
  description = "Count of Windows VMs to create"
  type = number
  default = 2
}

variable "windows_admin_password" {
  description = "Password for the windows vms"
  type = string
}

variable "vm_base_name" {
  description = "A unique name for the module"
  type        = string
  default     = "vm"
}

variable "region" {
  description = "The region to deploy the resources to"
  type        = string
  default     = "eastus2"
}

variable "resource_group" {
  description = "This is the pre-existing resource group in Azure resources"
  type        = string
  default     = "ama_test"
}

variable "vm_size" {
  type        = string
  description = "Preferred VM Size"
  default     = "Standard_E2_v3"
}

variable "timezones" {
  type = object({
    vm = string
    cli = string
  })
  default = {
    # vm = "Pacific Standard Time"
    vm = "Eastern Standard Time"
    # cli = "America/Los_Angeles"
    cli = "America/New_York"
  }
}