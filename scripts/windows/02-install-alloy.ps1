# ============================================================
# 02-install-alloy.ps1 — Install Grafana Alloy on Windows Server
#
# BEFORE RUNNING:
#   Fill in your private IPs at the top of this script!
#   (Get them from `terraform output` after running terraform apply)
#
# HOW TO RUN:
#   1. RDP into the Windows IIS VM
#   2. Open PowerShell as Administrator
#   3. .\02-install-alloy.ps1
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# ⚠️  FILL THESE IN BEFORE RUNNING
# ============================================================
$PROMETHEUS_PRIVATE_IP = "10.0.2.X"   # ← replace with actual Prometheus private IP
$LOKI_PRIVATE_IP       = "10.0.2.X"   # ← replace with actual Loki private IP
# ============================================================

if ($PROMETHEUS_PRIVATE_IP -eq "10.0.2.X" -or $LOKI_PRIVATE_IP -eq "10.0.2.X") {
    Write-Host "❌ ERROR: You must fill in PROMETHEUS_PRIVATE_IP and LOKI_PRIVATE_IP!" -ForegroundColor Red
    Write-Host "   Edit this script and replace the placeholder IPs." -ForegroundColor Red
    exit 1
}

Write-Host "=== Installing Grafana Alloy on Windows ===" -ForegroundColor Cyan
Write-Host "  Prometheus: $PROMETHEUS_PRIVATE_IP" -ForegroundColor Gray
Write-Host "  Loki:       $LOKI_PRIVATE_IP" -ForegroundColor Gray

# ── Step 1: Download Alloy installer ────────────────────────
Write-Host "=== Step 1: Downloading Grafana Alloy ===" -ForegroundColor Cyan

$alloyVersion = "1.4.2"
$downloadUrl  = "https://github.com/grafana/alloy/releases/download/v$alloyVersion/alloy-installer-windows-amd64.exe"
$installerPath = "$env:TEMP\alloy-installer.exe"

Write-Host "  Downloading Alloy v$alloyVersion..." -ForegroundColor Gray
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
Write-Host "✅ Downloaded" -ForegroundColor Green

# ── Step 2: Install Alloy silently ──────────────────────────
Write-Host "=== Step 2: Installing Alloy ===" -ForegroundColor Cyan

# /S = silent install, no GUI
Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
Write-Host "✅ Alloy installed" -ForegroundColor Green

# Default install location
$alloyDir    = "C:\Program Files\GrafanaLabs\Alloy"
$alloyConfig = "$alloyDir\config.alloy"

# ── Step 3: Write the Alloy config file ─────────────────────
Write-Host "=== Step 3: Writing Alloy config ===" -ForegroundColor Cyan

# This is the key config — this is what makes this stack enterprise-worthy.
# We use prometheus.exporter.windows which uses PDH (Performance Data Helper)
# and the Windows Event Log API — NO WMI REQUIRED.
$configContent = @"
// ============================================================
// Grafana Alloy config for Windows Server + IIS
// WMI-restriction SAFE: uses PDH API + Event Log API
// ============================================================


// ============================================================
// SECTION 1: WINDOWS METRICS via prometheus.exporter.windows
//
// This component is built into Alloy — no separate exporter needed.
// It reads metrics using PDH (Performance Data Helper) API,
// which works even when WMI is restricted by Group Policy.
// ============================================================

prometheus.exporter.windows "iis_server" {
  // List the collectors (metric categories) to enable.
  // Only enable what you need — each one adds some CPU/memory overhead.
  enabled_collectors = [
    "cpu",           // CPU usage per core, idle/user/system time
    "memory",        // RAM usage, available bytes, page faults
    "logical_disk",  // Disk space, I/O rates per drive letter
    "net",           // Network bytes in/out, packets, errors per NIC
    "os",            // OS-level: uptime, handles, threads, processes
    "system",        // System counters: context switches, interrupts
    "service",       // Windows service state (running/stopped/etc)
    "iis",           // IIS: requests/sec, bytes sent, connections, errors
    "process",       // Per-process CPU, memory (optional, can be noisy)
  ]

  // IIS collector: only monitor specific sites, not all of them
  // "^.*\$" means "match everything" — monitor ALL IIS sites
  // To restrict: site_include = "^(Default Web Site|MySite)\$"
  iis {
    site_include = "^.*\$"
    app_exclude  = "^/LM/W3SVC.*\$"  // exclude internal IIS metadata apps
  }

  // Service collector: monitor specific Windows services
  // This avoids collecting hundreds of obscure service metrics
  service {
    where_clause = "Name LIKE 'W3SVC' OR Name LIKE 'WAS' OR Name LIKE 'Alloy'"
    // W3SVC = IIS World Wide Web Publishing Service
    // WAS   = Windows Process Activation Service (required by IIS)
    // Alloy = Grafana Alloy itself (self-monitoring)
  }

  // Process collector: which processes to track
  process {
    include = "^(w3wp|iis|svchost|alloy).*"
    // w3wp = IIS worker process (one per app pool)
    // iis  = IIS core processes
  }
}

