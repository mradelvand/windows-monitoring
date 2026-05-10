variable "resource_group_name" {
  description = "Name of the Azure resource group (acts as a folder for all resources)"
  type        = string
  default     = "monitoring-stack-rg"
}

variable "location" {
  description = "Azure region. 'eastus' is usually cheapest and has free tier availability."
  type        = string
  default     = "eastus"
}

variable "vm_size_windows" {
  description = "Azure VM size for Windows IIS server. B1S = free tier (1 vCPU, 1GB RAM)"
  type        = string
  default     = "Standard_B1s"
}

variable "vm_size_linux" {
  description = "Azure VM size for Linux backend servers. B1S = free tier"
  type        = string
  default     = "Standard_B1s"
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
