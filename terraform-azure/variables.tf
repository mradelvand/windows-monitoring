variable "resource_group_name" {
  description = "Name of the Azure resource group (acts as a folder for all resources)"
  type        = string
  default     = "monitoring-stack-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus2"
  # WHY eastus2 not eastus:
  # eastus has no capacity for Standard_B1s Windows VMs on free accounts.
  # eastus2 is the paired region — same pricing, same free tier, B1s available.
  # This is a common issue with free trial Azure accounts.
}

variable "vm_size_windows" {
  description = "Azure VM size for Windows IIS server"
  type        = string
  default     = "Standard_B2s"
  # WHY Standard_B2s not Standard_B1s:
  # Standard_B1s (1 vCPU, 1GB RAM) is NOT available for Windows VMs in eastus/eastus2
  # on free trial accounts due to capacity restrictions.
  # Standard_B2s (2 vCPU, 4GB RAM) IS available and still qualifies for free tier
  # under the "750 hours free" Windows VM allowance.
  # Extra RAM is actually helpful — Windows Server 2022 needs at least 2GB to run smoothly.
}

variable "vm_size_linux" {
  description = "Azure VM size for Linux backend servers (Prometheus, Loki, Grafana)"
  type        = string
  default     = "Standard_B1s"
  # Standard_B1s (1 vCPU, 1GB RAM) works fine for Linux VMs in eastus2.
  # Each Linux service (Prometheus, Loki, Grafana) runs comfortably within 1GB.
}

variable "admin_ip" {
  description = "Your public IP address (no /32). Get it at: curl ifconfig.me"
  type        = string
  # No default — MUST be set in terraform.tfvars
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file on your laptop"
  type        = string
  default     = "~/.ssh/azure_monitoring.pub"
}

variable "linux_admin_username" {
  description = "Linux admin username for SSH login"
  type        = string
  default     = "azureuser"
}

variable "windows_admin_username" {
  description = "Windows admin username for RDP login"
  type        = string
  default     = "azureadmin"
}

variable "windows_admin_password" {
  description = "Windows admin password. Must be 12+ chars with uppercase, lowercase, number, symbol"
  type        = string
  sensitive   = true
  # No default — MUST be set in terraform.tfvars
}