// Scrape the windows exporter and forward metrics to Prometheus
prometheus.scrape "windows_metrics" {
  targets    = prometheus.exporter.windows.iis_server.targets
  forward_to = [prometheus.remote_write.prometheus_backend.receiver]

  scrape_interval = "30s"   // collect every 30 seconds
  // Note: 15s is default, but B1S VMs are small — 30s is kinder to CPU
}

// Send metrics to Prometheus via remote_write
// remote_write = Alloy PUSHES to Prometheus (better than pull through firewalls)
prometheus.remote_write "prometheus_backend" {
  endpoint {
    url = "http://${PROMETHEUS_PRIVATE_IP}:9090/api/v1/write"

    queue_config {
      max_samples_per_send = 1000
      batch_send_deadline  = "5s"
      // If Prometheus is temporarily down, queue metrics locally
      // and retry — no data loss
    }
  }
}


// ============================================================
// SECTION 2: WINDOWS EVENT LOGS via loki.source.windowsevent
//
// Reads from the Windows Event Log directly (not WMI).
// Streams Application and System events to Loki.
// ============================================================

loki.source.windowsevent "application_events" {
  // "Application" log = events from apps (IIS errors, app crashes, etc)
  eventlog_name = "Application"
  xpath_query   = "*"   // collect all events

  // Attach labels to every log line from this source
  labels = {
    job        = "windows-eventlog",
    log_source = "application",
    server     = env("COMPUTERNAME"),   // automatically uses the server's hostname
  }

  forward_to = [loki.write.loki_backend.receiver]
}

loki.source.windowsevent "system_events" {
  // "System" log = OS-level events (driver failures, service stops, etc)
  eventlog_name = "System"
  xpath_query   = "*[System[(Level=1 or Level=2 or Level=3)]]"
  // XPath filter: only collect Critical (1), Error (2), Warning (3)
  // This avoids flooding Loki with thousands of informational events

  labels = {
    job        = "windows-eventlog",
    log_source = "system",
    server     = env("COMPUTERNAME"),
  }

  forward_to = [loki.write.loki_backend.receiver]
}

// ============================================================
// SECTION 3: IIS ACCESS LOGS via loki.source.file
//
// IIS writes W3C format access logs to disk.
// Alloy tails these files — like `tail -f` on Linux.
// ============================================================

loki.source.file "iis_access_logs" {
  targets = [
    {
      // IIS writes one log file per day with date in filename
      // The W3SVC1 directory is for the Default Web Site (site ID 1)
      __path__ = "C:\\inetpub\\logs\\LogFiles\\W3SVC1\\*.log",
      job      = "iis-access-logs",
      log_type = "iis-access",
      site     = "Default Web Site",
      server   = env("COMPUTERNAME"),
    },
  ]

  forward_to = [loki.write.loki_backend.receiver]
}

// Send logs to Loki
loki.write "loki_backend" {
  endpoint {
    url = "http://${LOKI_PRIVATE_IP}:3100/loki/api/v1/push"
  }
}
"@

# Write config to Alloy's config directory
Set-Content -Path $alloyConfig -Value $configContent -Encoding UTF8
Write-Host "✅ Config written to: $alloyConfig" -ForegroundColor Green

# ── Step 4: Restart Alloy service to apply config ───────────
Write-Host "=== Step 4: Starting Alloy service ===" -ForegroundColor Cyan

Restart-Service -Name "Alloy" -Force
Start-Sleep -Seconds 5

$alloyService = Get-Service -Name "Alloy"
if ($alloyService.Status -eq "Running") {
    Write-Host "✅ Alloy service is running" -ForegroundColor Green
} else {
    Write-Host "❌ Alloy service failed to start. Check logs:" -ForegroundColor Red
    Write-Host "   Get-EventLog -LogName Application -Source 'Alloy' -Newest 10" -ForegroundColor Red
    exit 1
}

# ── Step 5: Verify Alloy UI is accessible ───────────────────
Write-Host "=== Step 5: Checking Alloy UI ===" -ForegroundColor Cyan

Start-Sleep -Seconds 3
try {
    $response = Invoke-WebRequest -Uri "http://localhost:12345" -UseBasicParsing -TimeoutSec 5
    Write-Host "✅ Alloy UI is responding (HTTP $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Alloy UI not responding yet — it may still be starting" -ForegroundColor Yellow
    Write-Host "   Try: http://localhost:12345 in a browser in 30 seconds" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Alloy Setup Complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "CHECK ALLOY STATUS:" -ForegroundColor Yellow
Write-Host "  Alloy UI (from your laptop): http://$($(Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing).Content):12345" -ForegroundColor White
Write-Host ""
Write-Host "VERIFY DATA IS FLOWING (from your laptop):" -ForegroundColor Yellow
Write-Host "  Prometheus targets: http://<PROMETHEUS_PUBLIC_IP>:9090/targets" -ForegroundColor White
Write-Host "  Look for job=windows-iis-metrics with state=UP" -ForegroundColor White
Write-Host ""
Write-Host "TROUBLESHOOT:" -ForegroundColor Yellow
Write-Host "  View Alloy logs: Get-EventLog -LogName Application -Source 'Alloy' -Newest 20" -ForegroundColor White
Write-Host "  Restart Alloy:   Restart-Service Alloy" -ForegroundColor White
