# Can Open-Source Monitoring Replace PRTG on Windows? I Built and Tested It.

*Posted by Mohammadreza Adelvand · DevOps Learning Series — Part 2*

---

## The Question This Post Answers

Most monitoring tutorials show you Linux servers with Node Exporter.
But enterprise environments run **Windows Server + IIS** — and that's where
tools like PRTG earn their $10,000/year license fees.

I wanted to know: can the open-source Prometheus/Grafana/Loki/Alloy stack
actually replace PRTG in a Windows/IIS enterprise environment?
Specifically, can it work in the **hardened enterprise** scenario where
WMI access is restricted by Group Policy?

**Short answer: Yes. And I built the proof.**

This post walks through everything I built, every decision, every command.
By the end you'll have a fully working Windows monitoring stack on Azure —
and you'll understand *why* each piece works the way it does.

---

## Why This Is Harder Than Linux Monitoring

On Linux, monitoring is straightforward:
- Install Node Exporter → exposes metrics at `:9100/metrics`
- Done.

On Windows, you have multiple options for reading system data,
and each has enterprise implications:

| Method | What it does | Enterprise problem |
|---|---|---|
| **WMI** (Windows Management Instrumentation) | Microsoft's "official" query interface | Often restricted by Group Policy in hardened environments |
| **PDH** (Performance Data Helper) | Lower-level Windows perf counter API | Always available, not restricted |
| **Windows Event Log API** | Direct event log access | Always available |
| **registry reads** | Direct registry access | Available with correct permissions |

**PRTG's problem:** It leans heavily on WMI.
In enterprises following CIS benchmarks or DISA STIGs, WMI remote access is
often disabled or heavily restricted. This is exactly when PRTG calls
break silently — no metrics, no errors, no visibility.

**Our solution:** Grafana Alloy's `prometheus.exporter.windows` component
uses PDH and the Windows Event Log API by default. WMI optional, not required.

---

## Architecture Overview

Before any commands, let me explain what we're building and why.

```
YOUR LAPTOP
    │
    ├── RDP to Windows VM (port 3389) — to set up IIS and Alloy
    ├── SSH to Linux VMs (port 22)    — to set up Prometheus/Loki/Grafana
    └── Browser to Grafana (port 3000) — to see dashboards

AZURE VIRTUAL NETWORK (10.0.0.0/16)
    │
    ├── app-subnet (10.0.1.0/24)
    │   └── Windows Server 2022 VM
    │       ├── IIS — serves web traffic (port 80)
    │       └── Grafana Alloy — collects metrics + logs
    │               │ remote_write metrics → 9090
    │               └── log push          → 3100
    │
    └── backend-subnet (10.0.2.0/24)
        ├── Prometheus VM — stores metrics (port 9090)
        ├── Loki VM       — stores logs (port 3100)
        └── Grafana VM    — dashboards (port 3000)
                                └── Alertmanager → Teams
```

**Key design insight from the SVG diagram I created:**
The monitoring backend is in a separate subnet from the application servers.
Prometheus and Loki are unreachable from the internet — they only accept
connections from the app-subnet (Alloy pushing data) and the admin workstation.
This is real enterprise network segmentation.

---

## What You Need Before Starting

