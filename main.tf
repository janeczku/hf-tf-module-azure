variable "client_id" {}
variable "subscription_id" {}
variable "tenant_id" {}
variable "client_secret" {}
variable "name" {}
variable "resource_group" {}
variable "location" {}
variable "vnet" {}
variable "subnet" {}
variable "public_key" {}
variable "registry_url" {
  default = ""
}
variable "registry_user" {
  default = ""
}
variable "registry_password" {
  default = ""
}
variable "cloud_init" {
  default = ""
}
variable "ssh_user" {
  default = "ubuntu"
}
variable "vm_size" {
  default = "Standard_B2s"
}
variable "disk" {
  default = "10"
}
variable "image" {
  description = "Format: '<Publisher>,<Offer>,<SKU>'"
  default = "Canonical,UbuntuServer,16.04-LTS"
}

provider "azurerm" {
  version = ">= 1.3.0"
  client_id = var.client_id
  subscription_id = var.subscription_id
  tenant_id = var.tenant_id
  client_secret = var.client_secret
}

locals {
  tags = {
    Owner = "hobbyfarm"
    DoNotDelete = "true"
  }
  cloud_config = <<EOF
#cloud-config
runcmd:
- 'curl https://releases.rancher.com/install-docker/18.09.sh | sh'
- 'sudo usermod -aG docker ubuntu'
- 'sudo su ubuntu -c "docker login -u ${var.registry_user} -p ${var.registry_password} ${var.registry_url}"'
EOF
}

data "azurerm_subnet" "instance" {
  name                 = var.subnet
  virtual_network_name = var.vnet
  resource_group_name  = var.resource_group
}

resource "azurerm_public_ip" "instance" {
  name                = "publicip-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group
  allocation_method   = "Dynamic"
  domain_name_label   = "hobbyfarm-${var.name}"
  tags                = local.tags
}

data "azurerm_public_ip" "instance" {
  name                = "publicip-${var.name}"
  resource_group_name = var.resource_group
  depends_on = [azurerm_virtual_machine.instance]
}

resource "azurerm_network_interface" "instance" {
  name                          = "nic-${var.name}"
  location                      = var.location
  resource_group_name           = var.resource_group
  ip_configuration {
    name                          = "ipconfig-${var.name}"
    subnet_id                     = data.azurerm_subnet.instance.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.instance.id
  }
  tags = local.tags
}

resource "azurerm_virtual_machine" "instance" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group
  vm_size                       = var.vm_size
  network_interface_ids         = ["${azurerm_network_interface.instance.id}"]
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = element(split(",", var.image), 0)
    offer     = element(split(",", var.image), 1)
    sku       = element(split(",", var.image), 2)
    version   = "latest"
  }

  storage_os_disk {
    name              = "osdisk-${var.name}"
    os_type           = "Linux"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "StandardSSD_LRS"
  }

  os_profile {
    computer_name  = var.name
    admin_username = var.ssh_user
    custom_data    = local.cloud_config
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.ssh_user}/.ssh/authorized_keys"
      key_data = var.public_key
    }
  }

  tags = local.tags
}

output "private_ip" {
  value = azurerm_network_interface.instance.private_ip_address
}

output "public_ip" {
   value = data.azurerm_public_ip.instance.ip_address
}

output "hostname" {
  value = azurerm_public_ip.instance.fqdn
}
