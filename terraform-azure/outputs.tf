output "windows_iis_public_ip" {
  description = "Windows IIS server — RDP to this IP on port 3389"
  value       = azurerm_public_ip.iis_pip.ip_address
}

output "windows_iis_private_ip" {
  description = "Windows IIS private IP — used in Alloy config"
  value       = azurerm_network_interface.iis_nic.private_ip_address
}

output "prometheus_public_ip" {
  description = "Prometheus server — SSH to this IP"
  value       = azurerm_public_ip.prometheus_pip.ip_address
}

output "prometheus_private_ip" {
  description = "Prometheus PRIVATE IP — use in Alloy config and Grafana datasource"
  value       = azurerm_network_interface.prometheus_nic.private_ip_address
}

output "loki_private_ip" {
  description = "Loki PRIVATE IP — use in Alloy config and Grafana datasource"
  value       = azurerm_network_interface.loki_nic.private_ip_address
}

output "grafana_public_ip" {
  description = "Grafana server — open http://<IP>:3000 in browser"
  value       = azurerm_public_ip.grafana_pip.ip_address
}

output "rdp_command" {
  description = "How to RDP into Windows VM"
  value       = "Open Microsoft Remote Desktop → Add PC → PC name: ${azurerm_public_ip.iis_pip.ip_address} → User: azureadmin"
}

output "ssh_prometheus" {
  description = "SSH command for Prometheus server"
  value       = "ssh -i ~/.ssh/azure_monitoring azureuser@${azurerm_public_ip.prometheus_pip.ip_address}"
}

output "ssh_loki" {
  description = "SSH command for Loki — goes THROUGH Prometheus (jump host) because Loki has no public IP"
  value       = "ssh -i ~/.ssh/azure_monitoring -J azureuser@${azurerm_public_ip.prometheus_pip.ip_address} azureuser@${azurerm_network_interface.loki_nic.private_ip_address}"
}

output "ssh_grafana" {
  description = "SSH command for Grafana server"
  value       = "ssh -i ~/.ssh/azure_monitoring azureuser@${azurerm_public_ip.grafana_pip.ip_address}"
}

output "next_steps" {
  value = <<-EOT
    ✅ Azure infrastructure created! Save everything below.

    ══════════════════════════════════════════
    PUBLIC IPs — Static, never change
    ══════════════════════════════════════════
    Windows IIS:  ${azurerm_public_ip.iis_pip.ip_address}   (RDP)
    Prometheus:   ${azurerm_public_ip.prometheus_pip.ip_address}   (SSH + UI :9090)
    Grafana:      ${azurerm_public_ip.grafana_pip.ip_address}   (SSH + UI :3000)

    ══════════════════════════════════════════
    PRIVATE IPs — Save these for Alloy config
    ══════════════════════════════════════════
    Prometheus private: ${azurerm_network_interface.prometheus_nic.private_ip_address}
    Loki private:       ${azurerm_network_interface.loki_nic.private_ip_address}
    Windows IIS private:${azurerm_network_interface.iis_nic.private_ip_address}

    ══════════════════════════════════════════
    SSH COMMANDS
    ══════════════════════════════════════════
    Prometheus: ssh -i ~/.ssh/azure_monitoring azureuser@${azurerm_public_ip.prometheus_pip.ip_address}
    Loki:       ssh -i ~/.ssh/azure_monitoring -J azureuser@${azurerm_public_ip.prometheus_pip.ip_address} azureuser@${azurerm_network_interface.loki_nic.private_ip_address}
    Grafana:    ssh -i ~/.ssh/azure_monitoring azureuser@${azurerm_public_ip.grafana_pip.ip_address}

    ⚠️  Loki has NO public IP (free account limit = 3 IPs).
    Use the SSH jump command above — it routes through Prometheus automatically.

    ══════════════════════════════════════════
    DEPLOYMENT ORDER
    ══════════════════════════════════════════
    1. SSH Prometheus → run scripts/linux/install-prometheus.sh
    2. SSH Loki       → run scripts/linux/install-loki.sh
    3. SSH Grafana    → run scripts/linux/install-grafana.sh
    4. RDP Windows    → run scripts/windows/01-install-iis.ps1
    5. RDP Windows    → run scripts/windows/02-install-alloy.ps1 (fill in private IPs first!)
    6. Open Grafana:    http://${azurerm_public_ip.grafana_pip.ip_address}:3000
  EOT
}
