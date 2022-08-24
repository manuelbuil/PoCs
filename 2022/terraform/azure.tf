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
}

resource "azurerm_virtual_network" "vn" {
  name                = "rke2-k3s-networking-vnet"
  address_space       = ["10.1.0.0/16", "fd56:5da5:a285::/48"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "sn" {
  name                 = "IPv6-default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = ["10.1.1.0/24", "fd56:5da5:a285:eea0::/64"]
}

resource "azurerm_public_ip" "pIP" {
  name                = "mbuil-publicIP${count.index}"
  count               = 2
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

#resource "azurerm_public_ip" "pIP2" {
#  name                = "mbuil-publicIP2"
#  location            = azurerm_resource_group.rg.location
#  resource_group_name = azurerm_resource_group.rg.name
#  allocation_method   = "Dynamic"
#}

resource "azurerm_network_interface" "if" {
  count               = 2
  name                = "mbuil-if${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipConfigurationIPv4"
    subnet_id                     = azurerm_subnet.sn.id
    private_ip_address_allocation = "dynamic"
    private_ip_address_version    = "IPv4"
    primary                       = true
    public_ip_address_id          = element(azurerm_public_ip.pIP.*.id, count.index)
  }

  ip_configuration {
    name                          = "ipConfigurationIPv6"
    subnet_id                     = azurerm_subnet.sn.id
    private_ip_address_allocation = "dynamic"
    private_ip_address_version    = "IPv6"
    primary                       = false
  }
}

#resource "azurerm_managed_disk" "test" {
#  count                = 2
#  name                 = "datadisk_existing_${count.index}"
#  location             = azurerm_resource_group.rg.location
#  resource_group_name  = azurerm_resource_group.rg.name
#  storage_account_type = "Standard_LRS"
#  create_option        = "Empty"
#  disk_size_gb         = "35"
#}
#
resource "azurerm_virtual_machine" "test" {
  count                 = 2
  name                  = "terraform-mbuil-vm${count.index}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [element(azurerm_network_interface.if.*.id, count.index)]
  vm_size               = "Standard_DS2_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "canonical"
    sku       = "20_04-lts-gen2"
    version   = "latest"
    offer     = "0001-com-ubuntu-server-focal"
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
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDmIGj5WCtf/zMocWGInE1d5KWU\r\nHZjZKKsVG+LjcaXb2VT3FvyO6EWwegod6VkGHjlHYYBHkiCv0LIGDnTleE/kaCkw\r\nTGXEEG+p1jZoP44Pg4LLfmyqfHy3SYLsUci/oMem6JpTQUTqn92h9Dr4jxLSsz0B\r\nhIvnnRquazSHB1PProkDAo4w3L1yUIgrm+n5fBlBvF5o8k78fkj2iU5wPuAOyOFW\r\nfLLYV096HafcW5l5CGSL8y9w30YxwnZeNhzxlz1tPUF6qT1n04MST4gAaglWaV85\r\nmQsxfKhXRumpUjq6KbjQ9r/75HzxIRVV1BIt273D/58JZMmDrT5NVKvGKTiVaeHP\r\n412AkSO522nq99rd7dCPMpk2k1wVZQgcHioX55OXojN2I0YfHeeq8VcxisyTqjv7\r\nCiAQPZbO3tHeafNhEDB5zDMS/FUl2YGCBN4F/7PjIXIPuYZgCW4tMXHVTKOtqtfm\r\njUkE0lejmlXl5G6nTIug2FirBgSkcJV8ZTDUUOE= generated-by-azure\r\n"
      path     = "/home/azureuser/.ssh/authorized_keys"
    }
  }
}
