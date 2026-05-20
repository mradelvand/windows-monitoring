#  Enterprise Windows/IIS Observability Stack

> **Prometheus · Grafana · Loki · Grafana Alloy** — Windows Server + IIS on Azure

[![Stack](https://img.shields.io/badge/stack-Prometheus%20%7C%20Grafana%20%7C%20Loki%20%7C%20Alloy-orange)](.)
[![Platform](https://img.shields.io/badge/platform-Azure%20Free%20Tier-blue)](.)
[![OS](https://img.shields.io/badge/app%20server-Windows%20Server%202022%20%2B%20IIS-0078D4)](.)
[![WMI](https://img.shields.io/badge/WMI-NOT%20required-green)](.)

A **production-grade, WMI-restriction-safe** monitoring stack for Windows/IIS
environments — designed as a viable open-source replacement for PRTG in enterprise settings.

---

##  Architecture (matches your SVG design)

```
┌─────────────────────────────────────────────────────────────────────┐
│  INTERNET / USERS                                                    │
│                     HTTP 80 / 443 ↓                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  APPLICATION TIER — Windows Server 2022 + IIS (Azure VM)            │
│                                                                      │
│  ┌──────────────────────────┐   ┌──────────────────────────────┐    │
│  │  Windows Server + IIS    │   │  Windows Server + IIS        │    │
│  │  Web app node 1          │   │  Web app node N              │    │
│  └──────────────────────────┘   └──────────────────────────────┘    │
│  ┌──────────────────────────┐   ┌──────────────────────────────┐    │
│  │  Grafana Alloy (Windows) │   │  Grafana Alloy (Windows)     │    │
│  │  metrics + logs agent    │   │  metrics + logs agent        │    │
│  └──────────────────────────┘   └──────────────────────────────┘    │
│                                                                      │
│  Alloy collects:                    WMI-restriction SAFE ✅          │
│  • prometheus.exporter.windows      Uses PDH + Event Log API        │
│    [iis, cpu, memory, disk, net,    No WMI required                 │
│     service, logical_disk]                                           │
│  • loki.source.windowsevent                                          │
│    [Application + System logs]                                       │
│  • IIS access logs (file tail)                                       │
└─────────────────────────────────────────────────────────────────────┘
        │ remote_write (metrics)       │ log push
        ▼ TCP 9090                     ▼ TCP 3100
┌───────────────────┐         ┌─────────────────────┐
│   Prometheus      │         │       Loki           │
│   Metrics store   │──────── │    Log store         │
│   TCP 9090        │ alerts  │    TCP 3100          │
└─────────┬─────────┘         └──────────┬──────────┘
          │                              │
          └──────────────┬───────────────┘
                         ▼ query
                ┌─────────────────┐
                │    Grafana      │
                │  Dashboards     │──→ Alertmanager ──→ Teams/PagerDuty
                │   TCP 3000      │        TCP 9093
                └─────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  ADMIN ACCESS — VPN / Jump host only                                │
│  Admin workstation │ CI/CD pipeline │ PagerDuty / Teams             │
└─────────────────────────────────────────────────────────────────────┘
```

##  Key Design Decisions

| Decision | Why |
|---|---|
| **Azure Free Tier** | 1× B1S Windows VM + 1× B1S Linux VM free for 12 months |
| **Alloy on Windows (not Promtail)** | Single agent handles metrics AND logs |
| **PDH API instead of WMI** | Works in hardened enterprise environments |
| **Windows Event Log API** | No WMI needed for System/Application event logs |
| **Linux VMs for backend** | Prometheus/Grafana/Loki run best on Linux |
| **Private VNet** | All backend services unreachable from public internet |

## 📁 Structure

```
windows-monitoring/
├── terraform-azure/         # Provision ALL Azure resources
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── network.tf
├── configs/
│   ├── alloy-windows/
│   │   └── config.alloy     # Alloy config for Windows Server
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alert-rules.yml  # Windows-specific alert rules
│   ├── loki/
│   │   └── config.yml
│   ├── grafana/
│   │   └── grafana.ini
│   └── alertmanager/
│       └── alertmanager.yml # Teams webhook config
├── scripts/
│   ├── windows/
│   │   ├── 01-install-iis.ps1         # PowerShell: IIS setup
│   │   ├── 02-install-alloy.ps1       # PowerShell: Alloy install
│   │   └── 03-configure-firewall.ps1  # PowerShell: Windows Firewall
│   └── linux/
│       ├── install-prometheus.sh
│       ├── install-loki.sh
│       └── install-grafana.sh
├── dashboards/
│   └── windows-iis-overview.json      # Importable Grafana dashboard
├── docs/
│   └── blog-post-windows.md           # Full blog post
└── .env.example
```

##  Deployment Order

1. **Terraform** → creates Azure VNet, NSGs, and all VMs
2. **Linux backend** → Prometheus → Loki → Grafana (via SSH + scripts)
3. **Windows IIS VM** → IIS → Alloy (via RDP + PowerShell scripts)
4. **Grafana** → add data sources → import dashboard
5. **Verify** → check Alloy UI, Prometheus targets, Grafana logs panel

## 📚 Blog Post

Full walkthrough: [docs/blog-post-windows.md](./docs/blog-post-windows.md)
