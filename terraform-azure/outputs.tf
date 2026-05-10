output "windows_iis_public_ip" {
  description = "Windows IIS server — RDP to this IP with port 3389"
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
  description = "Prometheus PRIVATE IP — use in Alloy config.alloy and Grafana datasource"
  value       = azurerm_network_interface.prometheus_nic.private_ip_address
}

output "loki_public_ip" {
  description = "Loki server — SSH to this IP"
  value       = azurerm_public_ip.loki_pip.ip_address
}

output "loki_private_ip" {
  description = "Loki PRIVATE IP — use in Alloy config.alloy and Grafana datasource"
  value       = azurerm_network_interface.loki_nic.private_ip_address
}

output "grafana_public_ip" {
  description = "Grafana server — open http://<IP>:3000 in browser"
  value       = azurerm_public_ip.grafana_pip.ip_address
}

output "rdp_command" {
  description = "Command to connect to Windows IIS server via RDP (from macOS with Microsoft Remote Desktop)"
  value       = "Open Microsoft Remote Desktop → Add PC → PC name: ${azurerm_public_ip.iis_pip.ip_address} → User: azureadmin"
}

output "ssh_prometheus" {
  description = "SSH command for Prometheus server"
  value       = "ssh -i ~/.ssh/azure_monitoring azureuser@${azurerm_public_ip.prometheus_pip.ip_address}"
}

output "ssh_loki" {
  description = "SSH command for Loki server"
  value       = "ssh -i ~/.ssh/azure_monitoring azureuser@${azurerm_public_ip.loki_pip.ip_address}"
}

output "ssh_grafana" {
  description = "SSH command for Grafana server"
  value       = "ssh -i ~/.ssh/azure_monitoring azureuser@${azurerm_public_ip.grafana_pip.ip_address}"
}

output "next_steps" {
  value = <<-EOT
    ✅ Azure infrastructure created!

    SAVE THESE PRIVATE IPs — you need them in configs:
      Prometheus private IP: ${azurerm_network_interface.prometheus_nic.private_ip_address}
      Loki private IP:       ${azurerm_network_interface.loki_nic.private_ip_address}

    DEPLOYMENT ORDER:
      1. SSH into Prometheus → run scripts/linux/install-prometheus.sh
      2. SSH into Loki       → run scripts/linux/install-loki.sh
      3. SSH into Grafana    → run scripts/linux/install-grafana.sh
      4. RDP into Windows    → run scripts/windows/01-install-iis.ps1
      5. RDP into Windows    → run scripts/windows/02-install-alloy.ps1 (fill in IPs first!)
      6. Open Grafana at http://${azurerm_public_ip.grafana_pip.ip_address}:3000
  EOT
}
