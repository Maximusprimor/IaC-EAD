resource "azurerm_virtual_network" "vnet" {
  name                = "${var.vm_name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.vm_name}-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.vm_name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "allow-winrm"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "allow-rdp"
    priority                   = 3000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-icmp"
    priority                   = 3010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "vm_public_ip" {
  name                = "${var.vm_name}-pubip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "${var.vm_name}-ip"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "isga" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                  = var.vm_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = "eadadm"
  admin_password        = "Fab12345"
  network_interface_ids = [azurerm_network_interface.nic.id]
  computer_name         = var.vm_name
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  os_disk {
    name              = "${var.vm_name}-osdisk"
    caching           = "ReadWrite"
    storage_account_type = var.disk_type
  }

  os_profile_windows_config {
    provision_vm_agent        = "true"
    enable_automatic_upgrades = "true"
    winrm {
      protocol = "HTTPS"
    }
  }
}

resource "azurerm_virtual_machine_extension" "ccwh" {
  name                       = "customCommandWinrmHttps"
  virtual_machine_id         = azurerm_virtual_machine.vm.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.9"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "commandToExecute": "netsh advfirewall firewall add rule name=\\"WinRM-HTTPS\\" dir=in action=allow protocol=TCP localport=5986"
    }
SETTINGS
}

resource "tls_private_key" "tpk" {
  algorithm   = "RSA"
  rsa_bits    = 2048
}

resource "tls_locally_signed_cert" "tlsc" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.tpk.private_key_pem

  subject {
    common_name  = "eadteste.com"
    organization = "eadteste"
  }

  validity_period_hours = 8760 # 1 year
}

resource "azurerm_virtual_machine_extension" "ccic" {
  name                 = "install-certificate"
  virtual_machine_id   = azurerm_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = jsonencode({
    "commandToExecute": "powershell.exe -ExecutionPolicy Unrestricted -File ${path.module}/install_certificate.ps1"
  })

  protected_settings = jsonencode({
    "script": base64encode(templatefile("${path.module}/install_certificate.ps1.tpl", {
      certificate_pem = tls_locally_signed_cert.example.cert_pem
      private_key_pem  = tls_private_key.example.private_key_pem
    }))
  })
}
