# ============================================================
# main.tf — Azure Infrastructure for Windows/IIS Monitoring Stack
#
# What this creates:
#   - 1× Windows Server 2022 VM (B1S free tier) — IIS web server
#   - 3× Linux Ubuntu VMs (B1S free tier) — Prometheus, Loki, Grafana
#   - Virtual Network with 2 subnets (app tier + monitoring backend)
#   - Network Security Groups (firewall rules)
#   - Public IPs for SSH/RDP access
# ============================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  # Credentials come from: az login  OR  environment variables
  # ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID
}

# ── Resource Group ───────────────────────────────────────────
# A resource group is like a folder in Azure that holds all your resources.
# Deleting the resource group deletes EVERYTHING inside it — useful for cleanup.
resource "azurerm_resource_group" "monitoring" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Project     = "windows-monitoring-stack"
    Environment = "learning"
    ManagedBy   = "terraform"
  }
}

# ── SSH Key for Linux VMs ────────────────────────────────────
# Reads your existing SSH public key from disk.
# If you don't have one, run: ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_monitoring
locals {
  ssh_public_key = file(var.ssh_public_key_path)
}

# ── Windows Server VM (IIS + Alloy) ─────────────────────────
resource "azurerm_windows_virtual_machine" "iis_server" {
  name                = "windows-iis-01"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  # B1S = 1 vCPU, 1GB RAM — qualifies for Azure free tier (750 hours/month)
  size = var.vm_size_windows

  # Windows admin credentials
  admin_username = var.windows_admin_username
  admin_password = var.windows_admin_password

  network_interface_ids = [azurerm_network_interface.iis_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 127
    # 64GB = closest to the Azure free-tier P6 SSD limit.
    # 128GB was the original default — costs ~$5.89/month extra. 64GB saves that.
    # Windows Server 2022 uses ~15-20GB. 64GB gives plenty of headroom for testing.
  }

  # Windows Server 2022 Datacenter — most recent LTS release
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  tags = { Role = "iis-app-server" }
}

# ── Prometheus VM (Linux) ────────────────────────────────────
resource "azurerm_linux_virtual_machine" "prometheus" {
  name                = "prometheus-server"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  size                = var.vm_size_linux   # B1S — free tier

  admin_username                  = var.linux_admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = local.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.prometheus_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = { Role = "prometheus" }
}

# ── Loki VM (Linux) ──────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "loki" {
  name                = "loki-server"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  size                = var.vm_size_linux

  admin_username                  = var.linux_admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = local.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.loki_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = { Role = "loki" }
}

# ── Grafana VM (Linux) ───────────────────────────────────────
resource "azurerm_linux_virtual_machine" "grafana" {
  name                = "grafana-server"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  size                = var.vm_size_linux

  admin_username                  = var.linux_admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = local.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.grafana_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = { Role = "grafana" }
}
