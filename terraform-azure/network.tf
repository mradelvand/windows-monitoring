# ============================================================
# network.tf — Azure Networking
#
# Two subnets inside one VNet:
#   app-subnet      → Windows IIS servers (public-facing)
#   backend-subnet  → Prometheus, Loki, Grafana (internal only)
#
# NSG rules follow the principle of least privilege:
#   - Only open what's absolutely needed
#   - Backend services unreachable from public internet
#   - All inter-service traffic goes through private IPs
# ============================================================

# ── Virtual Network ──────────────────────────────────────────
# Think of this as your private network inside Azure.
# 10.0.0.0/16 means IP addresses 10.0.0.0 through 10.0.255.255
resource "azurerm_virtual_network" "monitoring_vnet" {
  name                = "monitoring-vnet"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  address_space       = ["10.0.0.0/16"]

  tags = { Project = "windows-monitoring-stack" }
}

# ── App Subnet (Windows IIS VMs) ─────────────────────────────
resource "azurerm_subnet" "app_subnet" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.monitoring.name
  virtual_network_name = azurerm_virtual_network.monitoring_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ── Backend Subnet (Prometheus, Loki, Grafana) ───────────────
resource "azurerm_subnet" "backend_subnet" {
  name                 = "backend-subnet"
  resource_group_name  = azurerm_resource_group.monitoring.name
  virtual_network_name = azurerm_virtual_network.monitoring_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# ─────────────────────────────────────────────────────────────
# NSG: Windows IIS Server
# Allows: RDP from admin, HTTP/HTTPS from internet
# ─────────────────────────────────────────────────────────────
resource "azurerm_network_security_group" "iis_nsg" {
  name                = "iis-nsg"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  # RDP (port 3389) — Windows Remote Desktop — admin only
  security_rule {
    name                       = "Allow-RDP-Admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "${var.admin_ip}/32"
    destination_address_prefix = "*"
    description                = "RDP access for admin only"
  }

  # WinRM (port 5985) — Windows Remote Management — admin only
  # Used by some automation tools. Optional but useful.
  security_rule {
    name                       = "Allow-WinRM-Admin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985"
    source_address_prefix      = "${var.admin_ip}/32"
    destination_address_prefix = "*"
    description                = "WinRM from admin only"
  }

  # HTTP — IIS serves web traffic on port 80
  security_rule {
    name                       = "Allow-HTTP-Public"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "HTTP public web traffic"
  }

  # HTTPS — IIS secure web traffic
  security_rule {
    name                       = "Allow-HTTPS-Public"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "HTTPS public web traffic"
  }

  # Alloy UI (port 12345) — admin only
  security_rule {
    name                       = "Allow-Alloy-UI-Admin"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "12345"
    source_address_prefix      = "${var.admin_ip}/32"
    destination_address_prefix = "*"
    description                = "Alloy status UI - admin only"
  }

  tags = { Role = "iis-nsg" }
}

# ─────────────────────────────────────────────────────────────
# NSG: Prometheus Server
# Key: port 9090 open ONLY from backend subnet (Alloy push + Grafana query)
# ─────────────────────────────────────────────────────────────
resource "azurerm_network_security_group" "prometheus_nsg" {
  name                = "prometheus-nsg"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  # SSH — admin only
  security_rule {
    name                       = "Allow-SSH-Admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${var.admin_ip}/32"
    destination_address_prefix = "*"
    description                = "SSH from admin only"
  }

  # Prometheus UI — admin only
  security_rule {
    name                       = "Allow-Prometheus-Admin"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = "${var.admin_ip}/32"
    destination_address_prefix = "*"
    description                = "Prometheus UI - admin only"
  }

  # Prometheus remote_write — from app subnet (Alloy on Windows pushes here)
  security_rule {
    name                       = "Allow-Prometheus-AppSubnet"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = "10.0.1.0/24"   # app-subnet
    destination_address_prefix = "*"
    description                = "Alloy remote_write from IIS servers"
  }

  # Prometheus query — from Grafana in backend subnet
  security_rule {
    name                       = "Allow-Prometheus-BackendSubnet"
    priority                   = 220
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = "10.0.2.0/24"   # backend-subnet
    destination_address_prefix = "*"
    description                = "Grafana queries Prometheus"
  }

  tags = { Role = "prometheus-nsg" }
}

# ─────────────────────────────────────────────────────────────
# NSG: Loki Server
# Port 3100: open from app-subnet (Alloy log push) + backend-subnet (Grafana)
# ─────────────────────────────────────────────────────────────
resource "azurerm_network_security_group" "loki_nsg" {
  name                = "loki-nsg"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  security_rule {
    name                       = "Allow-SSH-Admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${var.admin_ip}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Loki-AppSubnet"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3100"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
    description                = "Alloy log push from IIS servers"
  }

  security_rule {
    name                       = "Allow-Loki-BackendSubnet"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3100"
    source_address_prefix      = "10.0.2.0/24"
    destination_address_prefix = "*"
    description                = "Grafana queries Loki"
  }

  tags = { Role = "loki-nsg" }
}

# ─────────────────────────────────────────────────────────────
# NSG: Grafana Server
# Port 3000: admin only (via VPN in production)
# ─────────────────────────────────────────────────────────────
resource "azurerm_network_security_group" "grafana_nsg" {
  name                = "grafana-nsg"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  security_rule {
    name                       = "Allow-SSH-Admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${var.admin_ip}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Grafana-Admin"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "${var.admin_ip}/32"
    destination_address_prefix = "*"
    description                = "Grafana UI - admin only (use VPN in prod)"
  }

  tags = { Role = "grafana-nsg" }
}

# ─────────────────────────────────────────────────────────────
# Public IPs
# ─────────────────────────────────────────────────────────────
resource "azurerm_public_ip" "iis_pip" {
  name                = "iis-public-ip"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "prometheus_pip" {
  name                = "prometheus-public-ip"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "loki_pip" {
  name                = "loki-public-ip"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "grafana_pip" {
  name                = "grafana-public-ip"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ─────────────────────────────────────────────────────────────
# Network Interfaces (NICs) — connect VMs to subnets
# ─────────────────────────────────────────────────────────────
resource "azurerm_network_interface" "iis_nic" {
  name                = "iis-nic"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  ip_configuration {
    name                          = "iis-ip-config"
    subnet_id                     = azurerm_subnet.app_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.iis_pip.id
  }
}

resource "azurerm_network_interface" "prometheus_nic" {
  name                = "prometheus-nic"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  ip_configuration {
    name                          = "prometheus-ip-config"
    subnet_id                     = azurerm_subnet.backend_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.prometheus_pip.id
  }
}

resource "azurerm_network_interface" "loki_nic" {
  name                = "loki-nic"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  ip_configuration {
    name                          = "loki-ip-config"
    subnet_id                     = azurerm_subnet.backend_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.loki_pip.id
  }
}

resource "azurerm_network_interface" "grafana_nic" {
  name                = "grafana-nic"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  ip_configuration {
    name                          = "grafana-ip-config"
    subnet_id                     = azurerm_subnet.backend_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.grafana_pip.id
  }
}

# ─────────────────────────────────────────────────────────────
# Associate NSGs with NICs
# ─────────────────────────────────────────────────────────────
resource "azurerm_network_interface_security_group_association" "iis_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.iis_nic.id
  network_security_group_id = azurerm_network_security_group.iis_nsg.id
}

resource "azurerm_network_interface_security_group_association" "prometheus_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.prometheus_nic.id
  network_security_group_id = azurerm_network_security_group.prometheus_nsg.id
}

resource "azurerm_network_interface_security_group_association" "loki_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.loki_nic.id
  network_security_group_id = azurerm_network_security_group.loki_nsg.id
}

resource "azurerm_network_interface_security_group_association" "grafana_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.grafana_nic.id
  network_security_group_id = azurerm_network_security_group.grafana_nsg.id
}