1. **An Azure account** — [portal.azure.com](https://portal.azure.com)
   New accounts get $200 free credit + 12 months free tier.
   You'll use the free B1S VM tier.

2. **Azure CLI installed** on your laptop:
   - macOS: `brew install azure-cli`
   - Windows: [Download MSI installer](https://aka.ms/installazurecliwindows)
   - Ubuntu: `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash`

3. **Terraform installed**: [terraform.io/downloads](https://developer.hashicorp.com/terraform/install)

4. **Microsoft Remote Desktop** (to connect to the Windows VM):
   - macOS: [Download from App Store](https://apps.apple.com/app/microsoft-remote-desktop/id1295203466)
   - Windows: Built in (search "Remote Desktop Connection")

5. **Your public IP**: `curl ifconfig.me`

---

## Step 1 — Azure Login and Free Tier Setup

**Step 1.1** Log in to Azure CLI on your laptop:
```bash
az login
```
A browser window opens. Sign in with your Azure account.
When done, you'll see your subscription listed in the terminal.

**Step 1.2** Note your subscription ID (you'll need it):
```bash
az account show --query id -o tsv
```
Copy that ID — it looks like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.

**Step 1.3** Check you're on free tier eligibility:
```bash
az account show --query "subscriptionPolicies.spendingLimit"
```
If it says `"On"` — good, you have spending limits protecting you from surprise charges.

---

## Step 2 — Create Your SSH Key Pair

> 💡 **Why an SSH key?** SSH keys are like a very long password that
> you never have to type. Your laptop holds the private key (secret),
> Azure holds the public key (not secret). If they match, you're authenticated.

**Step 2.1** Generate the key pair:
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_monitoring -C "azure-monitoring-stack"
```
- When asked for a passphrase: press Enter twice (no passphrase for now)
- This creates two files:
  - `~/.ssh/azure_monitoring` — your **private key** (NEVER share this)
  - `~/.ssh/azure_monitoring.pub` — your **public key** (safe to share)

**Step 2.2** Verify both files were created:
```bash
ls -la ~/.ssh/azure_monitoring*
```
You should see both files.

---

## Step 3 — Clone the Repo and Configure Terraform

**Step 3.1** Clone this repository:
```bash
git clone https://github.com/YOUR_USERNAME/windows-monitoring
cd windows-monitoring
```

**Step 3.2** Create the Terraform variables file:
```bash
cd terraform-azure
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Fill in:
```hcl
admin_ip               = "203.0.113.45"        # your IP from curl ifconfig.me
windows_admin_password = "Str0ng!Pass#2024"    # 12+ chars, uppercase, number, symbol
```

> ⚠️ **Azure password requirements:** Windows VM passwords must have:
> uppercase letter + lowercase letter + number + special character + 12+ characters.
> Example: `M0nit0ring@Stack!`

---

## Step 4 — Provision Azure Infrastructure with Terraform

> 💡 **What Terraform does here:** Instead of clicking through 50 Azure portal
> screens to create VMs, subnets, firewall rules, and network interfaces —
> we describe everything in code files and run one command.
> This is **Infrastructure as Code** — a core DevOps skill.

**Step 4.1** Initialize Terraform (downloads the Azure provider):
```bash
terraform init
```
You should see: `Terraform has been successfully initialized!`

**Step 4.2** Preview what will be created:
```bash
terraform plan
```
Count the resources. You should see ~20 resources planned:
4 VMs, 4 NICs, 4 public IPs, 4 NSGs, 1 VNet, 2 subnets, etc.

**Step 4.3** Apply (create everything):
```bash
terraform apply
```
Type `yes` when prompted. This takes **5–10 minutes** for Windows VM
(Windows VMs take longer than Linux to provision).

**Step 4.4** Save ALL the output IPs:
```
windows_iis_public_ip    = "20.x.x.x"    ← for RDP
windows_iis_private_ip   = "10.0.1.x"
prometheus_public_ip     = "20.x.x.x"    ← for SSH
prometheus_private_ip    = "10.0.2.x"    ← SAVE THIS
loki_public_ip           = "20.x.x.x"    ← for SSH
loki_private_ip          = "10.0.2.x"    ← SAVE THIS
grafana_public_ip        = "20.x.x.x"    ← for browser
```

> **Why private IPs?** Private IPs never change when you stop/start VMs.
> Public IPs are assigned fresh each boot. All inter-service configs
> must use private IPs.

---

## Step 5 — Set Up the Linux Backend (Prometheus, Loki, Grafana)

The monitoring backend runs on Linux — Prometheus, Loki, and Grafana
all run better on Linux and you get 3 free B1S Linux VMs on Azure.

### 5.1 — Install Prometheus

**Step 5.1.1** SSH into the Prometheus server:
```bash
ssh -i ~/.ssh/azure_monitoring azureuser@<PROMETHEUS_PUBLIC_IP>
sudo -i
```

**Step 5.1.2** Run the Prometheus setup script:
```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/windows-monitoring/main/scripts/linux/install-prometheus.sh
chmod +x install-prometheus.sh
./install-prometheus.sh
```

**Step 5.1.3** Upload the hardened prometheus.yml (from your laptop terminal):
```bash
# Fill in Windows VM private IP
sed "s/WINDOWS_IIS_PRIVATE_IP/10.0.1.X/g" \
    configs/prometheus/prometheus.yml > /tmp/prom-filled.yml

scp -i ~/.ssh/azure_monitoring \
    /tmp/prom-filled.yml \
    azureuser@<PROMETHEUS_PUBLIC_IP>:/tmp/prometheus.yml

scp -i ~/.ssh/azure_monitoring \
    configs/prometheus/alert-rules-windows.yml \
    azureuser@<PROMETHEUS_PUBLIC_IP>:/tmp/
```

Back in SSH:
```bash
cp /tmp/prometheus.yml /etc/prometheus/prometheus.yml
mkdir -p /etc/prometheus/rules
cp /tmp/alert-rules-windows.yml /etc/prometheus/rules/

# Validate before restarting — ALWAYS do this
promtool check config /etc/prometheus/prometheus.yml
promtool check rules /etc/prometheus/rules/alert-rules-windows.yml

systemctl restart prometheus
```

**Verify:** Open `http://<PROMETHEUS_PUBLIC_IP>:9090` in your browser.
Click **Status → Targets**. You should see `prometheus` as UP.

### 5.2 — Install Loki

```bash
ssh -i ~/.ssh/azure_monitoring azureuser@<LOKI_PUBLIC_IP>
sudo -i
wget https://raw.githubusercontent.com/YOUR_USERNAME/windows-monitoring/main/scripts/linux/install-loki.sh
chmod +x install-loki.sh
./install-loki.sh
```

Wait for: `curl http://localhost:3100/ready` → returns `ready`

### 5.3 — Install Grafana

```bash
ssh -i ~/.ssh/azure_monitoring azureuser@<GRAFANA_PUBLIC_IP>
sudo -i
wget https://raw.githubusercontent.com/YOUR_USERNAME/windows-monitoring/main/scripts/linux/install-grafana.sh
chmod +x install-grafana.sh
./install-grafana.sh
```

**Verify:** Open `http://<GRAFANA_PUBLIC_IP>:3000` and log in with `admin/admin`.

---

## Step 6 — Set Up Windows Server + IIS

Now the most interesting part — connecting to the Windows VM.

### 6.1 — Connect via RDP

> 💡 **What is RDP?** Remote Desktop Protocol — it gives you a full
> graphical Windows desktop on your laptop, as if you were sitting at
> the server. It's how Windows servers are managed in the enterprise.

**macOS — Microsoft Remote Desktop:**
1. Open Microsoft Remote Desktop
2. Click **+** → **Add PC**
3. PC name: `<WINDOWS_IIS_PUBLIC_IP>`
4. Click **Add**
5. Double-click the PC → Username: `azureadmin` → Password: (what you set in tfvars)
6. Click **Continue** when warned about the certificate

**Windows — Built-in Remote Desktop:**
1. Press `Win + R` → type `mstsc` → Enter
2. Computer: `<WINDOWS_IIS_PUBLIC_IP>`
3. Click **Connect** → enter `azureadmin` and your password

> **What you'll see:** A Windows Server 2022 desktop — like a normal Windows
> desktop but in a window on your laptop. Everything you do here happens on
> the Azure VM.

### 6.2 — Open PowerShell as Administrator

1. On the Windows desktop, right-click the **Start** button (bottom-left)
2. Click **Windows PowerShell (Admin)** or **Terminal (Admin)**
3. Click **Yes** when User Account Control asks for permission

> 💡 **Why Administrator?** Installing software and changing system settings
> requires elevated permissions on Windows — same reason you use `sudo` on Linux.

### 6.3 — Allow Script Execution

By default, Windows doesn't allow running downloaded scripts.
Run this once to allow it for this session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
Type `Y` to confirm.

### 6.4 — Download and Run the IIS Setup Script

```powershell
# Download the script
Invoke-WebRequest `
    -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/windows-monitoring/main/scripts/windows/01-install-iis.ps1" `
    -OutFile "$env:TEMP\01-install-iis.ps1"

# Run it
& "$env:TEMP\01-install-iis.ps1"
```

This installs IIS with logging enabled and creates test web pages.
It takes 1–3 minutes.

**Verify IIS is working:**
Open a browser on your laptop and go to `http://<WINDOWS_IIS_PUBLIC_IP>`.
You should see the "Windows Server + IIS" monitoring test page.

> ✅ **Checkpoint:** IIS is running and accessible from your laptop.

### 6.5 — Install Grafana Alloy on Windows

Now the critical step — the agent that makes our stack enterprise-ready.

**Step 6.5.1** Download the Alloy installation script to the Windows VM:
```powershell
Invoke-WebRequest `
    -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/windows-monitoring/main/scripts/windows/02-install-alloy.ps1" `
    -OutFile "$env:TEMP\02-install-alloy.ps1"
```

**Step 6.5.2** BEFORE running it, open the file and fill in your private IPs:
```powershell
notepad "$env:TEMP\02-install-alloy.ps1"
```

Find these two lines near the top:
```powershell
$PROMETHEUS_PRIVATE_IP = "10.0.2.X"   # ← replace with actual Prometheus private IP
$LOKI_PRIVATE_IP       = "10.0.2.X"   # ← replace with actual Loki private IP
```

Change both to the private IPs you saved from `terraform output`. Save and close Notepad.

**Step 6.5.3** Run the script:
```powershell
& "$env:TEMP\02-install-alloy.ps1"
```

What happens:
1. Downloads and installs Alloy as a Windows service
2. Writes our `config.alloy` to `C:\Program Files\GrafanaLabs\Alloy\config.alloy`
3. Starts the Alloy service
4. Verifies the Alloy UI is running

**Step 6.5.4** Verify Alloy is running:
```powershell
Get-Service -Name "Alloy"
# Should show: Status=Running
```

> ✅ **Checkpoint:** Alloy service is `Running`.

---

## Step 7 — Verify Data Is Flowing

This is the moment of truth — checking that metrics and logs are actually
reaching Prometheus and Loki from the Windows server.

### 7.1 — Check Prometheus Targets

Open `http://<PROMETHEUS_PUBLIC_IP>:9090` in your browser.
Click **Status → Targets**.

You should see a new target: `windows-iis-metrics` with state **UP**.

> ⚠️ If it shows **DOWN**: The most common cause is a typo in the private IP
> you entered in the Alloy config. RDP back to Windows, open
> `C:\Program Files\GrafanaLabs\Alloy\config.alloy` in Notepad,
> check the Prometheus IP, then run `Restart-Service Alloy` in PowerShell.

### 7.2 — Check the Alloy UI

Open `http://<WINDOWS_IIS_PUBLIC_IP>:12345` in your browser.
Click **Graph** in the left sidebar.

You should see a data flow diagram showing:
- `prometheus.exporter.windows.iis_server` → `prometheus.scrape.windows_metrics` → `prometheus.remote_write.prometheus_backend`
- `loki.source.windowsevent.system_events` → `loki.write.loki_backend`
- `loki.source.file.iis_access_logs` → `loki.write.loki_backend`

Green means data is flowing. This is the Alloy pipeline visualizer — one of
the most useful debugging tools in the stack.

### 7.3 — Run a Prometheus Query to Confirm Windows Metrics

In the Prometheus UI (`http://<PROMETHEUS_PUBLIC_IP>:9090`):

Click **Graph** → paste this query and click **Execute**:
```
windows_cpu_time_total
```

You should see multiple metric lines — one per CPU mode (idle, user, privileged).
If you see data, Windows metrics are flowing. 🎉

Try also:
```
windows_iis_requests_total
```
This shows IIS request counts. Open the IIS test page in your browser a few
times to generate some requests, then re-run the query.

### 7.4 — Check Loki Logs in Grafana

**Step 7.4.1** Log into Grafana at `http://<GRAFANA_PUBLIC_IP>:3000`

**Step 7.4.2** Add Prometheus data source:
- Left sidebar → **Connections** → **Data sources** → **Add data source**
- Select **Prometheus** → URL: `http://<PROMETHEUS_PRIVATE_IP>:9090`
- Click **Save & test** → should show ✅

**Step 7.4.3** Add Loki data source:
- **Add data source** → **Loki** → URL: `http://<LOKI_PRIVATE_IP>:3100`
- Click **Save & test** → should show ✅

**Step 7.4.4** Explore Windows Event Logs:
- Left sidebar → **Explore**
- Data source: **Loki**
- Click **Label browser** → you should see `job = "windows-eventlog"`
- Select it → click **Show logs**

You should see Windows Event Log entries flowing in. This is the System and
Application event log from the Windows Server, streamed in real time.

---

## Step 8 — Import the Windows IIS Dashboard

**Step 8.1** In Grafana: **Dashboards** → **New** → **Import**

**Step 8.2** Click **Upload dashboard JSON file** →
upload `dashboards/windows-iis-overview.json` from this repo.

**Step 8.3** Select your Prometheus and Loki data sources when prompted.

**Step 8.4** Click **Import**.

You now have a dashboard showing:
- CPU utilization over time
- Memory available (%)
- Disk usage on C:
- IIS request rate
- Active IIS connections
- Windows Event Log stream

---

## Step 9 — Set Up Microsoft Teams Alerting

> 💡 Enterprise environments use Teams for internal communication.
> Connecting Grafana/Alertmanager to Teams is a common enterprise requirement.

### 9.1 — Create a Teams Incoming Webhook

1. Open **Microsoft Teams**
2. Find or create a channel for alerts (e.g. `#monitoring-alerts`)
3. Click **...** (More options) next to the channel name
4. Click **Connectors** → search for "Incoming Webhook" → **Configure**
5. Name: `Grafana Monitoring` → click **Create**
6. Copy the webhook URL (starts with `https://xxxx.webhook.office.com/...`)

### 9.2 — Add Webhook to Alertmanager Config

Edit `configs/alertmanager/alertmanager.yml` and replace `TEAMS_WEBHOOK_URL`
with your actual URL.

Then upload to the Prometheus server (Alertmanager runs alongside Prometheus
in this setup):

```bash
# From your laptop:
scp -i ~/.ssh/azure_monitoring \
    configs/alertmanager/alertmanager.yml \
    azureuser@<PROMETHEUS_PUBLIC_IP>:/tmp/alertmanager.yml
```

SSH into Prometheus:
```bash
sudo cp /tmp/alertmanager.yml /etc/alertmanager/alertmanager.yml
sudo systemctl restart alertmanager
```

---

## The WMI-Free Architecture — Why It Matters

Let me show you exactly what Alloy is doing differently from a WMI-based tool:

### Traditional WMI-based monitoring (PRTG approach)
```
Monitoring Server → WMI query over network → Windows Server
                 ← metric value
```
This requires:
- WMI remote access enabled (often blocked by Group Policy)
- DCOM ports open through firewall
- The monitoring account in specific local groups
- Often fails silently when GPO changes

### Alloy's approach (what we built)
```
Windows Server → Alloy reads PDH counters locally → pushes to Prometheus
               → Alloy reads Event Log API locally → pushes to Loki
```

No inbound connections needed. No WMI. The agent runs locally on the server
and pushes data out — this is called a **push model**, and it's far more
firewall-friendly and enterprise-compatible.

---

## vs. PRTG — The Honest Comparison

| Capability | PRTG | Our Stack |
|---|---|---|
| **Windows/IIS monitoring** | ✅ Excellent (WMI-based) | ✅ Excellent (PDH-based, WMI-free) |
| **Works with restricted WMI** | ❌ Often breaks | ✅ Always works |
| **Log aggregation** | ❌ Metrics only | ✅ Full log store (Loki) |
| **Dashboard quality** | ⚠️ Limited, proprietary | ✅ Grafana — industry standard |
| **Alert routing** | ⚠️ Basic | ✅ Alertmanager (Teams, PagerDuty, Slack) |
| **Cost** | 💰 $3,000–$20,000/year | 🆓 Free (OSS) |
| **Config as Code** | ❌ GUI only | ✅ All configs in Git |
| **Setup complexity** | Low (wizard-driven) | Medium (but that's what this guide solves) |
| **Vendor support/SLA** | ✅ Included | Optional (Grafana Labs commercial) |
| **Scales to 100s of servers** | ⚠️ Sensor pricing | ✅ Yes (Prometheus federation) |

**Verdict:** For teams comfortable with DevOps tooling, this stack is
a legitimate PRTG replacement at zero license cost. The only real advantage
PRTG has is simpler initial setup for non-technical users — but that
advantage disappears as soon as WMI restrictions are introduced.

---

## Troubleshooting Guide

### "Alloy service won't start on Windows"
```powershell
# Check event log for Alloy errors
Get-EventLog -LogName Application -Source "Alloy" -Newest 20

# Common cause: syntax error in config.alloy
# Validate the config manually:
& "C:\Program Files\GrafanaLabs\Alloy\alloy.exe" run --config.file="C:\Program Files\GrafanaLabs\Alloy\config.alloy" 2>&1 | head -20
```

### "Prometheus target shows DOWN for windows-iis-metrics"
```
1. Is Alloy running?  → Get-Service Alloy
2. Is the private IP correct in config.alloy?  → notepad "C:\Program Files\GrafanaLabs\Alloy\config.alloy"
3. Can Windows reach Prometheus?  → Test-NetConnection -ComputerName 10.0.2.X -Port 9090
4. Check NSG: Azure Portal → prometheus-nsg → Inbound rules → verify port 9090 open to app-subnet (10.0.1.0/24)
```

### "No IIS access logs in Loki"
```
1. Verify log files exist:  Get-ChildItem C:\inetpub\logs\LogFiles\W3SVC1\
2. Open the IIS test page in a browser (generates log entries)
3. Check Alloy UI at :12345 → look for loki.source.file.iis_access_logs component
4. If no log files: check IIS logging is enabled in IIS Manager → your site → Logging
```

### "Windows Event Logs not appearing in Grafana"
```
1. Check Alloy UI → loki.source.windowsevent components — are they green?
2. In Grafana Explore → Loki → query: {job="windows-eventlog"}
3. Trigger a test event on Windows: eventvwr → right click → Create Custom View
4. Check Loki is healthy: curl http://<LOKI_PRIVATE_IP>:3100/ready
```

---

## What I Learned Building This

**WMI is the hidden debt of Windows monitoring.**
Every PRTG customer is one Group Policy update away from losing monitoring.
The PDH path makes the stack genuinely more reliable in enterprise environments.

**Push vs. pull changes the network model.**
PRTG pulls from servers (inbound connections required). Alloy pushes to the backend
(only outbound connections required). This means Alloy works with more restrictive
firewall rules — important in air-gapped or high-security environments.

**Azure free tier is genuinely useful for this.**
4 B1S VMs (1 Windows + 3 Linux) running 24/7 for a month = ~720 hours.
The free tier gives you 750 hours/month for 12 months. Perfect fit for a
DevOps learning lab.

**The Alloy UI at :12345 is invaluable.**
When data isn't flowing, the pipeline visualizer immediately shows you which
component is broken. I can't overstate how much debugging time this saves.

---

## Cost Awareness (Free Tier Limits)

Azure free tier gives you:
- **750 hours/month** of B1S Windows VM (enough for 1 VM running 24/7)
- **750 hours/month** of B1S Linux VMs

With 4 VMs running 24/7:
- Windows VM: ~744 hours/month ≈ free ✅
- Linux VMs: 3 × 744 = 2,232 hours needed — you have 750 total

**Recommendation:** Run Linux VMs only when testing. Stop them when not needed:
```bash
az vm deallocate --resource-group monitoring-stack-rg --name prometheus-server
az vm deallocate --resource-group monitoring-stack-rg --name loki-server
az vm deallocate --resource-group monitoring-stack-rg --name grafana-server
```

And start them when needed:
```bash
az vm start --resource-group monitoring-stack-rg --name prometheus-server
# (and so on for loki and grafana)
```

> ⚠️ When you stop and start VMs, their **public IPs change**.
> Private IPs stay the same. This is why all internal configs use private IPs.

---

## Cleanup — Delete Everything When Done

When you're done testing, delete all Azure resources to avoid charges:
```bash
cd terraform-azure
terraform destroy
```
Type `yes` when prompted. This deletes ALL resources including the VMs, network,
and public IPs. Your Azure bill goes to zero.

---

*Source: [github.com/YOUR_USERNAME/windows-monitoring](https://github.com/YOUR_USERNAME/windows-monitoring)*
*Architecture diagram: enterprise_windows_iis_observability_architecture.svg*
