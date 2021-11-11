# https://github.com/hashicorp/terraform-provider-azurerm/tree/main/examples

#--------------------------------------------------------------
# Set provider requirements
#--------------------------------------------------------------
terraform {
  required_version = ">= 1.0.10"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.69.0"
    }
    azurecaf = {
      source = "aztfmod/azurecaf"
      version = "1.2.6"
    }
  }
}

provider "azurerm" {
  features {}
}

#----------------------------------------------------------------
# Data Sources
#----------------------------------------------------------------

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "this" {
  name = var.resource_group
  location = var.region
}

# ------------------------------------------------------------------------------------------------------
# GENERATE SSH KEYS
# ------------------------------------------------------------------------------------------------------

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
