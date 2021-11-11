#--------------------------------------------------------------
# Project variable definitions
#--------------------------------------------------------------
variable "name" {
  description = "A unique name for the module"
  type        = string
  default     = "iamsam"
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

variable "vm-size" {
  type        = string
  description = "Preferred VM Size"
  default     = "Standard_E2_v3"
}

variable "time_zone" {
  type        = string
  description = "Time zone for midnight VM shutdown policy"
  default     = "Pacific Standard Time"
}
