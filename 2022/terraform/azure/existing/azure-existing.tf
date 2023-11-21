terraform {

  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rke2-k3s-networking"
  location = "West Europe"

# ignore tags since they seem to remove important stuff when I terraform apply
  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_virtual_network" "vn" {
  name                = "rke2-k3s-networking-vnet"
  address_space       = ["10.1.0.0/16", "fd56:5da5:a285::/48"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

# ignore tags since they seem to remove important stuff when I terraform apply
  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_subnet" "sn" {
  name                 = "IPv6-default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = ["10.1.1.0/24", "fd56:5da5:a285:eea0::/64"]
}

output "location" {
  value       = azurerm_resource_group.rg.location
}

output "name" {
  value       = azurerm_resource_group.rg.name
}

output "id" {
  value       = azurerm_subnet.sn.id 
}

