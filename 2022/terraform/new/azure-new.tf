terraform {

  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

variable "rgLocation" {
	type	= string
	default = "westeurope"
}
variable "rgName" {
	type	= string
	default = "rke2-k3s-networking"
}

variable "snId" {
	type = string
	default = "/subscriptions/f5e1bf9e-ec79-4fc5-8354-53e2fcc0d99f/resourceGroups/rke2-k3s-networking/providers/Microsoft.Network/virtualNetworks/rke2-k3s-networking-vnet/subnets/IPv6-default"
}

provider "azurerm" {
  features {}
}

resource "azurerm_public_ip" "pIP" {
  name                = "mbuil-publicIP${count.index}"
  count               = 2
  location            = var.rgLocation
  resource_group_name = var.rgName
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "if" {
  count               = 2
  name                = "mbuil-if${count.index}"
  location            = var.rgLocation
  resource_group_name = var.rgName

  ip_configuration {
    name                          = "ipConfigurationIPv4"
    subnet_id                     = var.snId
    private_ip_address_allocation = "dynamic"
    private_ip_address_version    = "IPv4"
    primary                       = true
    public_ip_address_id          = element(azurerm_public_ip.pIP.*.id, count.index)
  }

  ip_configuration {
    name                          = "ipConfigurationIPv6"
    subnet_id                     = var.snId
    private_ip_address_allocation = "dynamic"
    private_ip_address_version    = "IPv6"
    primary                       = false
  }
}

resource "azurerm_virtual_machine" "controlPlane" {
  count                 = 2
  name                  = "terraform-mbuil-vm${count.index}"
  location              = var.rgLocation
  resource_group_name   = var.rgName
  network_interface_ids = [element(azurerm_network_interface.if.*.id, count.index)]
  vm_size               = "Standard_DS2_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "canonical"
    sku       = "22_04-lts-gen2"
    version   = "latest"
    offer     = "0001-com-ubuntu-server-jammy"
  }

  storage_os_disk {
    name              = "myosdisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = 30
  }

  os_profile {
    computer_name  = "mbuil-vm${count.index}"
    admin_username = "azureuser"
    admin_password = ""
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDSDujXqHgH0BhMExw+PpxDIoadAmxl28KQQ/Lr73PRLhSYBe2JSvh3DFL1OkfLaORsNApXFdCmO2U4606o4a0ytduQmTBYSMfcAbaBqHxj3CU1HmOxLv4FZoXSrtm7Jvho8suwjIotVfCdWYqXAyVWxfTNfMUGKVPOJgLBDZhLZ+eg3KEKYR1V37pbdE/KZabBG627vMffXdGlrCXvkQaW3UjvMK7u+VqSh2ykllTijekDApwMAeFt+tSluIN7dvXWy38QnbYkVQAJGBmEkwqEwm1Dpv41JcDaqN1UQY5vjlUryqXDqBvo7Vof/2lubDtO0DHCD/C+1enZYW29UlSyGR7qki9wDS1GFkHemmI5d+QpjK5czKYhP+uB0eKcPTP4+kP6PRdahubZMQ18zkq5yVWfwloRKxa39MwBHYf1d7my+swR8Nf2AhCxb0b8M3RXj1hnT6oYfEAukg1yS3km/QXuSG400WmXKtU+G0i/Jr50CEKky5q8SkYP4ErBxDE= manuel@localhost.localdomain"
      path     = "/home/azureuser/.ssh/authorized_keys"
    }
  }
}

output "ipAddresses" {
  value       = azurerm_public_ip.pIP[*].ip_address
}
